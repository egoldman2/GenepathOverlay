import RealityKit
import SwiftUI
import UIKit

@MainActor
final class OverlayRenderer {
    private struct OutlineState {
        let center: SIMD3<Float>
        let extent: SIMD3<Float>
    }

    private let plateOutlineYOffset: Float = -0.003
    private let wellOverlayYOffset: Float = -0.001
    private let activeOverlayAlpha: CGFloat = 0.88
    private let inactiveOverlayAlpha: CGFloat = 0.16
    private let estimatedTipMarkerRadius: Float = 0.007
    private let overlayAccentColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.96)
    private let overlayAccentGlowColor = UIColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 0.92)
    private let overlayAccentSoftColor = UIColor(red: 0.30, green: 0.68, blue: 1.0, alpha: 0.28)
    private let overlayWhiteBeamColor = UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 0.90)
    private let estimatedTipColor = UIColor(red: 1.0, green: 0.18, blue: 0.08, alpha: 0.42)
    private var rootEntity: Entity?
    private var plateEntities: [PlateID: Entity] = [:]
    private var plateVisualEntities: [PlateID: Entity] = [:]
    private var outlineEdgeEntities: [PlateID: [ModelEntity]] = [:]
    private var wellGroupEntities: [PlateID: Entity] = [:]
    private var wellEntities: [PlateID: [String: Entity]] = [:]
    private var highlightedWellEntities: [PlateID: Entity] = [:]
    private var highlightedWellNames: [PlateID: String] = [:]
    private var outlineStates: [PlateID: OutlineState] = [:]
    private var testPlateContainerEntity: Entity?
    private var testPlateModelEntity: Entity?
    private var estimatedTipEntity: Entity?
    private var testPlateLoadTask: Task<Void, Never>?
    private var loadedTestPlateURL: URL?

    func installIfNeeded(
        content: inout RealityViewContent,
        mapper: CoordinateMapper,
        showTestPlateModel: Bool = false
    ) {
        if let rootEntity {
            if rootEntity.scene == nil {
                content.add(rootEntity)
            }
            installEstimatedTipMarkerIfNeeded(on: rootEntity)
            updateTestPlateVisibility(isVisible: showTestPlateModel)
            return
        }

        let root = Entity()
        root.name = "workflow-root"

        for plate in PlateID.allCases {
            let plateEntity = makePlateEntity(for: plate, mapper: mapper)
            plateEntities[plate] = plateEntity
            root.addChild(plateEntity)
        }

        rootEntity = root
        installEstimatedTipMarkerIfNeeded(on: root)
        content.add(root)

        installTestPlateContainerIfNeeded()
        updateTestPlateVisibility(isVisible: showTestPlateModel)
    }

    func update(
        trackingSnapshot: TrackingSnapshot,
        mapper: CoordinateMapper,
        highlightedCoordinates: [PlateID: Coordinate] = [:],
        showTestPlateModel: Bool = false,
        isTipAdjustmentActive: Bool = false,
        isTipEstimateFrozen: Bool = false
    ) {
        let selectedPlate = highlightedCoordinates.keys.first

        for plate in PlateID.allCases {
            guard let plateEntity = plateEntities[plate] else { continue }
            let anchorState = trackingSnapshot.plateAnchors[plate]
            let isSelectedPlate = selectedPlate == nil || selectedPlate == plate
            let anchorTransform = anchorState?.transform ?? mapper.plateWorldTransform(for: plate)
            plateEntity.transform = Transform(matrix: anchorTransform)
            plateEntity.isEnabled = anchorState != nil || highlightedCoordinates[plate] != nil
            updateOverlayOpacity(for: plate, alpha: isSelectedPlate ? activeOverlayAlpha : inactiveOverlayAlpha)
            updateOutline(
                for: plate,
                center: anchorState?.localBoundsCenter ?? mapper.plateOutlineCenter(for: plate),
                extent: anchorState?.localBoundsExtent ?? mapper.plateOutlineExtent(for: plate)
            )
            updateWellOverlayHeight(
                for: plate,
                center: anchorState?.localBoundsCenter ?? mapper.plateOutlineCenter(for: plate),
                extent: anchorState?.localBoundsExtent ?? mapper.plateOutlineExtent(for: plate),
                mapper: mapper
            )
            updateHighlightedWell(
                for: plate,
                coordinate: isSelectedPlate ? highlightedCoordinates[plate] : nil
            )
        }

        updateTestPlateVisibility(isVisible: showTestPlateModel)
        updateEstimatedTipMarker(
            using: trackingSnapshot,
            isTipAdjustmentActive: isTipAdjustmentActive,
            isTipEstimateFrozen: isTipEstimateFrozen
        )
    }

    func isEstimatedTipInteractionEntity(_ entity: Entity) -> Bool {
        var current: Entity? = entity
        while let candidate = current {
            if candidate.name == "estimated-pipette-tip" || candidate.name.hasPrefix("estimated-pipette-tip-") {
                return true
            }
            current = candidate.parent
        }

        return false
    }

    private func installTestPlateContainerIfNeeded() {
        guard testPlateContainerEntity == nil, let sourcePlate = plateVisualEntities[.source] else { return }

        let container = Entity()
        container.name = "test-plate-container"
        container.isEnabled = false
        sourcePlate.addChild(container)
        testPlateContainerEntity = container
    }

    private func installEstimatedTipMarkerIfNeeded(on root: Entity) {
        guard estimatedTipEntity == nil else { return }

        let tipMaterial = SimpleMaterial(
            color: estimatedTipColor,
            roughness: 0.35,
            isMetallic: false
        )

        let marker = Entity()
        marker.name = "estimated-pipette-tip"
        marker.isEnabled = false
        marker.components.set(InputTargetComponent())
        marker.components.set(CollisionComponent(shapes: [.generateSphere(radius: estimatedTipMarkerRadius * 2.2)]))

        let sphere = ModelEntity(
            mesh: .generateSphere(radius: estimatedTipMarkerRadius),
            materials: [tipMaterial]
        )
        sphere.name = "estimated-pipette-tip-dot"
        sphere.components.set(InputTargetComponent())
        sphere.components.set(CollisionComponent(shapes: [.generateSphere(radius: estimatedTipMarkerRadius * 2.2)]))
        marker.addChild(sphere)

        root.addChild(marker)
        estimatedTipEntity = marker
    }

    private func updateEstimatedTipMarker(
        using trackingSnapshot: TrackingSnapshot,
        isTipAdjustmentActive: Bool,
        isTipEstimateFrozen: Bool
    ) {
        guard let estimatedTipEntity else { return }
        guard let tipWorldPosition = trackingSnapshot.pipetteInput.tipWorldPosition else {
            estimatedTipEntity.isEnabled = false
            return
        }

        estimatedTipEntity.isEnabled = true
        estimatedTipEntity.position = tipWorldPosition
    }

    private func updateTestPlateVisibility(isVisible: Bool) {
        installTestPlateContainerIfNeeded()
        guard let testPlateContainerEntity else { return }

        testPlateContainerEntity.isEnabled = isVisible

        guard isVisible else { return }

        if let testPlateModelEntity {
            testPlateModelEntity.isEnabled = true
            return
        }

        guard testPlateLoadTask == nil else { return }
        guard let assetURL = TestWellPlateAssetLocator.locate() else { return }

        if loadedTestPlateURL == assetURL, testPlateModelEntity != nil {
            return
        }

        testPlateLoadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let entity = try await Entity(contentsOf: assetURL)
                await MainActor.run {
                    self.finishLoadingTestPlate(entity: entity, from: assetURL)
                }
            } catch {
                await MainActor.run {
                    self.testPlateLoadTask = nil
                }
            }
        }
    }

    private func finishLoadingTestPlate(entity: Entity, from assetURL: URL) {
        installTestPlateContainerIfNeeded()
        guard let testPlateContainerEntity else {
            testPlateLoadTask = nil
            return
        }

        entity.name = "test-well-plate"
        testPlateContainerEntity.addChild(entity)

        // Center the loaded model on the simulated anchor so mismatched USDZ pivots
        // do not shift the plate away from the expected tracking pose.
        let bounds = entity.visualBounds(relativeTo: testPlateContainerEntity)
        entity.position = -bounds.center
        entity.orientation = simd_quatf()
        entity.scale = SIMD3<Float>(repeating: 1)

        testPlateModelEntity = entity
        loadedTestPlateURL = assetURL
        testPlateLoadTask = nil
    }

    private func makePlateEntity(for plate: PlateID, mapper: CoordinateMapper) -> Entity {
        let anchorRoot = Entity()
        anchorRoot.name = "\(plate.rawValue)-plate"
        anchorRoot.transform = Transform(matrix: mapper.plateWorldTransform(for: plate))

        let visualRoot = Entity()
        visualRoot.name = "\(plate.rawValue)-plate-visuals"
        anchorRoot.addChild(visualRoot)
        plateVisualEntities[plate] = visualRoot

        let thickness: Float = 0.0035
        var edges: [ModelEntity] = []
        for index in 0..<4 {
            let edgeEntity = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(repeating: thickness), cornerRadius: min(thickness * 0.25, 0.001)),
                materials: [outlineMaterial(alpha: activeOverlayAlpha)]
            )
            edgeEntity.name = "\(plate.rawValue)-outline-\(index)"
            visualRoot.addChild(edgeEntity)
            edges.append(edgeEntity)
        }
        outlineEdgeEntities[plate] = edges
        updateOutline(
            for: plate,
            center: mapper.plateOutlineCenter(for: plate),
            extent: mapper.plateOutlineExtent(for: plate)
        )

        let wellGroup = makeWellGroup(for: plate, mapper: mapper)
        visualRoot.addChild(wellGroup)
        wellGroupEntities[plate] = wellGroup

        let highlightEntity = makeHighlightedWellEntity(for: plate, mapper: mapper)
        highlightEntity.isEnabled = false
        visualRoot.addChild(highlightEntity)
        highlightedWellEntities[plate] = highlightEntity

        return anchorRoot
    }

    private func makeWellGroup(for plate: PlateID, mapper: CoordinateMapper) -> Entity {
        let group = Entity()
        group.name = "\(plate.rawValue)-wells"

        let layout = mapper.plateLayout
        let ringRadius = layout.wellHighlightRadius
        let wellHeight = max(layout.wellHighlightHeight * 0.28, 0.0006)
        let inactiveMaterial = wellMaterial(alpha: activeOverlayAlpha)

        let mesh = MeshResource.generateCylinder(height: wellHeight, radius: ringRadius)

        var plateWells: [String: Entity] = [:]
        for coordinate in mapper.allCoordinates(for: plate) {
            let wellEntity = Entity()
            wellEntity.name = "\(plate.rawValue)-well-\(coordinate.well)"
            wellEntity.position = displayPosition(for: coordinate)

            let cap = ModelEntity(mesh: mesh, materials: [inactiveMaterial])
            wellEntity.addChild(cap)
            group.addChild(wellEntity)
            plateWells[coordinate.well] = wellEntity
        }

        wellEntities[plate] = plateWells
        return group
    }

    private func makeHighlightedWellEntity(for plate: PlateID, mapper: CoordinateMapper) -> Entity {
        let layout = mapper.plateLayout
        let root = Entity()
        root.name = "\(plate.rawValue)-highlighted-well"

        let haloMaterial = highlightSoftMaterial(alpha: activeOverlayAlpha)
        let glowMaterial = highlightGlowMaterial(alpha: activeOverlayAlpha)
        let halo = ModelEntity(
            mesh: .generateCylinder(height: layout.wellHighlightHeight * 0.35, radius: layout.wellHighlightRadius * 2.15),
            materials: [haloMaterial]
        )
        root.addChild(halo)

        let puck = ModelEntity(
            mesh: .generateCylinder(height: layout.wellHighlightHeight * 0.45, radius: layout.wellHighlightRadius * 1.35),
            materials: [glowMaterial]
        )
        root.addChild(puck)

        let ring = makeTargetRing(radius: layout.wellHighlightRadius * 2.4, thickness: layout.wellHighlightRadius * 0.28, material: glowMaterial)
        root.addChild(ring)

        return root
    }

    private func updateWellOverlayHeight(for plate: PlateID, center: SIMD3<Float>, extent: SIMD3<Float>, mapper: CoordinateMapper) {
        let topSurfaceY = center.y + extent.y * 0.5
        let baseYOffset = mapper.plateLayout.wellYOffset
        let yAdjustment = topSurfaceY + wellOverlayYOffset - baseYOffset

        wellGroupEntities[plate]?.position.y = yAdjustment
        highlightedWellEntities[plate]?.position.y = yAdjustment
    }

    private func updateHighlightedWell(for plate: PlateID, coordinate: Coordinate?) {
        guard let highlightEntity = highlightedWellEntities[plate] else { return }
        let previousWell = highlightedWellNames[plate]
        let nextWell = coordinate?.well
        guard previousWell != nextWell else { return }

        guard let coordinate else {
            if let previousWell, plate == .source {
                wellEntities[plate]?[previousWell]?.isEnabled = true
            }
            highlightedWellNames.removeValue(forKey: plate)
            highlightEntity.isEnabled = false
            return
        }

        if let previousWell, plate == .source {
            wellEntities[plate]?[previousWell]?.isEnabled = true
        }

        highlightedWellNames[plate] = coordinate.well
        highlightEntity.isEnabled = true
        highlightEntity.position = displayPosition(for: coordinate)

        if plate == .source {
            wellEntities[plate]?[coordinate.well]?.isEnabled = false
        }
    }

    private func updateOutline(for plate: PlateID, center: SIMD3<Float>, extent: SIMD3<Float>) {
        guard let edges = outlineEdgeEntities[plate], edges.count == 4 else { return }

        let minimumExtent = SIMD3<Float>(0.04, 0.004, 0.03)
        let clampedExtent = simd_max(extent, minimumExtent)
        let thickness = min(max(min(clampedExtent.x, clampedExtent.z) * 0.025, 0.0015), 0.004)
        let half = clampedExtent * 0.5
        let outlineCenter = center + SIMD3<Float>(0, plateOutlineYOffset, 0)
        let nextState = OutlineState(center: outlineCenter, extent: clampedExtent)

        if let previousState = outlineStates[plate],
           simd_distance(previousState.center, nextState.center) < 0.0005,
           simd_distance(previousState.extent, nextState.extent) < 0.0005 {
            return
        }
        outlineStates[plate] = nextState

        let edgeDefinitions: [(meshSize: SIMD3<Float>, position: SIMD3<Float>)] = [
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), outlineCenter + SIMD3<Float>(0, half.y, half.z)),
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), outlineCenter + SIMD3<Float>(0, half.y, -half.z)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), outlineCenter + SIMD3<Float>(half.x, half.y, 0)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), outlineCenter + SIMD3<Float>(-half.x, half.y, 0))
        ]

        for (edge, definition) in zip(edges, edgeDefinitions) {
            edge.model?.mesh = .generateBox(size: definition.meshSize, cornerRadius: min(thickness * 0.25, 0.001))
            edge.position = definition.position
        }
    }

    private func updateOverlayOpacity(for plate: PlateID, alpha: CGFloat) {
        outlineEdgeEntities[plate]?.forEach { $0.model?.materials = [outlineMaterial(alpha: alpha)] }
        wellEntities[plate]?.values.forEach { wellEntity in
            wellEntity.children.compactMap { $0 as? ModelEntity }.forEach { $0.model?.materials = [wellMaterial(alpha: alpha)] }
        }
        highlightedWellEntities[plate]?.children.compactMap { $0 as? ModelEntity }.forEach { entity in
            entity.model?.materials = [highlightGlowMaterial(alpha: alpha)]
        }
    }

    private func displayPosition(for coordinate: Coordinate) -> SIMD3<Float> {
        guard coordinate.plate == .destination else {
            return coordinate.normalizedPosition
        }

        return SIMD3<Float>(
            -coordinate.normalizedPosition.x,
            coordinate.normalizedPosition.y,
            -coordinate.normalizedPosition.z
        )
    }

    private func makeTargetRing(radius: Float, thickness: Float, material: SimpleMaterial) -> Entity {
        let root = Entity()
        let diameter = radius * 2
        let segmentLength = max(diameter - thickness, thickness)
        let segmentHeight = max(thickness * 0.45, 0.0006)
        let cornerRadius = min(thickness * 0.3, 0.001)
        let definitions: [(size: SIMD3<Float>, position: SIMD3<Float>)] = [
            (SIMD3<Float>(segmentLength, segmentHeight, thickness), SIMD3<Float>(0, 0, radius)),
            (SIMD3<Float>(segmentLength, segmentHeight, thickness), SIMD3<Float>(0, 0, -radius)),
            (SIMD3<Float>(thickness, segmentHeight, segmentLength), SIMD3<Float>(radius, 0, 0)),
            (SIMD3<Float>(thickness, segmentHeight, segmentLength), SIMD3<Float>(-radius, 0, 0))
        ]

        for definition in definitions {
            let segment = ModelEntity(
                mesh: .generateBox(size: definition.size, cornerRadius: cornerRadius),
                materials: [material]
            )
            segment.position = definition.position
            root.addChild(segment)
        }

        return root
    }

    private func outlineMaterial(alpha: CGFloat) -> SimpleMaterial {
        SimpleMaterial(color: overlayAccentColor.withAlphaComponent(alpha), roughness: 0.1, isMetallic: false)
    }

    private func wellMaterial(alpha: CGFloat) -> SimpleMaterial {
        SimpleMaterial(color: UIColor.white.withAlphaComponent(alpha * 0.18), roughness: 0.18, isMetallic: false)
    }

    private func highlightGlowMaterial(alpha: CGFloat) -> SimpleMaterial {
        SimpleMaterial(color: overlayAccentGlowColor.withAlphaComponent(alpha), roughness: 0.02, isMetallic: false)
    }

    private func highlightSoftMaterial(alpha: CGFloat) -> SimpleMaterial {
        SimpleMaterial(color: overlayAccentSoftColor.withAlphaComponent(alpha * 0.35), roughness: 0.02, isMetallic: false)
    }
}
