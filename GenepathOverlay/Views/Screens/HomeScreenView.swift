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
                HomeLogoMark()

                homeHeader

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
            .offset(y: -36)

            Spacer(minLength: 0)
        }
    }

    private var homeHeader: some View {
        VStack(spacing: 12) {
            Text("Vision Pro Guidance for Well Plate Workflows")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .frame(maxWidth: 620, alignment: .center)

            Text("Guide technicians through transfer steps with mixed-reality overlays and step-by-step validation.")
                .font(.system(size: 18, weight: .regular, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct HomeLogoMark: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            AppUIStyle.accentColor.opacity(0.18),
                            Color.white.opacity(0.03),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 6,
                        endRadius: 84
                    )
                )
                .frame(width: 144, height: 144)

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .frame(width: 112, height: 112)
                .background(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: AppUIStyle.accentColor.opacity(0.10), radius: 20, x: 0, y: 12)

            Image("HomeLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 86, height: 86)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.bottom, 2)
    }
}
