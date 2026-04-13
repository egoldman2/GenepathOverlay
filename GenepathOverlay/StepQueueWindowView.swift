import SwiftUI

struct StepQueueWindowView: View {
    @Environment(AppModel.self) private var appModel

    private var currentStepID: UUID? {
        appModel.currentStep?.id
    }

    private var lastStepID: UUID? {
        appModel.sequenceEngine.allSteps.last?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageEyebrow(title: "Reference")

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
                .background(AppTintedPanel(opacity: 0.88))
            }
            .padding(26)
            .frame(maxWidth: 380, alignment: .leading)
        }
        .foregroundStyle(AppUIStyle.primaryTextColor)
        .preferredColorScheme(.dark)
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
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppUIStyle.accentColor.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(AppUIStyle.accentColor.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }
}
