import SwiftUI

struct GuidedTransferHeroView: View {
    @Environment(AppModel.self) private var appModel

    let isLoadingState: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isLoadingState {
                SwiftUI.ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AppUIStyle.accentColor)
            }

            CompactRunStatusView()

            WorkflowActionRow()

            if shouldShowValidationStatus {
                ValidationStatusView()
            }
        }
        .padding(14)
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

            AppSubtitleText("The guided transfer sequence has finished. Review the summary below and export the session log if needed.")

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
        VStack(alignment: .center, spacing: 8) {
            Text(appModel.uiState.validationFeedback.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(appModel.uiState.validationFeedback.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage = appModel.uiState.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppUIStyle.feedbackColor(for: appModel.uiState.validationFeedback.tone).opacity(0.12))
        )
    }
}

private struct CompactRunStatusView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(appModel.isAwaitingTipChange ? "Tip Change" : appModel.currentPhase.title)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 13)
                .background(TrackingGlassBackground(cornerRadius: 24))

            VStack(alignment: .center, spacing: 5) {
                Text(statusTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppUIStyle.primaryTextColor)
                    .multilineTextAlignment(.center)

                Text(statusText)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 6)
    }

    private var statusTitle: String {
        if appModel.isAwaitingTipChange {
            return appModel.tipChangeInstructionTitle
        }

        return appModel.progressLabel
    }

    private var statusText: String {
        guard appModel.currentStep != nil else {
            return "No active transfer."
        }

        if appModel.isAwaitingTipChange {
            return appModel.tipChangeInstructionDetail
        }

        if appModel.isPipettePressed {
            return "Pipette press detected."
        }

        return "Waiting for pipette press."
    }
}

private struct WorkflowActionRow: View {
    @Environment(AppModel.self) private var appModel
    private let actionButtonWidth: CGFloat = 188
    private let actionButtonHeight: CGFloat = 52
    private let actionButtonFont = Font.system(size: 15, weight: .semibold, design: .rounded)

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
        if let tipChangeState = appModel.tipChangeState {
            switch tipChangeState {
            case .awaitingEjection:
                Text("Waiting for eject button press")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            case .awaitingReplacement:
                Button("Fresh Tip Attached") {
                    appModel.confirmTipReplacement()
                }
                .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                .buttonStyle(PrimaryActionButton())
            }
        } else {
        switch appModel.uiState.validationResult {
        case .none:
            if appModel.isPreviewTracking {
                HStack(spacing: 12) {
                    Button("Preview Correct") {
                        appModel.validateCurrentPhase()
                    }
                    .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                    .buttonStyle(PrimaryActionButton())

                    Button("Preview Wrong") {
                        appModel.validateCurrentPhase(simulatingMismatch: true)
                    }
                    .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                    .buttonStyle(SecondaryActionButton())

                    Button("Manual Confirm") {
                        appModel.confirmCurrentPhaseManually()
                    }
                    .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                    .buttonStyle(SecondaryActionButton())
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                HStack(spacing: 12) {
                    Button("Check Position") {
                        appModel.validateCurrentPhase()
                    }
                    .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                    .buttonStyle(PrimaryActionButton())

                    Button(appModel.manualConfirmButtonTitle) {
                        appModel.confirmCurrentPhaseManually()
                    }
                    .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                    .buttonStyle(SecondaryActionButton())
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        case .some(.correct):
            Button(appModel.currentPhase.confirmationTitle) {
                appModel.confirmValidationAndAdvance()
            }
            .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
            .buttonStyle(PrimaryActionButton())
        case .some(.incorrect):
            HStack(spacing: 12) {
                Button("Retry") {
                    appModel.retryValidation()
                }
                .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                .buttonStyle(SecondaryActionButton())

                Button("Continue Anyway") {
                    appModel.continueAnyway()
                }
                .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                .buttonStyle(PrimaryActionButton())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        case .some(.blocked):
            HStack(spacing: 12) {
                Button("Try Again") {
                    appModel.retryValidation()
                }
                .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                .buttonStyle(SecondaryActionButton())

                Button(appModel.manualConfirmButtonTitle) {
                    appModel.confirmCurrentPhaseManually()
                }
                .modifier(WorkflowActionButtonLayout(width: actionButtonWidth, height: actionButtonHeight, font: actionButtonFont))
                .buttonStyle(PrimaryActionButton())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        }
    }
}

private struct WorkflowActionButtonLayout: ViewModifier {
    let width: CGFloat
    let height: CGFloat
    let font: Font

    func body(content: Content) -> some View {
        content
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(width: width, height: height, alignment: .center)
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
