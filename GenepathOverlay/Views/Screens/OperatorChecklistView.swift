//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct OperatorChecklistView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace

    @State private var confirmedPlates = false
    @State private var readyToValidate = false
    @State private var awareOfRecovery = false
    @State private var mixedRealityReady = false

    private var baseChecklistComplete: Bool {
        confirmedPlates && readyToValidate && awareOfRecovery
    }

    private var canStartRun: Bool {
        baseChecklistComplete
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    HStack(alignment: .center) {
                        Button {
                            appModel.goToProtocolReview()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(SecondaryActionButton())

                        Spacer(minLength: 0)

                        SetupProgressIndicator(currentStep: 3, totalSteps: 4)
                    }

                    Text("Operator checklist")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    AppSubtitleText("Complete each item before starting the guided run.")

                    VStack(alignment: .leading, spacing: 14) {
                        OperatorChecklistToggleRow(
                            title: "Source and destination plates are correct",
                            isOn: $confirmedPlates
                        )
                        OperatorChecklistToggleRow(
                            title: "Each transfer step will be validated before continuing",
                            isOn: $readyToValidate
                        )
                        OperatorChecklistToggleRow(
                            title: "If a mismatch appears, I will retry before proceeding",
                            isOn: $awareOfRecovery
                        )
                        OperatorChecklistToggleRow(
                            title: "Show Mixed Reality View",
                            isOn: $mixedRealityReady
                        )
                    }

                    Button("Enter Guided Run") {
                        Task { @MainActor in
                            await openMixedRealityIfNeeded()
                            guard mixedRealityReady else { return }
                            if appModel.isPipetteCalibrationComplete {
                                appModel.beginWorkflow()
                            } else {
                                appModel.goToPipetteCalibrationFromFlow()
                            }
                        }
                    }
                    .buttonStyle(PrimaryActionButton())
                    .disabled(!canStartRun)
                    .opacity(canStartRun ? 1.0 : 0.45)
                }
            }
        }
        .onAppear {
            syncMixedRealityChecklistState()
        }
        .onChange(of: appModel.immersiveSpaceState) { _, _ in
            syncMixedRealityChecklistState()
        }
    }

    private func syncMixedRealityChecklistState() {
        mixedRealityReady = appModel.immersiveSpaceState == .open
    }

    @MainActor
    private func openMixedRealityIfNeeded() async {
        if appModel.immersiveSpaceState == .open {
            mixedRealityReady = true
            return
        }

        appModel.setImmersiveSpaceState(.inTransition)
        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
        if case .opened = result {
            appModel.setImmersiveSpaceState(.open)
            mixedRealityReady = true
        } else {
            appModel.setImmersiveSpaceState(.closed)
            mixedRealityReady = false
        }
    }
}

private struct OperatorChecklistToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? AppUIStyle.accentColor : .secondary)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(AppUIStyle.primaryTextColor)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
            .padding(18)
            .background(OperatorChecklistGlassBackground())
        }
        .buttonStyle(.plain)
    }
}

private struct OperatorChecklistGlassBackground: View {
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
