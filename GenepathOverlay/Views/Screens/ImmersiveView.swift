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
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                highlightedCoordinates: appModel.overlayHighlightedCoordinates,
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
                trackingSnapshot: appModel.trackingSnapshot,
                mapper: appModel.coordinateMapper,
                highlightedCoordinates: appModel.overlayHighlightedCoordinates,
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
        VStack(alignment: .leading, spacing: 14) {
            if let step = appModel.currentStep {
                let targetWell = step.coordinate(for: appModel.currentPhase).well

                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(appModel.progressLabel.uppercased())
                            .font(.caption.weight(.bold))
                            .tracking(1.1)
                            .foregroundStyle(Color.white.opacity(0.72))

                        Text(targetWell)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    }

                    Spacer(minLength: 0)

                    phaseBadge
                }

                HStack(spacing: 10) {
                    metricPill(title: "Target Well", value: targetWell)
                    metricPill(title: "Volume", value: formattedVolume(step.volume))
                }

                if appModel.isPipettePressed {
                    Text("Pipette Button Pressed")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.12), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("WORKFLOW")
                        .font(.caption.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(Color.white.opacity(0.72))

                    Text("Load a protocol to begin")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(stepCardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 20)
    }

    private var phaseBadge: some View {
        Text(appModel.currentPhase.title)
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
    }

    private var stepCardBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(AppUIStyle.containerFill.opacity(0.72))
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.regularMaterial)
            )
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(Color.white.opacity(0.64))

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
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
