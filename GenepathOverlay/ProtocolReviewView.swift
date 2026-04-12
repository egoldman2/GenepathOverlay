//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct ProtocolReviewView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    Button {
                        appModel.goToLoadProtocol()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    PageEyebrow(title: "Step 2")

                    Text("Review protocol before starting")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Check the loaded file and transfer list before continuing.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Run summary")
                            .font(.headline)

                        DetailItemView(title: "Loaded File", value: appModel.uiState.importedFileName ?? "No file selected")
                        DetailItemView(title: "Total Steps", value: "\(appModel.sequenceEngine.totalSteps)")
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Transfer list")
                            .font(.headline)

                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(appModel.sequenceEngine.allSteps) { step in
                                HStack(spacing: 16) {
                                    Text("Step \(step.sequenceNumber)")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(width: 78, alignment: .leading)

                                    Text("\(step.source.well) to \(step.destination.well)")
                                        .font(.subheadline)

                                    Spacer(minLength: 0)

                                    Text(AppUIStyle.formattedVolume(step.volume))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .padding(20)
                        .background(AppTintedPanel(opacity: 0.52))
                    }

                    HStack(spacing: 12) {
                        Button("Continue") {
                            appModel.goToOperatorChecklist()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppUIStyle.accentColor)

                        Button("Re-import CSV") {
                            appModel.showImporter()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
