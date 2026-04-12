//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct LoadProtocolView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                AppSetupCard {
                    Button {
                        appModel.goHome()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    PageEyebrow(title: "Step 1")

                    Text("Load a transfer protocol")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Import the CSV to build the guided run.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        Text("Upload the protocol file to continue.")
                            .font(.headline)

                        Button("Import CSV") {
                            appModel.showImporter()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppUIStyle.accentColor)

                        Text("You will review the full list of steps before the guided run begins.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let errorMessage = appModel.uiState.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(Color.red)
                        }
                    }
                    .padding(20)
                    .background(AppTintedPanel(opacity: 0.68))
                }
            }
        }
    }
}
