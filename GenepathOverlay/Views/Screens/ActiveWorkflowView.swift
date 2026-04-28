//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct ActiveWorkflowView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private var isLoadingState: Bool {
        switch appModel.uiState.appState {
        case .loadingCSV, .mapping:
            return true
        default:
            return false
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                topBar

                if let summary = appModel.uiState.summary {
                    CompletionHeroView(summary: summary)
                } else {
                    GuidedTransferHeroView(isLoadingState: isLoadingState)
                }

                if let summary = appModel.uiState.summary {
                    SessionSummaryCardView(summary: summary)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                Task { @MainActor in
                    await closeMixedRealityBeforeGoingBack()
                    appModel.goToProtocolReview()
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryActionButton())

            VStack(alignment: .leading, spacing: 6) {
                Text(appModel.uiState.importedFileName ?? "Transfer Protocol")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    openWindow(id: "step-queue-window")
                } label: {
                    Text(appModel.progressLabel)
                        .foregroundStyle(.white)
                }
                .buttonStyle(StepPillButtonStyle())
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .help("Open Steps")

                ToggleImmersiveSpaceButton()

                Button {
                    appModel.goToWorkflowSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(CompactIconButtonStyle())
                .help("Settings")
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(20)
    }

    @MainActor
    private func closeMixedRealityBeforeGoingBack() async {
        guard appModel.immersiveSpaceState != .closed else { return }

        appModel.setImmersiveSpaceState(.inTransition)
        await dismissImmersiveSpace()
        appModel.setImmersiveSpaceState(.closed)
    }
}
