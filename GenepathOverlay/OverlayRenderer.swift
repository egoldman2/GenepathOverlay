import RealityKit
import SwiftUI
import UIKit

@MainActor
final class OverlayRenderer {
    private var rootEntity: Entity?
    private var plateEntities: [PlateID: Entity] = [:]
    private var outlineEdgeEntities: [PlateID: [ModelEntity]] = [:]
    private weak var workflowPanelEntity: Entity?

    func installIfNeeded(
        content: inout RealityViewContent,
        mapper: CoordinateMapper,
        workflowPanel: Entity? = nil
    ) {
        if let rootEntity {
            if rootEntity.scene == nil {
                content.add(rootEntity)
            }
            if let workflowPanel {
                attachWorkflowPanelIfNeeded(workflowPanel)
            }
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
    }

    func update(
        currentStep: Step?,
        currentPhase: WorkflowPhase,
        trackingSnapshot: TrackingSnapshot,
        mapper: CoordinateMapper
    ) {
        for plate in PlateID.allCases {
            guard let plateEntity = plateEntities[plate] else { continue }
            let anchorState = trackingSnapshot.plateAnchors[plate]
            let anchorTransform = anchorState?.transform ?? mapper.plateWorldTransform(for: plate)
            plateEntity.transform = Transform(matrix: anchorTransform)
            plateEntity.isEnabled = plate == .source
            updateOutline(
                for: plate,
                center: anchorState?.localBoundsCenter ?? mapper.plateOutlineCenter(for: plate),
                extent: anchorState?.localBoundsExtent ?? mapper.plateOutlineExtent(for: plate)
            )
        }

        if let workflowPanelEntity {
            attachWorkflowPanelIfNeeded(workflowPanelEntity)
            let sourceAnchor = trackingSnapshot.plateAnchors[.source]
            let sourceCenter = sourceAnchor?.localBoundsCenter ?? mapper.plateOutlineCenter(for: .source)
            let sourceExtent = sourceAnchor?.localBoundsExtent ?? mapper.plateOutlineExtent(for: .source)
            workflowPanelEntity.position = sourceCenter + SIMD3<Float>(-(sourceExtent.x * 0.5 + 0.08), sourceExtent.y * 0.5 + 0.05, 0)
            workflowPanelEntity.scale = SIMD3<Float>(repeating: 0.5)
        }
    }

    private func attachWorkflowPanelIfNeeded(_ workflowPanel: Entity) {
        guard let sourcePlate = plateEntities[.source] else { return }
        guard workflowPanel.parent !== sourcePlate else { return }

        workflowPanel.removeFromParent()
        workflowPanel.name = "workflow-panel"
        workflowPanel.position = SIMD3<Float>(-0.15, 0.08, 0.0)
        workflowPanel.scale = SIMD3<Float>(repeating: 0.5)
        sourcePlate.addChild(workflowPanel)
        workflowPanelEntity = workflowPanel
    }

    private func makePlateEntity(for plate: PlateID, mapper: CoordinateMapper) -> Entity {
        let root = Entity()
        root.name = "\(plate.rawValue)-plate"
        root.transform = Transform(matrix: mapper.plateWorldTransform(for: plate))

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

        return root
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
