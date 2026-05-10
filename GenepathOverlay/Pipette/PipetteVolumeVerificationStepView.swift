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
        VStack(alignment: .center, spacing: 12) {
            targetChip

            Button {
                appModel.confirmCurrentStepVolume()
            } label: {
                Label("Confirm", systemImage: "checkmark")
            }
            .modifier(VolumeActionButtonLayout())
            .buttonStyle(PrimaryActionButton())
            .disabled(appModel.currentStep == nil)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 28)
    }

    private var targetChip: some View {
        HStack(spacing: 10) {
            Image(systemName: "dial.medium")
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppUIStyle.accentColor)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppUIStyle.accentColor.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Target volume")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(appModel.volumeVerificationTargetLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppUIStyle.primaryTextColor)
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
            .frame(width: 168, height: 52, alignment: .center)
    }
}

#Preview(windowStyle: .plain) {
    PipetteVolumeVerificationStepView()
        .environment(AppModel())
        .padding()
}
