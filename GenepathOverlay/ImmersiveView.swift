import RealityKit
import RealityKitContent
import SwiftUI
import UIKit

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    @State private var sourcePlateEntity: Entity?
    @State private var destinationPlateEntity: Entity?
    @State private var markerTracker = TableMarkerTrackingController()

    private let sourceEntityName = "source-plate-entity"
    private let destinationEntityName = "destination-plate-entity"

    var body: some View {
        RealityView { content in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            }

            let root = Entity()
            root.name = "tracking-root"
            let sourcePlateEntity = makePlateEntity(for: .source)
            let destinationPlateEntity = makePlateEntity(for: .destination)
            self.sourcePlateEntity = sourcePlateEntity
            self.destinationPlateEntity = destinationPlateEntity
            root.addChild(sourcePlateEntity)
            root.addChild(destinationPlateEntity)
            content.add(root)
        } update: { _ in
            if let source = sourcePlateEntity {
                source.transform = Transform(matrix: appModel.sourceAnchor.transform)
            }

            if let destination = destinationPlateEntity {
                destination.transform = Transform(matrix: appModel.destinationAnchor.transform)
            }
        }
        .task {
            markerTracker.startTracking(appModel: appModel)
        }
        .onDisappear {
            markerTracker.stopTracking()
        }
        .overlay(alignment: .top) {
            overlayPanel
                .padding(.top, 20)
        }
    }

    private var overlayPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Table Marker Alignment")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(UITheme.panelTextPrimary)

                Text("Place the printed QR markers flat on the table directly to the right of each plate's bottom-right corner. The overlays will follow the detected table markers, and you can apply a small manual correction if your bench layout is slightly different.")
                    .font(.subheadline)
                    .foregroundStyle(UITheme.panelTextSecondary)
            }

            HStack(alignment: .top, spacing: 16) {
                trackingCard(for: .source)
                trackingCard(for: .destination)
            }

            fineTuneControls
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func trackingCard(for role: AppModel.PlateRole) -> some View {
        let anchor = appModel.trackingAnchor(for: role)
        let isFocused = appModel.focusedRole == role

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(anchor.assignedPlateName)
                    .font(.headline)
                    .foregroundStyle(UITheme.panelTextPrimary)

                Spacer(minLength: 0)

                Circle()
                    .fill(role.tint)
                    .frame(width: 10, height: 10)
            }

            Text(role.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(UITheme.panelTextSecondary)

            Text(anchor.markerVisible ? "Marker visible" : "Marker hidden")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(UITheme.panelTextPrimary)

            Text("\(anchor.wellCount) wells  |  \(Int(anchor.confidence * 100))% confidence")
                .font(.caption)
                .foregroundStyle(UITheme.panelTextSecondary)

            Button(isFocused ? "Focused" : "Fine-Tune This Plate") {
                appModel.focus(role: role)
            }
            .buttonStyle(.borderedProminent)
            .tint(role.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(isFocused ? role.tint.opacity(0.16) : Color.white.opacity(0.38))
        )
    }

    private var fineTuneControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Focused Plate: \(appModel.focusedRole.title)")
                .font(.headline)
                .foregroundStyle(UITheme.panelTextPrimary)

            HStack(spacing: 10) {
                placementButton("Left") { appModel.nudgeFocusedPlate(x: -0.01) }
                placementButton("Right") { appModel.nudgeFocusedPlate(x: 0.01) }
                placementButton("Up") { appModel.nudgeFocusedPlate(y: 0.005) }
                placementButton("Down") { appModel.nudgeFocusedPlate(y: -0.005) }
                placementButton("Near") { appModel.nudgeFocusedPlate(z: 0.01) }
                placementButton("Far") { appModel.nudgeFocusedPlate(z: -0.01) }
            }

            Button("Reset Fine-Tuning") {
                appModel.resetFocusedPlatePlacement()
            }
            .buttonStyle(.bordered)
        }
    }

    private func placementButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
    }

    private func makePlateEntity(for role: AppModel.PlateRole) -> Entity {
        let anchor = appModel.trackingAnchor(for: role)
        let tint = role == .source
            ? UIColor(red: 0.09, green: 0.49, blue: 0.83, alpha: 1)
            : UIColor(red: 0.12, green: 0.65, blue: 0.46, alpha: 1)

        let root = Entity()
        root.name = role == .source ? sourceEntityName : destinationEntityName
        root.transform = Transform(matrix: anchor.transform)

        let baseMesh = MeshResource.generateBox(size: SIMD3<Float>(0.19, 0.014, 0.125), cornerRadius: 0.008)
        let baseMaterial = SimpleMaterial(color: tint.withAlphaComponent(0.95), roughness: 0.18, isMetallic: false)
        let base = ModelEntity(mesh: baseMesh, materials: [baseMaterial])
        root.addChild(base)

        for row in 0..<8 {
            for column in 0..<12 {
                let well = ModelEntity(
                    mesh: .generateCylinder(height: 0.005, radius: 0.0042),
                    materials: [SimpleMaterial(color: .white.withAlphaComponent(0.92), roughness: 0.35, isMetallic: false)]
                )

                let x = Float(column) * 0.014 - 0.077
                let z = Float(row) * 0.014 - 0.049
                well.position = [x, 0.0095, z]
                root.addChild(well)
            }
        }

        let highlight = ModelEntity(
            mesh: .generateBox(size: SIMD3<Float>(0.205, 0.002, 0.14), cornerRadius: 0.012),
            materials: [SimpleMaterial(color: tint.withAlphaComponent(0.22), roughness: 0.05, isMetallic: false)]
        )
        highlight.position = [0, -0.009, 0]
        root.addChild(highlight)

        return root
    }
}

#Preview(immersionStyle: .full) {
    ImmersiveView()
        .environment(AppModel())
}
