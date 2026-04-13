//
//  ContentView.swift
//  GenepathOverlay
//
//  Created by Ethan on 12/4/2026.
//

import SwiftUI

enum AppUIStyle {
    static let primaryTextColor = Color(red: 0.96, green: 0.96, blue: 0.97)
    static let accentColor = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let setupCardWidth: CGFloat = 760
    static let groupFill = Color(red: 0.19, green: 0.20, blue: 0.23)
    static let containerFill = Color(red: 0.27, green: 0.28, blue: 0.31)
    static let dividerStroke = Color.white.opacity(0.09)
    static let cardStroke = Color.white.opacity(0.12)

    static func feedbackColor(for tone: ValidationTone) -> Color {
        switch tone {
        case .neutral:
            return Color(red: 0.39, green: 0.66, blue: 1.0)
        case .success:
            return Color(red: 0.31, green: 0.83, blue: 0.51)
        case .failure:
            return Color(red: 1.0, green: 0.41, blue: 0.39)
        case .warning:
            return Color(red: 1.0, green: 0.76, blue: 0.33)
        }
    }

    static func formattedVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return "\(Int(volume)) uL"
        }

        return String(format: "%.1f uL", volume)
    }
}

struct AppCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(AppUIStyle.containerFill.opacity(0.74))
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(AppUIStyle.cardStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 22, x: 0, y: 12)
    }
}

struct AppHeroCardBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(AppUIStyle.containerFill.opacity(0.76))
            .background(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .stroke(AppUIStyle.cardStroke, lineWidth: 1)
            )
            .shadow(color: AppUIStyle.accentColor.opacity(0.10), radius: 24, x: 0, y: 14)
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
    }
}

struct AppTintedPanel: View {
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppUIStyle.groupFill.opacity(0.92))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppUIStyle.dividerStroke, lineWidth: 1)
            )
            .opacity(opacity)
    }
}

struct PrimaryActionButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(AppUIStyle.accentColor.opacity(configuration.isPressed ? 0.78 : 1))
            )
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
                    .foregroundStyle(AppUIStyle.primaryTextColor)

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
                .foregroundStyle(AppUIStyle.primaryTextColor)
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
