import RealityKit
import SwiftUI
import UIKit

@MainActor
final class OverlayRenderer {
    private let plateFacingCorrection = simd_float4x4(rotationAboutY: .pi)
    private var rootEntity: Entity?
    private var plateEntities: [PlateID: Entity] = [:]
    private var outlineEdgeEntities: [PlateID: [ModelEntity]] = [:]
    private var wellEntities: [PlateID: [String: Entity]] = [:]
    private var highlightedWellEntities: [PlateID: Entity] = [:]
    private weak var workflowPanelEntity: Entity?
    private var testPlateContainerEntity: Entity?
    private var testPlateModelEntity: Entity?
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
            if let workflowPanel {
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
            plateEntity.transform = Transform(matrix: correctedPlateTransform(anchorTransform))
            plateEntity.isEnabled = plate == .source
            updateOutline(
                for: plate,
                center: anchorState?.localBoundsCenter ?? mapper.plateOutlineCenter(for: plate),
                extent: anchorState?.localBoundsExtent ?? mapper.plateOutlineExtent(for: plate)
            )
            updateHighlightedWell(
                for: plate,
                coordinate: highlightedCoordinates[plate]
            )
        }

        if let workflowPanelEntity {
            attachWorkflowPanelIfNeeded(workflowPanelEntity)
            let sourceAnchor = trackingSnapshot.plateAnchors[.source]
            let sourceCenter = sourceAnchor?.localBoundsCenter ?? mapper.plateOutlineCenter(for: .source)
            let sourceExtent = sourceAnchor?.localBoundsExtent ?? mapper.plateOutlineExtent(for: .source)
            workflowPanelEntity.position = sourceCenter + SIMD3<Float>(sourceExtent.x * 0.5 + 0.08, sourceExtent.y * 0.5 + 0.05, 0)
            workflowPanelEntity.orientation = simd_quatf(angle: -.pi, axis: SIMD3<Float>(0, 1, 0))
            workflowPanelEntity.scale = SIMD3<Float>(repeating: 0.5)
        }

        updateTestPlateVisibility(isVisible: showTestPlateModel)
    }

    private func attachWorkflowPanelIfNeeded(_ workflowPanel: Entity) {
        guard let sourcePlate = plateEntities[.source] else { return }
        guard workflowPanel.parent !== sourcePlate else { return }

        workflowPanel.removeFromParent()
        workflowPanel.name = "workflow-panel"
        workflowPanel.position = SIMD3<Float>(0.15, 0.08, 0.0)
        workflowPanel.orientation = simd_quatf(angle: -.pi, axis: SIMD3<Float>(0, 1, 0))
        workflowPanel.scale = SIMD3<Float>(repeating: 0.5)
        sourcePlate.addChild(workflowPanel)
        workflowPanelEntity = workflowPanel
    }

    private func installTestPlateContainerIfNeeded() {
        guard testPlateContainerEntity == nil, let sourcePlate = plateEntities[.source] else { return }

        let container = Entity()
        container.name = "test-plate-container"
        container.isEnabled = false
        sourcePlate.addChild(container)
        testPlateContainerEntity = container
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
        let root = Entity()
        root.name = "\(plate.rawValue)-plate"
        root.transform = Transform(matrix: correctedPlateTransform(mapper.plateWorldTransform(for: plate)))

        let outlineColor = UIColor(red: 0.16, green: 0.95, blue: 0.36, alpha: 0.96)
        let outlineMaterial = SimpleMaterial(color: outlineColor, roughness: 0.1, isMetallic: false)
        let thickness: Float = 0.0035
        var edges: [ModelEntity] = []
        for index in 0..<12 {
            let edgeEntity = ModelEntity(
                mesh: .generateBox(size: SIMD3<Float>(repeating: thickness), cornerRadius: min(thickness * 0.25, 0.001)),
                materials: [outlineMaterial]
            )
            edgeEntity.name = "\(plate.rawValue)-outline-\(index)"
            root.addChild(edgeEntity)
            edges.append(edgeEntity)
        }
        outlineEdgeEntities[plate] = edges
        updateOutline(
            for: plate,
            center: mapper.plateOutlineCenter(for: plate),
            extent: mapper.plateOutlineExtent(for: plate)
        )

        let wellGroup = makeWellGroup(for: plate, mapper: mapper)
        root.addChild(wellGroup)

        let highlightEntity = makeHighlightedWellEntity(for: plate, mapper: mapper)
        highlightEntity.isEnabled = false
        root.addChild(highlightEntity)
        highlightedWellEntities[plate] = highlightEntity

        return root
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

        let glowMaterial = SimpleMaterial(
            color: UIColor(red: 0.12, green: 0.82, blue: 1.0, alpha: 0.92),
            roughness: 0.06,
            isMetallic: false
        )
        let stemMaterial = SimpleMaterial(
            color: UIColor(red: 0.94, green: 0.99, blue: 1.0, alpha: 0.88),
            roughness: 0.04,
            isMetallic: false
        )

        let puck = ModelEntity(
            mesh: .generateCylinder(height: layout.wellHighlightHeight, radius: layout.wellHighlightRadius),
            materials: [glowMaterial]
        )
        puck.position.y = layout.wellHighlightHeight * 0.5
        root.addChild(puck)

        let stemHeight = max(layout.wellHighlightHeight * 4.5, 0.012)
        let stem = ModelEntity(
            mesh: .generateBox(
                size: SIMD3<Float>(layout.wellHighlightRadius * 0.22, stemHeight, layout.wellHighlightRadius * 0.22),
                cornerRadius: layout.wellHighlightRadius * 0.08
            ),
            materials: [stemMaterial]
        )
        stem.position.y = stemHeight * 0.5 + layout.wellHighlightHeight
        root.addChild(stem)

        return root
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

    private func correctedPlateTransform(_ transform: simd_float4x4) -> simd_float4x4 {
        simd_mul(transform, plateFacingCorrection)
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

extension simd_float4x4 {
    init(rotationAboutY angle: Float) {
        self = matrix_identity_float4x4
        let cosine = cos(angle)
        let sine = sin(angle)
        columns.0 = SIMD4<Float>(cosine, 0, -sine, 0)
        columns.1 = SIMD4<Float>(0, 1, 0, 0)
        columns.2 = SIMD4<Float>(sine, 0, cosine, 0)
        columns.3 = SIMD4<Float>(0, 0, 0, 1)
    }
}
