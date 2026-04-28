import RealityKit
import SwiftUI
import UIKit

@MainActor
final class OverlayRenderer {
    private let thumbGuideLength: Float = 0.25
    private let thumbGuideThickness: Float = 0.004
    private let thumbGuideStartInset: Float = 0.02
    private let workflowPanelScale: Float = 0.575
    private let workflowPanelLift: Float = 0.05
    private let workflowPanelBackOffset: Float = 0.09
    private let overlayAccentColor = UIColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 0.96)
    private let overlayAccentGlowColor = UIColor(red: 0.20, green: 0.62, blue: 1.0, alpha: 0.92)
    private let overlayAccentSoftColor = UIColor(red: 0.30, green: 0.68, blue: 1.0, alpha: 0.28)
    private let overlayWhiteBeamColor = UIColor(red: 0.96, green: 0.97, blue: 1.0, alpha: 0.90)
    private var rootEntity: Entity?
    private var plateEntities: [PlateID: Entity] = [:]
    private var plateVisualEntities: [PlateID: Entity] = [:]
    private var outlineEdgeEntities: [PlateID: [ModelEntity]] = [:]
    private var wellGroupEntities: [PlateID: Entity] = [:]
    private var wellEntities: [PlateID: [String: Entity]] = [:]
    private var highlightedWellEntities: [PlateID: Entity] = [:]
    private weak var workflowPanelEntity: Entity?
    private var testPlateContainerEntity: Entity?
    private var testPlateModelEntity: Entity?
    private var thumbGuideEntity: ModelEntity?
    private var testPlateLoadTask: Task<Void, Never>?
    private var loadedTestPlateURL: URL?

    func installIfNeeded(
        content: inout RealityViewContent,
        mapper: CoordinateMapper,
        workflowPanel: Entity? = nil,
        showTestPlateModel: Bool = false
    ) {
        if let rootEntity {
            if rootEntity.scene == nil {
                content.add(rootEntity)
            }
            installThumbGuideIfNeeded(on: rootEntity)
            if let workflowPanel, workflowPanelEntity == nil {
                attachWorkflowPanelIfNeeded(workflowPanel)
            }
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
        installThumbGuideIfNeeded(on: root)
        content.add(root)

        if let workflowPanel {
            attachWorkflowPanelIfNeeded(workflowPanel)
        }

        installTestPlateContainerIfNeeded()
        updateTestPlateVisibility(isVisible: showTestPlateModel)
    }

    func update(
        trackingSnapshot: TrackingSnapshot,
        mapper: CoordinateMapper,
        highlightedCoordinates: [PlateID: Coordinate] = [:],
        showTestPlateModel: Bool = false
    ) {
        for plate in PlateID.allCases {
            guard let plateEntity = plateEntities[plate] else { continue }
            let anchorState = trackingSnapshot.plateAnchors[plate]
            let anchorTransform = anchorState?.transform ?? mapper.plateWorldTransform(for: plate)
            plateEntity.transform = Transform(matrix: anchorTransform)
            plateEntity.isEnabled = anchorState != nil || highlightedCoordinates[plate] != nil
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
                coordinate: highlightedCoordinates[plate]
            )
        }

        if let workflowPanelEntity {
            attachWorkflowPanelIfNeeded(workflowPanelEntity)
            if let highlightedCoordinate = highlightedCoordinates[.source] {
                let layout = mapper.plateLayout
                let beamHeight = max(layout.wellHighlightHeight * 10, 0.04)
                workflowPanelEntity.position = highlightedCoordinate.normalizedPosition + SIMD3<Float>(0, beamHeight + 0.07 + workflowPanelLift, workflowPanelBackOffset)
            } else {
                let sourceAnchor = trackingSnapshot.plateAnchors[.source]
                let sourceCenter = sourceAnchor?.localBoundsCenter ?? mapper.plateOutlineCenter(for: .source)
                let sourceExtent = sourceAnchor?.localBoundsExtent ?? mapper.plateOutlineExtent(for: .source)
                workflowPanelEntity.position = sourceCenter + SIMD3<Float>(0, sourceExtent.y * 0.5 + 0.045 + workflowPanelLift, sourceExtent.z * 0.5 + 0.12 + workflowPanelBackOffset)
            }
            workflowPanelEntity.scale = SIMD3<Float>(repeating: workflowPanelScale)
        }

        updateTestPlateVisibility(isVisible: showTestPlateModel)
        updateThumbGuide(using: trackingSnapshot)
    }

    private func attachWorkflowPanelIfNeeded(_ workflowPanel: Entity) {
        guard let sourcePlate = plateEntities[.source] else { return }
        guard workflowPanel.parent !== sourcePlate else { return }

        workflowPanel.removeFromParent()
        workflowPanel.name = "workflow-panel"
        workflowPanel.position = SIMD3<Float>(0, 0.08 + workflowPanelLift, 0.14 + workflowPanelBackOffset)
        workflowPanel.orientation = simd_quatf()
        workflowPanel.scale = SIMD3<Float>(repeating: workflowPanelScale)
        workflowPanel.components.set(BillboardComponent())
        sourcePlate.addChild(workflowPanel)
        workflowPanelEntity = workflowPanel
    }

    private func installTestPlateContainerIfNeeded() {
        guard testPlateContainerEntity == nil, let sourcePlate = plateVisualEntities[.source] else { return }

        let container = Entity()
        container.name = "test-plate-container"
        container.isEnabled = false
        sourcePlate.addChild(container)
        testPlateContainerEntity = container
    }

    private func installThumbGuideIfNeeded(on root: Entity) {
        guard thumbGuideEntity == nil else { return }

        let material = SimpleMaterial(
            color: overlayAccentGlowColor,
            roughness: 0.05,
            isMetallic: false
        )
        let guide = ModelEntity(
            mesh: .generateCylinder(height: 1, radius: thumbGuideThickness),
            materials: [material]
        )
        guide.name = "thumb-guide-line"
        guide.isEnabled = false
        root.addChild(guide)
        thumbGuideEntity = guide
    }

    private func updateThumbGuide(using trackingSnapshot: TrackingSnapshot) {
        guard let thumbGuideEntity else { return }
        guard
            let start = trackingSnapshot.pipetteInput.thumbWorldPosition,
            let direction = trackingSnapshot.pipetteInput.thumbWorldDirection
        else {
            thumbGuideEntity.isEnabled = false
            return
        }

        let normalizedDirection = simd_normalize(direction)
        let insetStart = start + normalizedDirection * thumbGuideStartInset
        let end = insetStart + normalizedDirection * thumbGuideLength
        thumbGuideEntity.isEnabled = true
        thumbGuideEntity.position = (insetStart + end) * 0.5
        thumbGuideEntity.scale = SIMD3<Float>(1, thumbGuideLength, 1)
        thumbGuideEntity.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: normalizedDirection)
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

        let outlineMaterial = SimpleMaterial(color: overlayAccentColor, roughness: 0.1, isMetallic: false)
        let thickness: Float = 0.0035
        var edges: [ModelEntity] = []
        for index in 0..<12 {
            let edgeEntity = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(repeating: thickness), cornerRadius: min(thickness * 0.25, 0.001)),
                materials: [outlineMaterial]
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
        let ringThickness = max(ringRadius * 0.18, 0.0008)
        let wellHeight = max(layout.wellHighlightHeight * 0.28, 0.0006)
        let inactiveMaterial = SimpleMaterial(
            color: UIColor.white.withAlphaComponent(plate == .source ? 0.16 : 0.08),
            roughness: 0.18,
            isMetallic: false
        )

        let mesh = MeshResource.generateCylinder(height: wellHeight, radius: ringRadius)

        var plateWells: [String: Entity] = [:]
        for coordinate in mapper.allCoordinates(for: plate) {
            let wellEntity = Entity()
            wellEntity.name = "\(plate.rawValue)-well-\(coordinate.well)"
            wellEntity.position = coordinate.normalizedPosition

            let cap = ModelEntity(mesh: mesh, materials: [inactiveMaterial])
            cap.position.y = ringThickness * 0.5
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

        let haloMaterial = SimpleMaterial(
            color: overlayAccentSoftColor,
            roughness: 0.02,
            isMetallic: false
        )
        let glowMaterial = SimpleMaterial(
            color: overlayAccentGlowColor,
            roughness: 0.02,
            isMetallic: false
        )
        let beamMaterial = SimpleMaterial(
            color: overlayWhiteBeamColor,
            roughness: 0.01,
            isMetallic: false
        )
        let halo = ModelEntity(
            mesh: .generateCylinder(height: layout.wellHighlightHeight * 0.9, radius: layout.wellHighlightRadius * 1.9),
            materials: [haloMaterial]
        )
        halo.position.y = layout.wellHighlightHeight * 0.45
        root.addChild(halo)

        let puck = ModelEntity(
            mesh: .generateCylinder(height: layout.wellHighlightHeight * 1.4, radius: layout.wellHighlightRadius * 1.2),
            materials: [glowMaterial]
        )
        puck.position.y = layout.wellHighlightHeight * 0.7
        root.addChild(puck)

        let beamHeight = max(layout.wellHighlightHeight * 10, 0.04)
        let beam = ModelEntity(
            mesh: .generateBox(
                size: SIMD3<Float>(layout.wellHighlightRadius * 0.18, beamHeight, layout.wellHighlightRadius * 0.18),
                cornerRadius: layout.wellHighlightRadius * 0.08
            ),
            materials: [beamMaterial]
        )
        beam.position.y = beamHeight * 0.5 + layout.wellHighlightHeight * 1.4
        root.addChild(beam)

        let beacon = ModelEntity(
            mesh: .generateSphere(radius: layout.wellHighlightRadius * 0.85),
            materials: [glowMaterial]
        )
        beacon.position.y = beamHeight + layout.wellHighlightHeight * 1.9
        root.addChild(beacon)

        return root
    }

    private func updateWellOverlayHeight(for plate: PlateID, center: SIMD3<Float>, extent: SIMD3<Float>, mapper: CoordinateMapper) {
        let topSurfaceY = center.y + extent.y * 0.5
        let baseYOffset = mapper.plateLayout.wellYOffset
        let yAdjustment = topSurfaceY - baseYOffset

        wellGroupEntities[plate]?.position.y = yAdjustment
        highlightedWellEntities[plate]?.position.y = yAdjustment
    }

    private func updateHighlightedWell(for plate: PlateID, coordinate: Coordinate?) {
        guard let highlightEntity = highlightedWellEntities[plate] else { return }
        if let plateWells = wellEntities[plate] {
            for (_, wellEntity) in plateWells {
                wellEntity.isEnabled = true
            }
        }

        guard let coordinate else {
            highlightEntity.isEnabled = false
            return
        }

        highlightEntity.isEnabled = true
        highlightEntity.position = coordinate.normalizedPosition

        if let plateWells = wellEntities[plate] {
            for (wellName, wellEntity) in plateWells {
                wellEntity.isEnabled = wellName != coordinate.well || plate != .source
            }
        }
    }

    private func updateOutline(for plate: PlateID, center: SIMD3<Float>, extent: SIMD3<Float>) {
        guard let edges = outlineEdgeEntities[plate], edges.count == 12 else { return }

        let minimumExtent = SIMD3<Float>(0.04, 0.004, 0.03)
        let clampedExtent = simd_max(extent, minimumExtent)
        let thickness = min(max(min(clampedExtent.x, clampedExtent.z) * 0.025, 0.0015), 0.004)
        let half = clampedExtent * 0.5

        let edgeDefinitions: [(meshSize: SIMD3<Float>, position: SIMD3<Float>)] = [
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), center + SIMD3<Float>(0, half.y, half.z)),
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), center + SIMD3<Float>(0, half.y, -half.z)),
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), center + SIMD3<Float>(0, -half.y, half.z)),
            (SIMD3<Float>(clampedExtent.x, thickness, thickness), center + SIMD3<Float>(0, -half.y, -half.z)),
            (SIMD3<Float>(thickness, clampedExtent.y, thickness), center + SIMD3<Float>(half.x, 0, half.z)),
            (SIMD3<Float>(thickness, clampedExtent.y, thickness), center + SIMD3<Float>(half.x, 0, -half.z)),
            (SIMD3<Float>(thickness, clampedExtent.y, thickness), center + SIMD3<Float>(-half.x, 0, half.z)),
            (SIMD3<Float>(thickness, clampedExtent.y, thickness), center + SIMD3<Float>(-half.x, 0, -half.z)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), center + SIMD3<Float>(half.x, half.y, 0)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), center + SIMD3<Float>(half.x, -half.y, 0)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), center + SIMD3<Float>(-half.x, half.y, 0)),
            (SIMD3<Float>(thickness, thickness, clampedExtent.z), center + SIMD3<Float>(-half.x, -half.y, 0)),
        ]

        for (edge, definition) in zip(edges, edgeDefinitions) {
            edge.model?.mesh = .generateBox(size: definition.meshSize, cornerRadius: min(thickness * 0.25, 0.001))
            edge.position = definition.position
        }
    }
}
