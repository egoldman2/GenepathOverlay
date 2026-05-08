import SwiftUI

struct StepQueueWindowView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    private var currentStepID: UUID? {
        appModel.currentStep?.id
    }

    private var lastStepID: UUID? {
        appModel.sequenceEngine.allSteps.last?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Queued steps")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(appModel.sequenceEngine.allSteps) { step in
                        StepQueueRowView(
                            step: step,
                            isCurrent: step.id == currentStepID
                        )

                        if step.id != lastStepID {
                            Divider()
                                .overlay(AppUIStyle.dividerStroke)
                                .padding(.leading, 18)
                        }
                    }
                }
                .background(StepQueueGlassBackground())
            }
            .padding(26)
            .frame(maxWidth: 430, alignment: .leading)
        }
        .foregroundStyle(AppUIStyle.primaryTextColor)
        .preferredColorScheme(.dark)
        .task {
            guard appModel.isWorkflowScreenVisible == false || appModel.isMainWindowOpen == false else { return }
            await closeQueueAndRestoreMainWindowIfNeeded()
        }
        .onChange(of: appModel.isMainWindowOpen) { _, isOpen in
            guard isOpen == false else { return }
            Task {
                await closeQueueAndRestoreMainWindowIfNeeded()
            }
        }
        .onChange(of: appModel.isWorkflowScreenVisible) { _, isVisible in
            guard isVisible == false else { return }
            Task {
                await closeQueueAndRestoreMainWindowIfNeeded()
            }
        }
    }

    private func closeQueueAndRestoreMainWindowIfNeeded() async {
        await Task.yield()

        if appModel.isMainWindowOpen == false,
           appModel.isClosingAuxiliaryWindowsFromMainWindow == false {
            openWindow(id: "main-window")
        }

        appModel.setStepQueueWindowOpen(false)
        dismiss()
    }
}

private struct StepQueueRowView: View {
    let step: Step
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("Step \(step.sequenceNumber)")
                .font(.subheadline.weight(.semibold))
                .frame(width: 70, alignment: .leading)

            Text(step.source.well)
                .font(.subheadline)
                .foregroundStyle(AppUIStyle.primaryTextColor)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(step.destination.well)
                .font(.subheadline)
                .foregroundStyle(AppUIStyle.primaryTextColor)

            Spacer(minLength: 0)

            Text(AppUIStyle.formattedVolume(step.volume))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }
}

private struct StepQueueGlassBackground: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
    }
}
