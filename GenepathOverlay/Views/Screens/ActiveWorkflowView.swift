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
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    private let panelWidth: CGFloat = 460
    private let panelHeight: CGFloat = 380

    private var isCompletedState: Bool {
        appModel.uiState.summary != nil
    }

    private var isLoadingState: Bool {
        switch appModel.uiState.appState {
        case .loadingCSV, .mapping:
            return true
        default:
            return false
        }
    }

    var body: some View {
        Group {
            if isCompletedState {
                VStack {
                    Spacer(minLength: 0)
                    CompletionHeroView()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    topBar
                    GuidedTransferHeroView(isLoadingState: isLoadingState)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, isCompletedState ? 22 : 18)
        .padding(.bottom, isCompletedState ? 22 : 24)
        .frame(
            width: panelWidth,
            height: panelHeight,
            alignment: isCompletedState ? .center : .topLeading
        )
        .onAppear {
            appModel.setWorkflowScreenVisible(true)
        }
        .onDisappear {
            appModel.setWorkflowScreenVisible(false)
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if appModel.uiState.summary != nil {
            EmptyView()
        } else {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    Task { @MainActor in
                        await closeMixedRealityBeforeGoingBack()
                        appModel.goToProtocolReview()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(CompactIconButtonStyle())
                .help("Back")

                VStack(alignment: .leading, spacing: 3) {
                    Text("Workflow")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)

                    Text(appModel.uiState.importedFileName ?? "Transfer Protocol")
                        .font(.headline.weight(.semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                toolBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var toolBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                toggleStepQueueWindow()
            } label: {
                Image(systemName: "list.bullet")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(ToolTrayIconButtonStyle())
            .help("Open Steps")

            ToggleImmersiveSpaceButton()

            Button {
                toggleWorkflowSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(ToolTrayIconButtonStyle())
            .help("Settings")
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func toggleStepQueueWindow() {
        if appModel.isStepQueueWindowOpen {
            dismissWindow(id: "step-queue-window")
            appModel.setStepQueueWindowOpen(false)
        } else {
            openWindow(id: "step-queue-window")
            appModel.setStepQueueWindowOpen(true)
        }
    }

    private func toggleWorkflowSettingsWindow() {
        if appModel.isWorkflowSettingsWindowOpen {
            dismissWindow(id: "workflow-settings-window")
            appModel.setWorkflowSettingsWindowOpen(false)
        } else {
            openWindow(id: "workflow-settings-window")
            appModel.setWorkflowSettingsWindowOpen(true)
        }
    }

    @MainActor
    private func closeMixedRealityBeforeGoingBack() async {
        guard appModel.immersiveSpaceState != .closed else { return }

        appModel.setImmersiveSpaceState(.inTransition)
        await dismissImmersiveSpace()
        appModel.setImmersiveSpaceState(.closed)
    }
}
