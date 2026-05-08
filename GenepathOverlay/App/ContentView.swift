//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var appModel

    private var contentPadding: CGFloat {
        appModel.currentScreen == .workflow ? 12 : 28
    }

    private var contentWidth: CGFloat? {
        appModel.currentScreen == .workflow ? nil : 764
    }

    private var contentHeight: CGFloat? {
        appModel.currentScreen == .workflow ? nil : 564
    }

    var body: some View {
        Group {
            switch appModel.currentScreen {
            case .home:
                HomeScreenView()
            case .loadProtocol:
                LoadProtocolView()
            case .protocolHistory:
                ProtocolHistoryView()
            case .protocolReview:
                ProtocolReviewView()
            case .operatorChecklist:
                OperatorChecklistView()
            case .pipetteCalibration:
                PipetteCalibrationSetupView()
            case .workflowSettings:
                WorkflowSettingsView()
            case .workflow:
                ActiveWorkflowView()
            }
        }
        .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        .padding(contentPadding)
        .foregroundStyle(AppUIStyle.primaryTextColor)
        .preferredColorScheme(.dark)
        .defaultHoverEffect(.lift)
        .fileImporter(
            isPresented: Binding(
                get: { appModel.uiState.isShowingImporter },
                set: { appModel.uiState.isShowingImporter = $0 }
            ),
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let needsAccess = url.startAccessingSecurityScopedResource()
                    defer {
                        if needsAccess {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    await appModel.importCSV(from: url)
                case .failure(let error):
                    appModel.uiState.setError(error.localizedDescription)
                }
            }
        }
        .fileExporter(
            isPresented: Binding(
                get: { appModel.uiState.isShowingExporter },
                set: { appModel.uiState.isShowingExporter = $0 }
            ),
            document: appModel.uiState.logDocument,
            contentType: .plainText,
            defaultFilename: "genepath-session-log"
        ) { result in
            if case .failure(let error) = result {
                appModel.uiState.setError(error.localizedDescription)
            }
        }
    }
}

#Preview(windowStyle: .automatic) {
    ContentView()
        .environment(AppModel())
}
