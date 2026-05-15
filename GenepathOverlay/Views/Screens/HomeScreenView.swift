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
                AppScreenHeader(
                    title: "Vision Pro Guidance for Well Plate Workflows",
                    subtitle: "Guide technicians through transfer steps with mixed-reality overlays and step-by-step validation."
                )

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
                .frame(maxWidth: 480, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)

                Button("Start Session") {
                    appModel.startSession()
                }
                .buttonStyle(PrimaryActionButton())
                .frame(maxWidth: .infinity, alignment: .center)
            }

            Spacer(minLength: 0)
        }
    }
}
