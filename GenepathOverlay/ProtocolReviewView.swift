//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct ProtocolReviewView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isTransferListExpanded = false

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
                        DisclosureGroup(isExpanded: $isTransferListExpanded) {
                            VStack(alignment: .leading, spacing: 10) {
                                TransferListHeaderRow()

                                Divider()
                                    .overlay(AppUIStyle.groupFill.opacity(0.9))

                                LazyVStack(alignment: .leading, spacing: 6) {
                                    ForEach(appModel.sequenceEngine.allSteps) { step in
                                        TransferListRow(step: step)
                                    }
                                }
                            }
                            .padding(.top, 12)
                        } label: {
                            HStack {
                                Text("Transfer list")
                                    .font(.headline)

                                Spacer(minLength: 0)

                                Text("\(appModel.sequenceEngine.totalSteps) steps")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tint(AppUIStyle.primaryTextColor)
                        .padding(18)
                        .background(AppTintedPanel(opacity: 0.52))
                    }

                    HStack(spacing: 12) {
                        Button("Continue") {
                            appModel.goToOperatorChecklist()
                        }
                        .buttonStyle(PrimaryActionButton())

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

private struct TransferListHeaderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Step")
                .frame(width: 56, alignment: .leading)

            Text("Source")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Destination")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Volume")
                .frame(width: 88, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct TransferListRow: View {
    let step: Step

    var body: some View {
        HStack(spacing: 10) {
            Text("\(step.sequenceNumber)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 56, alignment: .leading)

            coordinatePill(step.source.well)

            coordinatePill(step.destination.well)

            Text(AppUIStyle.formattedVolume(step.volume))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 88, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private func coordinatePill(_ well: String) -> some View {
        Text(well)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppUIStyle.primaryTextColor)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTintedPanel(opacity: 0.72))
    }
}
