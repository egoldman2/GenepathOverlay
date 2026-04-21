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
                appModel.goToProtocolReview()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 6) {
                Text("Guided Transfer Workflow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                if let fileName = appModel.uiState.importedFileName {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                Button {
                    appModel.goToWorkflowSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.headline.weight(.semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.bordered)

                Button("Open Steps") {
                    openWindow(id: "step-queue-window")
                }
                .buttonStyle(.bordered)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

                ToggleImmersiveSpaceButton()
                    .buttonStyle(PrimaryActionButton())
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(20)
        .background(AppCardBackground())
    }
}
