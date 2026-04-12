//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

enum AppUIStyle {
    static let primaryTextColor = Color(red: 0.11, green: 0.15, blue: 0.22)
    static let accentColor = Color(red: 0.14, green: 0.42, blue: 0.73)
    static let surfaceTint = Color(red: 0.91, green: 0.95, blue: 0.99)
    static let setupCardWidth: CGFloat = 860

    static let backgroundGradient = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.99, blue: 1.0),
            Color(red: 0.93, green: 0.96, blue: 0.99),
            Color(red: 0.90, green: 0.94, blue: 0.98)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func feedbackColor(for tone: ValidationTone) -> Color {
        switch tone {
        case .neutral:
            return Color(red: 0.14, green: 0.31, blue: 0.60)
        case .success:
            return Color(red: 0.10, green: 0.60, blue: 0.32)
        case .failure:
            return Color(red: 0.82, green: 0.24, blue: 0.18)
        case .warning:
            return Color(red: 0.84, green: 0.57, blue: 0.12)
        }
    }

    static func formattedVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return "\(Int(volume)) uL"
        }

        return String(format: "%.1f uL", volume)
    }
}

struct AppUIBackgroundShapes: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AppUIStyle.surfaceTint.opacity(0.95))
                .frame(width: 420, height: 420)
                .blur(radius: 20)
                .offset(x: -320, y: -210)

            Circle()
                .fill(AppUIStyle.accentColor.opacity(0.08))
                .frame(width: 360, height: 360)
                .blur(radius: 18)
                .offset(x: 300, y: -180)

            RoundedRectangle(cornerRadius: 80, style: .continuous)
                .fill(Color.white.opacity(0.25))
                .frame(width: 540, height: 260)
                .rotationEffect(.degrees(-12))
                .blur(radius: 8)
                .offset(x: 260, y: 290)
        }
        .ignoresSafeArea()
    }
}

struct AppCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(Color.white.opacity(0.9))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 22, x: 0, y: 12)
    }
}

struct AppHeroCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.97),
                        Color(red: 0.95, green: 0.97, blue: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1)
            )
            .shadow(color: AppUIStyle.accentColor.opacity(0.10), radius: 26, x: 0, y: 16)
    }
}

struct AppSetupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            content
        }
        .padding(34)
        .frame(maxWidth: AppUIStyle.setupCardWidth, alignment: .leading)
        .background(AppCardBackground())
    }
}

struct AppTintedPanel: View {
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppUIStyle.surfaceTint.opacity(opacity))
    }
}

struct PageEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(AppUIStyle.accentColor)
    }
}

struct FeatureRow: View {
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(AppUIStyle.accentColor.opacity(0.18))
                .frame(width: 28, height: 28)
                .overlay(
                    Circle()
                        .fill(AppUIStyle.accentColor)
                        .frame(width: 8, height: 8)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ChecklistItemView: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(AppUIStyle.accentColor)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct DetailItemView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTintedPanel(opacity: 0.9))
    }
}

struct StateBadgeView: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color.opacity(0.14), in: Capsule())
    }
}
