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
                    HStack(alignment: .center) {
                        Button {
                            appModel.goHome()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(SecondaryActionButton())

                        Spacer(minLength: 0)

                        SetupProgressIndicator(currentStep: 1, totalSteps: 4)
                    }

                    Text("Load a transfer protocol")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    Text("Select an existing CSV file or browse files to begin. File should contain source and destination well coordinates.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 12) {
                        Button {
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                        .buttonStyle(SecondaryActionButton())

                        Button {
                            appModel.showImporter()
                        } label: {
                            Label("Browse", systemImage: "doc")
                        }
                        .buttonStyle(PrimaryActionButton())
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
