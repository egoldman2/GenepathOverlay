import SwiftUI

struct GuidedTransferHeroView: View {
    @Environment(AppModel.self) private var appModel

    let isLoadingState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoadingState {
                SwiftUI.ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AppUIStyle.accentColor)
            }

            CompactRunStatusView()

            if shouldShowValidationStatus {
                ValidationStatusView()
            }

            WorkflowActionRow()
        }
        .padding(22)
    }

    private var shouldShowValidationStatus: Bool {
        appModel.uiState.validationResult != nil || appModel.uiState.errorMessage != nil
    }
}

struct CompletionHeroView: View {
    let summary: WorkflowSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
    }
}

struct WorkflowCardView: View {
    var body: some View {
        EmptyView()
    }
}

private struct ValidationStatusView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appModel.uiState.validationFeedback.title)
                .font(.headline)

            Text(appModel.uiState.validationFeedback.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let errorMessage = appModel.uiState.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppUIStyle.feedbackColor(for: appModel.uiState.validationFeedback.tone).opacity(0.12))
        )
    }
}

private struct CompactRunStatusView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(appModel.progressLabel)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppUIStyle.primaryTextColor)

                Text(statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(appModel.currentPhase.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(TrackingGlassBackground(cornerRadius: 18))
    }

    private var statusText: String {
        guard appModel.currentStep != nil else {
            return "No active transfer."
        }

        if appModel.isPipettePressed {
            return "Pipette press detected."
        }

        return "Waiting for pipette press."
    }
}

private struct WorkflowActionRow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        if appModel.currentStep != nil {
            ViewThatFits(in: .horizontal) {
                actionButtons
                VStack(alignment: .leading, spacing: 12) {
                    actionButtons
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch appModel.uiState.validationResult {
        case .none:
            if appModel.isPreviewTracking {
                HStack(spacing: 12) {
                    Button("Preview Correct") {
                        appModel.validateCurrentPhase()
                    }
                    .buttonStyle(PrimaryActionButton())

                    Button("Preview Wrong") {
                        appModel.validateCurrentPhase(simulatingMismatch: true)
                    }
                    .buttonStyle(SecondaryActionButton())

                    Button("Manual Confirm") {
                        appModel.confirmCurrentPhaseManually()
                    }
                    .buttonStyle(SecondaryActionButton())
                }
            } else {
                HStack(spacing: 12) {
                    Button("Check Position") {
                        appModel.validateCurrentPhase()
                    }
                    .buttonStyle(PrimaryActionButton())

                    Button(appModel.manualConfirmButtonTitle) {
                        appModel.confirmCurrentPhaseManually()
                    }
                    .buttonStyle(SecondaryActionButton())
                }
            }
        case .some(.correct):
            Button(appModel.currentPhase.confirmationTitle) {
                appModel.confirmValidationAndAdvance()
            }
            .buttonStyle(PrimaryActionButton())
        case .some(.incorrect):
            HStack(spacing: 12) {
                Button("Retry") {
                    appModel.retryValidation()
                }
                .buttonStyle(SecondaryActionButton())

                Button("Continue Anyway") {
                    appModel.continueAnyway()
                }
                .buttonStyle(PrimaryActionButton())
            }
        case .some(.blocked):
            HStack(spacing: 12) {
                Button("Try Again") {
                    appModel.retryValidation()
                }
                .buttonStyle(SecondaryActionButton())

                Button(appModel.manualConfirmButtonTitle) {
                    appModel.confirmCurrentPhaseManually()
                }
                .buttonStyle(PrimaryActionButton())
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
            PipetteInputStatusCard(compact: false)

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
        .background(TrackingGlassBackground())
    }
}

private struct PipetteInputStatusCard: View {
    @Environment(AppModel.self) private var appModel

    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Label("Pipette button", systemImage: appModel.isPipettePressed ? "hand.thumbsup.fill" : "hand.thumbsup")
                    .font(.headline)

                Spacer(minLength: 0)

                Text(appModel.pipettePressLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appModel.isPipettePressed ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(appModel.isPipettePressed ? AppUIStyle.accentColor.opacity(0.9) : Color.white.opacity(0.08))
                    )
            }

            Text(appModel.pipetteTrackingMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if compact == false {
                DetailItemView(title: "Selected Hand", value: appModel.selectedPipetteHandLabel)
                DetailItemView(title: "Calibration", value: appModel.pipetteCalibrationMessage)
                DetailItemView(title: "Grip Confidence", value: appModel.pipetteGripConfidenceLabel)
                DetailItemView(title: "Press Count", value: "\(appModel.pipetteInputState.pressCount)")
                DetailItemView(title: "Last Event", value: appModel.lastPipetteEventLabel)
                Text(appModel.pipetteCalibrationProgressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Hand: \(appModel.selectedPipetteHandLabel) • Grip: \(appModel.pipetteGripConfidenceLabel) • Presses: \(appModel.pipetteInputState.pressCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(appModel.lastPipetteEventLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(TrackingGlassBackground(cornerRadius: 18))
    }
}

private struct TrackingGlassBackground: View {
    var cornerRadius: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.white.opacity(0.08))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
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
            .buttonStyle(PrimaryActionButton())
        }
        .padding(22)
        .background(AppCardBackground())
    }
}
