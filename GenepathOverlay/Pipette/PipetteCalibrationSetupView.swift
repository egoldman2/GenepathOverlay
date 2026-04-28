import SwiftUI

struct PipetteCalibrationSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private let infoColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var canCapture: Bool {
        appModel.immersiveSpaceState == .open && appModel.selectedPipetteHand != nil
    }

    private var isSettingsMode: Bool {
        appModel.pipetteCalibrationOpenedFromSettings
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    HStack(alignment: .center) {
                        Button {
                            appModel.leavePipetteCalibration()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(SecondaryActionButton())

                        Spacer(minLength: 0)

                        if appModel.pipetteCalibrationOpenedFromSettings == false {
                            SetupProgressIndicator(currentStep: 4, totalSteps: 4)
                        }
                    }

                    Text(isSettingsMode ? "Pipette Calibration" : "Pipette calibration")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text(
                        isSettingsMode
                        ? "Adjust pipette setup, refresh calibration, and review the current input state."
                        : "Set the pipette hand, capture a resting thumb pose, then capture a pressed pose before starting the guided run."
                    )
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        if appModel.immersiveSpaceState != .open {
                            Button("Open Mixed Reality View") {
                                Task { @MainActor in
                                    await openMixedRealityIfNeeded()
                                }
                            }
                            .buttonStyle(PrimaryActionButton())
                        } else {
                            Label("Mixed Reality View is open", systemImage: "visionpro")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            handSelectionButton(.left)
                            handSelectionButton(.right)
                        }

                        LazyVGrid(columns: infoColumns, alignment: .leading, spacing: 12) {
                            CalibrationInfoCard(title: "Tracking", value: appModel.pipetteTrackingMessage)
                            CalibrationInfoCard(title: "Calibration", value: appModel.pipetteCalibrationMessage)
                            CalibrationInfoCard(title: "Progress", value: appModel.pipetteCalibrationProgressLabel)
                            CalibrationInfoCard(title: "Last Event", value: appModel.lastPipetteEventLabel)
                        }

                        HStack(spacing: 12) {
                            Button("Capture Rest Hold") {
                                appModel.startRestCalibrationCapture()
                            }
                            .buttonStyle(PrimaryActionButton())
                            .disabled(!canCapture)

                            Button("Capture Press Hold") {
                                appModel.startPressedCalibrationCapture()
                            }
                            .buttonStyle(SecondaryActionButton())
                            .disabled(!canCapture)

                            Button("Reset Calibration") {
                                appModel.resetPipetteCalibration()
                            }
                            .buttonStyle(SecondaryActionButton())
                            .disabled(appModel.selectedPipetteHand == nil)
                        }

                        Text(
                            appModel.isPipetteCalibrationComplete
                            ? (isSettingsMode ? "Calibration is complete and ready to use." : "Calibration complete. Start the guided run when ready.")
                            : (isSettingsMode ? "Use the controls above to recalibrate the pipette input when needed." : "Calibration is required before the guided run can begin.")
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(18)
                    .background(CalibrationGlassBackground())

                    if isSettingsMode {
                        Button("Done") {
                            appModel.leavePipetteCalibration()
                        }
                        .buttonStyle(PrimaryActionButton())
                    } else {
                        HStack(spacing: 12) {
                            Button("Bypass for Testing") {
                                appModel.beginWorkflow()
                            }
                            .buttonStyle(SecondaryActionButton())

                            Button("Start Guided Run") {
                                appModel.beginWorkflow()
                            }
                            .buttonStyle(PrimaryActionButton())
                            .disabled(!appModel.isPipetteCalibrationComplete)
                            .opacity(appModel.isPipetteCalibrationComplete ? 1 : 0.45)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func handSelectionButton(_ hand: PipetteHandedness) -> some View {
        if appModel.selectedPipetteHand == hand {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
            .buttonStyle(PrimaryActionButton())
        } else {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
            .buttonStyle(SecondaryActionButton())
        }
    }

    @MainActor
    private func openMixedRealityIfNeeded() async {
        if appModel.immersiveSpaceState == .open {
            return
        }

        appModel.setImmersiveSpaceState(.inTransition)
        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
        if case .opened = result {
            appModel.setImmersiveSpaceState(.open)
        } else {
            appModel.setImmersiveSpaceState(.closed)
        }
    }
}

private struct CalibrationInfoCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(CalibrationGlassBackground(cornerRadius: 18))
    }
}

private struct CalibrationGlassBackground: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

#Preview {
    PipetteCalibrationSetupView()
        .environment(AppModel())
}
