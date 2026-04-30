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
                    HStack(alignment: .center) {
                        Button {
                            appModel.goToLoadProtocol()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(SecondaryActionButton())

                        Spacer(minLength: 0)

                        SetupProgressIndicator(currentStep: 2, totalSteps: 4)
                    }

                    Text("Review protocol before starting")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    AppSubtitleText("Check the loaded file and transfer list before continuing.")

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Run summary")
                            .font(.headline)

                        ReviewFileSummary(
                            title: "Loaded File",
                            value: appModel.uiState.importedFileName ?? "No file selected"
                        )

                        ReviewExpandableCard(
                            title: "Total Steps",
                            value: "\(appModel.sequenceEngine.totalSteps)",
                            actionTitle: isTransferListExpanded ? "Hide >" : "View >",
                            isExpanded: $isTransferListExpanded
                        )

                        if isTransferListExpanded {
                            ScrollView {
                                LazyVGrid(
                                    columns: [
                                        GridItem(.flexible(), spacing: 10),
                                        GridItem(.flexible(), spacing: 10)
                                    ],
                                    alignment: .leading,
                                    spacing: 8
                                ) {
                                    ForEach(appModel.sequenceEngine.allSteps) { step in
                                        TransferListRow(step: step)
                                    }
                                }
                            }
                            .frame(maxHeight: 260)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(ReviewGlassBackground())
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Re-import CSV") {
                            appModel.showImporter()
                        }
                        .buttonStyle(SecondaryActionButton())

                        Button("Continue") {
                            appModel.goToOperatorChecklist()
                        }
                        .buttonStyle(PrimaryActionButton())
                    }
                }
            }
        }
    }
}

private struct TransferListRow: View {
    let step: Step

    var body: some View {
        HStack(spacing: 8) {
            Text("\(step.sequenceNumber)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )

            coordinateText(step.source.well)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            coordinateText(step.destination.well)

            Spacer(minLength: 4)

            Text(AppUIStyle.formattedVolume(step.volume))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(TransferChipBackground())
    }

    private func coordinateText(_ well: String) -> some View {
        Text(well)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppUIStyle.primaryTextColor)
            .frame(minWidth: 34, alignment: .leading)
    }
}

private struct TransferChipBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

private struct ReviewFileSummary: View {
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
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}

private struct ReviewExpandableCard: View {
    let title: String
    let value: String
    let actionTitle: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(value)
                        .font(.headline)
                        .foregroundStyle(AppUIStyle.primaryTextColor)
                }

                Spacer(minLength: 0)

                Text(actionTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(ReviewGlassBackground())
        }
        .buttonStyle(ReviewCardButtonStyle())
    }
}

private struct ReviewGlassBackground: View {
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

private struct ReviewCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 20, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .hoverEffect(.highlight)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
