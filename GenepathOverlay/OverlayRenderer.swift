import RealityKit
import SwiftUI
import UIKit

@MainActor
final class OverlayRenderer {
    private var rootEntity: Entity?
    private var plateEntities: [PlateID: Entity] = [:]
    private var highlightEntities: [PlateID: ModelEntity] = [:]
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
            let platePosition = trackingSnapshot.plateAnchors[plate]?.position ?? mapper.plateWorldPosition(for: plate)
            plateEntity.transform = Transform(matrix: simd_float4x4(translation: platePosition))
        }

        if let workflowPanelEntity {
            attachWorkflowPanelIfNeeded(workflowPanelEntity)
            workflowPanelEntity.position = SIMD3<Float>(-0.19, 0.11, 0.0)
            workflowPanelEntity.scale = SIMD3<Float>(repeating: 0.5)
        }

        guard let currentStep else {
            highlightEntities.values.forEach { $0.isEnabled = false }
            return
        }

        updateHighlight(
            for: .source,
            coordinate: currentStep.source,
            isPrimary: currentPhase == .aspiration
        )
        updateHighlight(
            for: .destination,
            coordinate: currentStep.destination,
            isPrimary: currentPhase == .dispense
        )
    }

    private func attachWorkflowPanelIfNeeded(_ workflowPanel: Entity) {
        guard let sourcePlate = plateEntities[.source] else { return }
        guard workflowPanel.parent !== sourcePlate else { return }

        workflowPanel.removeFromParent()
        workflowPanel.name = "workflow-panel"
        workflowPanel.position = SIMD3<Float>(-0.19, 0.11, 0.0)
        workflowPanel.scale = SIMD3<Float>(repeating: 0.5)
        sourcePlate.addChild(workflowPanel)
        workflowPanelEntity = workflowPanel
    }

    private func updateHighlight(for plate: PlateID, coordinate: Coordinate, isPrimary: Bool) {
        guard let highlight = highlightEntities[plate] else { return }
        highlight.position = coordinate.normalizedPosition + SIMD3<Float>(0, 0.003, 0)
        highlight.scale = isPrimary ? SIMD3<Float>(repeating: 1.2) : SIMD3<Float>(repeating: 0.8)
        if var model = highlight.model {
            model.materials = [highlightMaterial(for: plate, emphasized: isPrimary)]
            highlight.model = model
        }
        highlight.isEnabled = true
    }

    private func makePlateEntity(for plate: PlateID, mapper: CoordinateMapper) -> Entity {
        let tint = plate == .source
            ? UIColor(red: 0.10, green: 0.50, blue: 0.87, alpha: 1)
            : UIColor(red: 0.10, green: 0.70, blue: 0.44, alpha: 1)

        let root = Entity()
        root.name = "\(plate.rawValue)-plate"
        root.transform = Transform(matrix: mapper.plateWorldTransform(for: plate))

        let baseMesh = MeshResource.generateBox(size: SIMD3<Float>(0.19, 0.014, 0.125), cornerRadius: 0.008)
        let baseMaterial = SimpleMaterial(color: tint.withAlphaComponent(0.94), roughness: 0.2, isMetallic: false)
        root.addChild(ModelEntity(mesh: baseMesh, materials: [baseMaterial]))

        for row in 0..<8 {
            for column in 0..<12 {
                let well = ModelEntity(
                    mesh: .generateCylinder(height: 0.005, radius: 0.0042),
                    materials: [SimpleMaterial(color: .white.withAlphaComponent(0.92), roughness: 0.35, isMetallic: false)]
                )
                well.position = mapper.localPosition(for: row, column: column)
                root.addChild(well)
            }
        }

        let highlight = ModelEntity(
            mesh: .generateSphere(radius: 0.0065),
            materials: [highlightMaterial(for: plate, emphasized: false)]
        )
        highlight.name = "\(plate.rawValue)-highlight"
        highlight.isEnabled = false
        root.addChild(highlight)
        highlightEntities[plate] = highlight

        return root
    }

    private func highlightMaterial(for plate: PlateID, emphasized: Bool) -> SimpleMaterial {
        let alpha: CGFloat = emphasized ? 0.95 : 0.35
        let color = plate == .source
            ? UIColor(red: 0.15, green: 0.75, blue: 0.98, alpha: alpha)
            : UIColor(red: 0.32, green: 0.95, blue: 0.48, alpha: alpha)
        return SimpleMaterial(color: color, roughness: 0.08, isMetallic: true)
    }
}
