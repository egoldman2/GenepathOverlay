//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct ActiveWorkflowView: View {
    @Environment(AppModel.self) private var appModel

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

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        WorkflowCardView()

                        if !appModel.previewSteps.isEmpty {
                            StepQueueCardView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 20) {
                        TrackingCardView()

                        if let summary = appModel.uiState.summary {
                            SessionSummaryCardView(summary: summary)
                        } else {
                            OperatorFocusCardView()
                        }
                    }
                    .frame(width: 320, alignment: .leading)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    appModel.goToProtocolReview()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)

                PageEyebrow(title: "Current session")

                Text("Guided Transfer Workflow")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                if let fileName = appModel.uiState.importedFileName {
                    Text(fileName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            ToggleImmersiveSpaceButton()
                .buttonStyle(.borderedProminent)
                .tint(AppUIStyle.accentColor)
        }
        .padding(24)
        .background(AppCardBackground())
    }
}
