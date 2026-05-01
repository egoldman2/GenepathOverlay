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
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 820, height: 620)
        .windowResizability(.contentSize)

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
        .defaultSize(width: 320, height: 440)

        WindowGroup(id: "workflow-settings-window") {
            WorkflowSettingsView(showsWorkflowBackButton: false)
                .environment(appModel)
                .onAppear {
                    appModel.setWorkflowSettingsWindowOpen(true)
                }
                .onDisappear {
                    appModel.setWorkflowSettingsWindowOpen(false)
                }
        }
        .defaultSize(width: 520, height: 560)

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
