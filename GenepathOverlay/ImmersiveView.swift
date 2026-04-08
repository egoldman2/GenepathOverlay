//
//  ImmersiveView.swift
//  GenepathOverlay
//
//  Created by Ethan on 17/3/2026.
//

import RealityKit
import RealityKitContent
import Foundation
import SwiftUI

struct ImmersiveView: View {
    @Environment(AppModel.self) private var appModel
    private let workflowPanelAttachmentID = "workflow-panel"

    var body: some View {
        RealityView { content, attachments in
            if let immersiveContentEntity = try? await Entity(named: "Immersive", in: realityKitContentBundle) {
                content.add(immersiveContentEntity)
            }

            let workflowPanel = attachments.entity(for: workflowPanelAttachmentID)
            appModel.overlayRenderer.installIfNeeded(
                content: &content,
                mapper: appModel.coordinateMapper,
                workflowPanel: workflowPanel,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
            appModel.overlayRenderer.update(
                currentStep: appModel.currentStep,
                currentPhase: appModel.currentPhase,
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
        } update: { content, attachments in
            let workflowPanel = attachments.entity(for: workflowPanelAttachmentID)
            appModel.overlayRenderer.installIfNeeded(
                content: &content,
                mapper: appModel.coordinateMapper,
                workflowPanel: workflowPanel,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
            appModel.overlayRenderer.update(
                currentStep: appModel.currentStep,
                currentPhase: appModel.currentPhase,
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                showTestPlateModel: appModel.isShowingTestWellPlate
            )
        } attachments: {
            Attachment(id: workflowPanelAttachmentID) {
                banner
                    .frame(width: 320)
            }
        }
        .task {
            appModel.prepareForLaunch()
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mixed Reality Workflow Overlay")
                .font(.headline.weight(.bold))

            Text(appModel.currentInstructionTitle)
                .font(.subheadline.weight(.semibold))

            Text(appModel.currentInstructionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let step = appModel.currentStep {
                HStack(spacing: 14) {
                    detailPill("Source \(step.source.well)")
                    detailPill("Destination \(step.destination.well)")
                    detailPill(formattedVolume(step.volume))
                }
            }

            Text(appModel.trackingMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func detailPill(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.4), in: Capsule())
    }

    private func formattedVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return "\(Int(volume)) uL"
        }

        return String(format: "%.1f uL", volume)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
