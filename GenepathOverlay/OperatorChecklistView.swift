//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct OperatorChecklistView: View {
    @Environment(AppModel.self) private var appModel

    @State private var confirmedPlates = false
    @State private var readyToValidate = false
    @State private var awareOfRecovery = false

    private var canStartRun: Bool {
        confirmedPlates && readyToValidate && awareOfRecovery
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
                    }

                    Button("Start Guided Run") {
                        appModel.beginWorkflow()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppUIStyle.accentColor)
                    .disabled(!canStartRun)
                    .opacity(canStartRun ? 1.0 : 0.45)
                }
            }
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
            .background(AppTintedPanel(opacity: isOn ? 0.76 : 0.5))
        }
        .buttonStyle(.plain)
    }
}
