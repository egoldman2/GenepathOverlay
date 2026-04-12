import SwiftUI

struct GuidedTransferHeroView: View {
    @Environment(AppModel.self) private var appModel

    let isLoadingState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    PageEyebrow(title: "Active step")

                    Text(appModel.currentInstructionTitle)
                        .font(.system(size: 32, weight: .bold, design: .rounded))

                    Text(appModel.currentInstructionDetail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                StateBadgeView(
                    title: appModel.uiState.appState.title,
                    color: AppUIStyle.feedbackColor(for: appModel.uiState.validationFeedback.tone)
                )
            }

            if isLoadingState {
                SwiftUI.ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AppUIStyle.accentColor)
            }

            HStack(spacing: 14) {
                DetailItemView(title: "Progress", value: appModel.progressLabel)

                if let step = appModel.currentStep {
                    DetailItemView(title: "Source", value: step.source.well)
                    DetailItemView(title: "Destination", value: step.destination.well)
                    DetailItemView(title: "Volume", value: AppUIStyle.formattedVolume(step.volume))
                }
            }
        }
        .padding(28)
        .background(AppHeroCardBackground())
    }
}

struct CompletionHeroView: View {
    let summary: WorkflowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            PageEyebrow(title: "Run complete")

            Text("Protocol completed successfully")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Text("The guided transfer sequence has finished. Review the summary below and export the session log if needed.")
                .font(.title3)
                .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                DetailItemView(title: "Total Steps", value: "\(summary.totalSteps)")
                DetailItemView(title: "Aspiration Warnings", value: "\(summary.aspirationWarnings)")
                DetailItemView(title: "Dispense Warnings", value: "\(summary.dispenseWarnings)")
            }
        }
        .padding(28)
        .background(AppHeroCardBackground())
    }
}

struct WorkflowCardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Current instruction")
                    .font(.headline)

                Spacer(minLength: 0)

                Text(appModel.currentPhase.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppUIStyle.accentColor)
            }

            validationCard

            if let errorMessage = appModel.uiState.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(Color.red)
            }

            actionRow
        }
        .padding(24)
        .background(AppCardBackground())
    }

    private var validationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appModel.uiState.validationFeedback.title)
                .font(.headline)

            Text(appModel.uiState.validationFeedback.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppUIStyle.feedbackColor(for: appModel.uiState.validationFeedback.tone).opacity(0.12))
        )
    }

    @ViewBuilder
    private var actionRow: some View {
        if appModel.currentStep != nil {
            HStack(spacing: 12) {
                switch appModel.uiState.validationResult {
                case .none:
                    if appModel.isPreviewTracking {
                        Button("Preview Correct") {
                            appModel.validateCurrentPhase()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppUIStyle.accentColor)

                        Button("Preview Wrong") {
                            appModel.validateCurrentPhase(simulatingMismatch: true)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button(appModel.currentPhase.actionTitle) {
                            appModel.validateCurrentPhase()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AppUIStyle.accentColor)
                    }
                case .some(.correct):
                    Button(appModel.currentPhase.confirmationTitle) {
                        appModel.confirmValidationAndAdvance()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppUIStyle.accentColor)
                case .some(.incorrect):
                    Button("Retry") {
                        appModel.retryValidation()
                    }
                    .buttonStyle(.bordered)

                    Button("Continue Anyway") {
                        appModel.continueAnyway()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppUIStyle.accentColor)
                case .some(.blocked):
                    Button("Retry Validation") {
                        appModel.retryValidation()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

struct TrackingCardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tracking and alignment")
                .font(.headline)

            Text(appModel.trackingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DetailItemView(title: "Reference Objects", value: appModel.bundledReferenceObjectsLabel)
            DetailItemView(title: "Tracked Plates", value: appModel.trackedPlatesLabel)
            DetailItemView(title: "Test Plate Model", value: appModel.testWellPlateModelName)

            Toggle("Show Test Well Plate Model", isOn: Binding(
                get: { appModel.isShowingTestWellPlate },
                set: { appModel.isShowingTestWellPlate = $0 }
            ))
            .disabled(!appModel.isTestWellPlateModelAvailable)

            Text(
                appModel.isTestWellPlateModelAvailable
                    ? "Use the bundled USDZ model when you want to test the workflow in preview mode."
                    : "Add a well plate `.usdz` file to `ReferenceObjects/` to enable the simulated plate model."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if appModel.isPreviewTracking {
                Text("Preview mode is active because live tracking assets are still being prepared.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(AppCardBackground())
    }
}

struct OperatorFocusCardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Operator focus")
                .font(.headline)

            Text("Keep the technician focused on the highlighted target well and the current phase. Everything else should support that action.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ChecklistItemView(text: "Validate the current action before moving on")
            ChecklistItemView(text: "Use the mixed reality view when plate guidance is needed")
            ChecklistItemView(text: "Retry immediately if a mismatch is detected")
        }
        .padding(22)
        .background(AppCardBackground())
    }
}

struct StepQueueCardView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Upcoming steps")
                    .font(.headline)

                Spacer(minLength: 0)

                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(appModel.previewSteps) { step in
                HStack(spacing: 14) {
                    Text("\(step.sequenceNumber)")
                        .font(.headline.weight(.semibold))
                        .frame(width: 30, alignment: .leading)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(step.source.well) to \(step.destination.well)")
                            .font(.subheadline.weight(.semibold))

                        Text(AppUIStyle.formattedVolume(step.volume))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(24)
        .background(AppCardBackground())
    }
}

struct SessionSummaryCardView: View {
    @Environment(AppModel.self) private var appModel

    let summary: WorkflowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Session summary")
                .font(.headline)

            Text("Completed at \(summary.completedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Export Log") {
                appModel.exportLog()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppUIStyle.accentColor)
        }
        .padding(22)
        .background(AppCardBackground())
    }
}
