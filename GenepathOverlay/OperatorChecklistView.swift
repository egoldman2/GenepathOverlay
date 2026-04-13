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
        baseChecklistComplete && mixedRealityReady
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    Button {
                        appModel.goToProtocolReview()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    PageEyebrow(title: "Step 3")

                    Text("Operator checklist")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Complete each item before starting the guided run.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                            if appModel.immersiveSpaceState == .open {
                                mixedRealityReady = true
                                appModel.beginWorkflow()
                                return
                            }

                            appModel.immersiveSpaceState = .inTransition
                            let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
                            if case .opened = result {
                                appModel.immersiveSpaceState = .open
                                mixedRealityReady = true
                                appModel.beginWorkflow()
                            } else {
                                appModel.immersiveSpaceState = .closed
                                mixedRealityReady = false
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
            .background(AppTintedPanel(opacity: isOn ? 0.76 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
