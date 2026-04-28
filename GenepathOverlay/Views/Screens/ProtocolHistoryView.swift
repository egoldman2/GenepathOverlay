//
//  ProtocolHistoryView.swift
//  GenepathOverlay
//

import SwiftUI

struct ProtocolHistoryView: View {
    @Environment(AppModel.self) private var appModel

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

                        SetupProgressIndicator(currentStep: 1, totalSteps: 4)
                    }

                    Text("Protocol history")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    AppSubtitleText("Select a recent transfer protocol to review it again without browsing files.")

                    if appModel.protocolHistory.isEmpty {
                        EmptyProtocolHistoryCard()
                    } else {
                        VStack(spacing: 12) {
                            ForEach(appModel.protocolHistory) { entry in
                                Button {
                                    appModel.loadProtocolHistory(entry)
                                } label: {
                                    ProtocolHistoryEntryCard(entry: entry)
                                }
                                .buttonStyle(HistoryCardButtonStyle())
                            }
                        }
                    }

                    if let errorMessage = appModel.uiState.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppUIStyle.feedbackColor(for: .failure))
                    }
                }
            }
        }
    }
}

private struct ProtocolHistoryEntryCard: View {
    let entry: ProtocolHistoryEntry

    var body: some View {
        HStack(spacing: 16) {
            FileBadgeIcon(stepCount: entry.stepCount)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.fileName)
                    .font(.headline)
                    .foregroundStyle(AppUIStyle.primaryTextColor)
                    .lineLimit(1)

                Text("\(entry.stepCount) steps • \(entry.importedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HistoryGlassBackground())
    }
}

private struct FileBadgeIcon: View {
    let stepCount: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(Color.white.opacity(0.08))
                .background(Circle().fill(.regularMaterial))
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: "doc.text")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                )

            Text("\(stepCount)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(AppUIStyle.accentColor, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.42), lineWidth: 1)
                )
                .offset(x: 8, y: -6)
        }
        .frame(width: 68, height: 62)
    }
}

private struct HistoryGlassBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}

private struct HistoryCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct EmptyProtocolHistoryCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)

            Text("No saved protocols yet")
                .font(.headline)
                .foregroundStyle(AppUIStyle.primaryTextColor)

            Text("Import a CSV once, then it will appear here for quick access during testing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HistoryGlassBackground())
    }
}
