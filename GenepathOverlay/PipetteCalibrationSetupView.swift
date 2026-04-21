import SwiftUI

struct PipetteCalibrationSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    private var canCapture: Bool {
        appModel.immersiveSpaceState == .open && appModel.selectedPipetteHand != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    Button {
                        appModel.goToOperatorChecklist()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    PageEyebrow(title: "Step 4")

                    Text("Pipette calibration")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Set the pipette hand, capture a resting thumb pose, then capture a pressed pose before starting the guided run.")
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
                            .buttonStyle(.borderedProminent)
                        } else {
                            Label("Mixed Reality View is open", systemImage: "visionpro")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppUIStyle.accentColor)
                        }

                        HStack(spacing: 12) {
                            handSelectionButton(.left)
                            handSelectionButton(.right)
                        }

                        DetailItemView(title: "Tracking", value: appModel.pipetteTrackingMessage)
                        DetailItemView(title: "Calibration", value: appModel.pipetteCalibrationMessage)
                        DetailItemView(title: "Progress", value: appModel.pipetteCalibrationProgressLabel)
                        DetailItemView(title: "Last Event", value: appModel.lastPipetteEventLabel)

                        HStack(spacing: 12) {
                            Button("Capture Rest Hold") {
                                appModel.startRestCalibrationCapture()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!canCapture)

                            Button("Capture Press Hold") {
                                appModel.startPressedCalibrationCapture()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!canCapture)

                            Button("Reset Calibration") {
                                appModel.resetPipetteCalibration()
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.selectedPipetteHand == nil)
                        }

                        Text(appModel.isPipetteCalibrationComplete ? "Calibration complete. Start the guided run when ready." : "Calibration is required before the guided run can begin.")
                            .font(.caption)
                            .foregroundStyle(appModel.isPipetteCalibrationComplete ? AppUIStyle.accentColor : .secondary)
                    }
                    .padding(18)
                    .background(AppTintedPanel(opacity: 0.58))

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
            .buttonStyle(.bordered)
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

#Preview {
    PipetteCalibrationSetupView()
        .environment(AppModel())
}
