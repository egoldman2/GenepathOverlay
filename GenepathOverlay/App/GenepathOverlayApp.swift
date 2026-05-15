//
//  GenepathOverlayApp.swift
//  GenepathOverlay
//
//  Created by Ethan on 17/3/2026.
//

import SwiftUI

@main
struct GenepathOverlayApp: App {

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup(id: "main-window") {
            MainWindowSceneView()
                .environment(appModel)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Pipette") {
                Button("Record Plunger Press") {
                    appModel.recordExternalPipetteButtonRelease(.plunger)
                }
                .keyboardShortcut("p", modifiers: [])

                Button("Record Tip Eject Press") {
                    appModel.recordExternalPipetteButtonRelease(.tipEject)
                }
                .keyboardShortcut("e", modifiers: [])
            }
        }

        WindowGroup(id: "step-queue-window") {
            StepQueueWindowView()
                .environment(appModel)
                .onAppear {
                    appModel.setStepQueueWindowOpen(true)
                }
                .onDisappear {
                    appModel.setStepQueueWindowOpen(false)
                }
        }
        .defaultSize(width: 420, height: 560)
        .windowResizability(.contentSize)

        WindowGroup(id: "workflow-settings-window") {
            WorkflowSettingsView(showsWorkflowBackButton: false)
                .frame(width: 920, height: 680)
                .environment(appModel)
                .onAppear {
                    appModel.setWorkflowSettingsWindowOpen(true)
                }
                .onDisappear {
                    appModel.setWorkflowSettingsWindowOpen(false)
                }
        }
        .defaultSize(width: 920, height: 680)
        .windowResizability(.contentSize)

        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.setImmersiveSpaceState(.open)
                }
                .onDisappear {
                    appModel.setImmersiveSpaceState(.closed)
                }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

private struct MainWindowSceneView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasRunInitialWindowCleanup = false

    var body: some View {
        ContentView()
            .task {
                appModel.prepareForLaunch()

                guard hasRunInitialWindowCleanup == false else { return }
                hasRunInitialWindowCleanup = true
                appModel.setMainWindowOpen(true)
                appModel.setClosingAuxiliaryWindowsFromMainWindow(false)
                closeAuxiliaryWindows()
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    appModel.setMainWindowOpen(true)
                    appModel.setClosingAuxiliaryWindowsFromMainWindow(false)
                case .background:
                    closeMainWindowAndAuxiliaryWindows()
                case .inactive:
                    break
                @unknown default:
                    break
                }
            }
            .onDisappear {
                closeMainWindowAndAuxiliaryWindows()
            }
    }

    private func closeMainWindowAndAuxiliaryWindows() {
        appModel.setClosingAuxiliaryWindowsFromMainWindow(true)
        appModel.setMainWindowOpen(false)
        closeAuxiliaryWindows()
    }

    private func closeAuxiliaryWindows() {
        dismissWindow(id: "step-queue-window")
        appModel.setStepQueueWindowOpen(false)

        dismissWindow(id: "workflow-settings-window")
        appModel.setWorkflowSettingsWindowOpen(false)
    }
}
