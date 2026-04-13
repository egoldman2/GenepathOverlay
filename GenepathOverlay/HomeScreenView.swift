//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

struct HomeScreenView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            AppSetupCard {
                PageEyebrow(title: "GenepathOverlay")

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Vision Pro guidance for well plate workflows")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Guide technicians through transfer steps with mixed-reality overlays and step-by-step validation.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(alignment: .leading, spacing: 12) {
                            FeatureRow(
                                title: "Load one protocol",
                                detail: "Import a CSV once, then move into guided transfer mode."
                            )
                            FeatureRow(
                                title: "Track the real plate",
                                detail: "Highlight the active target well in physical space."
                            )
                            FeatureRow(
                                title: "Validate each action",
                                detail: "Confirm each transfer step before continuing."
                            )
                        }
                    }
                }

                Button("Start Session") {
                    appModel.startSession()
                }
                .buttonStyle(PrimaryActionButton())
            }

            Spacer(minLength: 0)
        }
    }
}
