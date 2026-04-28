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

        WindowGroup(id: "step-queue-window") {
            StepQueueWindowView()
                .environment(appModel)
        }
        .defaultSize(width: 320, height: 440)

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
