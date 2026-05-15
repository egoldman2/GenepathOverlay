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

                    AppScreenHeader(
                        title: "Load a transfer protocol",
                        subtitle: "Select an existing CSV file or browse files to begin. File should contain source and destination well coordinates."
                    )

                    HStack(spacing: 12) {
                        Button {
                            appModel.goToProtocolHistory()
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
                    .frame(maxWidth: .infinity, alignment: .center)

                    if let errorMessage = appModel.uiState.errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(AppUIStyle.feedbackColor(for: .failure))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }
}

#Preview {
    LoadProtocolView()
}
