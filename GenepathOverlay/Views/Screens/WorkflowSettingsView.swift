import SwiftUI

struct WorkflowSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var route: SettingsRoute = .menu

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    header

                    switch route {
                    case .menu:
                        settingsMenu
                    case .tracking:
                        trackingSettings
                    case .pipetteButton:
                        pipetteButtonSettings
                    }
                }
            }
        }
        .foregroundStyle(AppUIStyle.primaryTextColor)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var header: some View {
        if route == .menu {
            Button {
                appModel.beginWorkflow()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryActionButton())
        } else {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    route = .menu
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryActionButton())
        }
    }

    private var settingsMenu: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            AppSubtitleText("Choose a setting to adjust for the guided run.")

            VStack(alignment: .leading, spacing: 10) {
                SettingsOptionRow(
                    title: "Tracking and Alignment",
                    detail: "Reference objects, anchors, and test plate options."
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        route = .tracking
                    }
                }

                SettingsOptionRow(
                    title: "Pipette Button",
                    detail: "View pipette press status, hand selection, and confidence."
                ) {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        route = .pipetteButton
                    }
                }

                SettingsOptionRow(
                    title: "Pipette Calibration",
                    detail: "Open pipette setup and recalibration tools."
                ) {
                    appModel.goToPipetteCalibrationFromSettings()
                }
            }
        }
    }

    private var trackingSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Tracking and Alignment")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            AppSubtitleText("Manage plate tracking and preview alignment options.")

            SettingsDetailCard(title: "Tracking Status", value: appModel.trackingMessage)
            SettingsDetailCard(title: "Reference Objects", value: appModel.bundledReferenceObjectsLabel)
            SettingsDetailCard(title: "Tracked Plates", value: appModel.trackedPlatesLabel)
            SettingsDetailCard(title: "Test Plate Model", value: appModel.testWellPlateModelName)

            Toggle("Show Test Well Plate Model", isOn: Binding(
                get: { appModel.isShowingTestWellPlate },
                set: { appModel.isShowingTestWellPlate = $0 }
            ))
            .disabled(!appModel.isTestWellPlateModelAvailable)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(SettingsGlassBackground())

            Text(
                appModel.isTestWellPlateModelAvailable
                    ? "Use the bundled USDZ model when you want to test the workflow in preview mode."
                    : "Add a well plate `.usdz` file to `ReferenceObjects/` to enable the simulated plate model."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if appModel.isPreviewTracking {
                Text("Preview mode is active because live tracking assets are still being prepared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pipetteButtonSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Pipette Button")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            AppSubtitleText("View the current pipette input state and calibration status.")

            SettingsPipetteStatusCard()

            SettingsDetailCard(title: "Tracking", value: appModel.pipetteTrackingMessage)
            SettingsDetailCard(title: "Selected Hand", value: appModel.selectedPipetteHandLabel)
            SettingsDetailCard(title: "Calibration", value: appModel.pipetteCalibrationMessage)
            SettingsDetailCard(title: "Grip Confidence", value: appModel.pipetteGripConfidenceLabel)
            SettingsDetailCard(title: "Press State", value: appModel.pipettePressLabel)
            SettingsDetailCard(title: "Press Count", value: "\(appModel.pipetteInputState.pressCount)")
            SettingsDetailCard(title: "Last Event", value: appModel.lastPipetteEventLabel)

            Text(appModel.pipetteCalibrationProgressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsPipetteStatusCard: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Pipette button", systemImage: appModel.isPipettePressed ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.headline)
                    .foregroundStyle(AppUIStyle.primaryTextColor)

                Spacer(minLength: 0)

                Text(appModel.pipettePressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }

            Text(appModel.pipetteTrackingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hand: \(appModel.selectedPipetteHandLabel) • Grip: \(appModel.pipetteGripConfidenceLabel) • Presses: \(appModel.pipetteInputState.pressCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(appModel.lastPipetteEventLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(SettingsGlassBackground())
    }
}

private enum SettingsRoute {
    case menu
    case tracking
    case pipetteButton
}

private struct SettingsOptionRow: View {
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(AppUIStyle.primaryTextColor)

                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(SettingsGlassBackground())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsDetailCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(SettingsGlassBackground())
    }
}

private struct SettingsGlassBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}
