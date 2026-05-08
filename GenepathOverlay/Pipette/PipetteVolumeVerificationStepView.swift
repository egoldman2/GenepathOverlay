//
//  PipetteVolumeVerificationStepView.swift
//  GenepathOverlay
//
//  Created by Melissa Lyon on 31/3/2026.
//

import SwiftUI

struct PipetteVolumeVerificationStepView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            targetChip

            Button {
                appModel.confirmCurrentStepVolume()
            } label: {
                Label("Volume Set", systemImage: "checkmark")
            }
            .modifier(VolumeActionButtonLayout())
            .buttonStyle(PrimaryActionButton())
            .disabled(appModel.currentStep == nil)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            targetChip

            Button {
                appModel.confirmCurrentStepVolume()
            } label: {
                Label("Volume Set", systemImage: "checkmark")
            }
            .modifier(VolumeActionButtonLayout())
            .buttonStyle(PrimaryActionButton())
            .disabled(appModel.currentStep == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var targetChip: some View {
        HStack(spacing: 10) {
            Image(systemName: "dial.medium")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppUIStyle.accentColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppUIStyle.accentColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Set volume")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(appModel.volumeVerificationTargetLabel)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppUIStyle.primaryTextColor)

                    Text("before aspiration")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(height: 52)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .background(Capsule().fill(.regularMaterial))
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .accessibilityLabel("Set volume to \(appModel.volumeVerificationTargetLabel) before aspiration")
    }
}

private struct VolumeActionButtonLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(width: 188, height: 52, alignment: .center)
    }
}

#Preview(windowStyle: .plain) {
    PipetteVolumeVerificationStepView()
        .environment(AppModel())
        .padding()
}
