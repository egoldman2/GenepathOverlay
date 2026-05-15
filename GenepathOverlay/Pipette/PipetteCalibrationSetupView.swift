import SwiftUI

struct PipetteCalibrationSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @State private var isSkipCalibrationConfirmationPresented = false
    private let settingsPresentationOverride: Bool?
    private let onBack: (() -> Void)?
    private let calibrationActionWidth: CGFloat = 240
    private let poseCalibrationActionWidth: CGFloat = 236
    private let poseCalibrationActionHeight: CGFloat = 54

    init(
        isSettingsPresentation: Bool? = nil,
        onBack: (() -> Void)? = nil
    ) {
        self.settingsPresentationOverride = isSettingsPresentation
        self.onBack = onBack
    }

    private var canCapture: Bool {
        appModel.immersiveSpaceState == .open && appModel.selectedPipetteHand != nil
    }

    private var isSettingsMode: Bool {
        settingsPresentationOverride ?? appModel.pipetteCalibrationOpenedFromSettings
    }

    private var liveStage: CalibrationStage {
        if appModel.isCalibrationTipAttached == false {
            return .attachTip
        }

        if appModel.isPipetteCalibrationComplete {
            return .ready
        }

        if appModel.selectedPipetteHand == nil {
            return .chooseHand
        }

        switch appModel.pipetteInputState.calibration.step {
        case .readyForPress, .collectingPress:
            return .pressedPose
        case .adjustingTip:
            return .tipAdjustment
        case .failed:
            return .failed
        default:
            return .restPose
        }
    }

    private var displayStage: CalibrationStage { liveStage }

    private var shouldShowCalibrationProgress: Bool {
        switch displayStage {
        case .restPose, .pressedPose, .tipAdjustment, .ready, .failed:
            return true
        case .attachTip, .chooseHand:
            return false
        }
    }

    var body: some View {
        AppSetupCard {
            header

            VStack(spacing: 10) {
                Text(isSettingsMode ? "Pipette Calibration" : "Pipette calibration")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)

                topMixedRealityStatus
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: 12) {
                CalibrationStepRail(currentStep: displayStage.stepNumber)
                if shouldShowCalibrationProgress {
                    compactCalibrationProgress
                }
            }
            .padding(.top, -4)
            .padding(.bottom, -8)

            stageCard
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .confirmationDialog(
            "Skip pipette calibration?",
            isPresented: $isSkipCalibrationConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Skip Calibration", role: .destructive) {
                appModel.beginWorkflow()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Skipping calibration disables pipette hand tracking, automatic press detection, and tip alignment. Continue only if you plan to rely on manual confirmation.")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                if let onBack {
                    onBack()
                } else {
                    appModel.leavePipetteCalibration()
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(SecondaryActionButton())

            Spacer(minLength: 0)

            if isSettingsMode == false && displayStage != .ready {
                Spacer(minLength: 0)
            }

            if isSettingsMode == false && displayStage != .ready {
                Button("Skip Calibration") {
                    isSkipCalibrationConfirmationPresented = true
                }
                .buttonStyle(SecondaryActionButton())
            }
        }
    }

    @ViewBuilder
    private var stageCard: some View {
        VStack(alignment: .center, spacing: 12) {
            Text(displayStage.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .multilineTextAlignment(.center)
                .frame(maxWidth: displayStage.isPoseCapture ? 560 : .infinity, alignment: .center)
                .offset(x: displayStage.isPoseCapture ? -98 : 0)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .center, spacing: 14) {
                    if displayStage != .tipAdjustment {
                        Text(displayStage.instruction)
                            .font(.system(size: 17, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: displayStage.isPoseCapture ? 44 : nil, alignment: .top)
                    }

                    stageControls
                }
                .frame(maxWidth: .infinity, alignment: .center)

                if let illustrationAssetName = displayStage.illustrationAssetName {
                    CalibrationPoseIllustration(
                        assetName: illustrationAssetName,
                        accessibilityLabel: displayStage.illustrationAccessibilityLabel,
                        size: displayStage.illustrationSize
                    )
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var stageControls: some View {
        switch displayStage {
        case .attachTip:
            VStack(alignment: .center, spacing: 12) {
                Text("Calibration assumes a tip is already attached before hand pose capture and final tip alignment.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 520, alignment: .center)

                Button {
                    appModel.confirmCalibrationTipAttached()
                } label: {
                    Label("Tip Attached", systemImage: "checkmark")
                }
                .frame(width: calibrationActionWidth)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonStyle(PrimaryActionButton())
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .chooseHand:
            HStack(spacing: 12) {
                handSelectionButton(.left)
                handSelectionButton(.right)
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .restPose:
            poseCaptureControls(
                primaryTitle: "Capture Rest Position",
                secondaryTitle: "Change Hand",
                secondaryDisabled: false,
                primaryAction: {
                    appModel.startRestCalibrationCapture()
                },
                secondaryAction: {
                    appModel.setPipetteHandedness(nil)
                }
            )

        case .pressedPose:
            poseCaptureControls(
                primaryTitle: "Capture Pressed Position",
                secondaryTitle: "Recapture Rest",
                secondaryDisabled: !canCapture,
                primaryAction: {
                    appModel.startPressedCalibrationCapture()
                },
                secondaryAction: {
                    appModel.startRestCalibrationCapture()
                }
            )

        case .tipAdjustment:
            tipAdjustmentControls

        case .ready:
            HStack(spacing: 12) {
                Button(isSettingsMode ? "Done" : "Start Guided Run") {
                    if isSettingsMode {
                        if let onBack {
                            onBack()
                        } else {
                            appModel.leavePipetteCalibration()
                        }
                    } else {
                        appModel.beginWorkflow()
                    }
                }
                .frame(width: calibrationActionWidth)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonStyle(PrimaryActionButton())

                Button("Recalibrate") {
                    appModel.resetPipetteCalibration()
                }
                .frame(width: calibrationActionWidth)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonStyle(SecondaryActionButton())
            }
            .frame(maxWidth: .infinity, alignment: .center)

        case .failed:
            HStack(spacing: 12) {
                Button("Try Again") {
                    appModel.resetPipetteCalibration()
                }
                .frame(width: calibrationActionWidth)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonStyle(PrimaryActionButton())

                Button("Change Hand") {
                    appModel.setPipetteHandedness(nil)
                }
                .frame(width: calibrationActionWidth)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .buttonStyle(SecondaryActionButton())
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var mixedRealityControl: some View {
        Group {
            if appModel.immersiveSpaceState == .open {
                Label("Mixed Reality View is open", systemImage: "visionpro")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
            } else {
                Button {
                    Task { @MainActor in
                        await openMixedRealityIfNeeded()
                    }
                } label: {
                    Label("Open Mixed Reality View", systemImage: "visionpro")
                }
                .buttonStyle(PrimaryActionButton())
            }
        }
    }

    @ViewBuilder
    private var topMixedRealityStatus: some View {
        if appModel.immersiveSpaceState == .open {
            Label("Mixed Reality View open", systemImage: "visionpro")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.58))
        } else if displayStage != .ready {
            mixedRealityControl
        }
    }

    private var compactCalibrationProgress: some View {
        HStack(spacing: 8) {
            calibrationProgressPill(title: "Rest", value: restProgressPercentageLabel, isComplete: isRestCaptureComplete)
            calibrationProgressPill(
                title: "Press",
                value: pressProgressPercentageLabel,
                isComplete: isPressCaptureComplete,
                isActive: appModel.isPipettePressed
            )
            calibrationProgressPill(title: "Tip", value: appModel.pipetteTipOffsetLabel, isComplete: appModel.isPipetteCalibrationComplete)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var tipAdjustmentControls: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                calibrationMetricChip(
                    title: "Current Offset",
                    value: appModel.pipetteTipOffsetLabel,
                    symbol: "move.3d"
                )

                calibrationMetricChip(
                    title: "Tip Confidence",
                    value: appModel.pipetteTipConfidenceLabel,
                    symbol: "dot.scope"
                )

                calibrationMetricChip(
                    title: appModel.isPipetteTipEstimateFrozen ? "Marker State" : "Alignment",
                    value: appModel.isPipetteTipEstimateFrozen ? "Frozen" : "Live",
                    symbol: appModel.isPipetteTipEstimateFrozen ? "snowflake" : "scope"
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 8) {
                Text(
                    appModel.isPipetteTipEstimateFrozen
                        ? "Move the physical pipette tip onto the frozen red dot, then save the tip position."
                        : "Freeze the red dot, move the pipette tip onto it, then save the tip position."
                )
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Reset clears the saved manual offset and lets you capture again from the live estimate.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
            )

            ViewThatFits(in: .horizontal) {
                tipAdjustmentActionButtons
                VStack(spacing: 12) {
                    tipAdjustmentActionButtons
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var tipAdjustmentActionButtons: some View {
        HStack(spacing: 12) {
            Button {
                appModel.toggleFrozenPipetteTipEstimate()
            } label: {
                Label(
                    appModel.isPipetteTipEstimateFrozen ? "Unfreeze Ball" : "Freeze Ball",
                    systemImage: appModel.isPipetteTipEstimateFrozen ? "snowflake.slash" : "snowflake"
                )
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .buttonStyle(SecondaryActionButton())
            .frame(width: 150, height: 54)
            .disabled(appModel.pipetteInputState.tipWorldPosition == nil)

            Button {
                appModel.savePipetteTipOffset()
            } label: {
                Label("Save Position", systemImage: "checkmark")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .buttonStyle(PrimaryActionButton())
            .frame(width: 172, height: 54)
            .disabled(appModel.pipetteInputState.tipWorldPosition == nil)

            Button {
                appModel.resetPipetteTipOffset()
            } label: {
                Label("Reset Offset", systemImage: "arrow.counterclockwise")
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .buttonStyle(SecondaryActionButton())
            .frame(width: 150, height: 54)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func calibrationMetricChip(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.7))

                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.09),
                    Color.white.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }

    private func calibrationProgressPill(
        title: String,
        value: String,
        isComplete: Bool,
        isActive: Bool = false
    ) -> some View {
        let indicatorColor = isComplete
            ? AppUIStyle.accentColor
            : (isActive ? AppUIStyle.feedbackColor(for: .success) : Color.white.opacity(0.38))

        let pillStrokeColor = isActive && !isComplete
            ? AppUIStyle.feedbackColor(for: .success).opacity(0.36)
            : Color.white.opacity(0.1)

        let pillBackgroundColor = isActive && !isComplete
            ? AppUIStyle.feedbackColor(for: .success).opacity(0.14)
            : Color.white.opacity(0.055)

        return HStack(spacing: 6) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.caption2.weight(.bold))
                .foregroundStyle(indicatorColor)

            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isActive && !isComplete ? AppUIStyle.primaryTextColor : Color.white.opacity(0.62))

            Text(isComplete ? "Ready" : value)
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(pillBackgroundColor, in: Capsule())
        .overlay(
            Capsule()
                .stroke(pillStrokeColor, lineWidth: 1)
        )
    }

    private var isRestCaptureComplete: Bool {
        let calibration = appModel.pipetteInputState.calibration
        return calibration.restSampleCount >= calibration.requiredSampleCount
    }

    private var isPressCaptureComplete: Bool {
        let calibration = appModel.pipetteInputState.calibration
        return calibration.pressedSampleCount >= calibration.requiredSampleCount
    }

    private var restProgressPercentageLabel: String {
        let calibration = appModel.pipetteInputState.calibration
        return progressPercentageLabel(
            sampleCount: calibration.restSampleCount,
            requiredSampleCount: calibration.requiredSampleCount
        )
    }

    private var pressProgressPercentageLabel: String {
        let calibration = appModel.pipetteInputState.calibration
        return progressPercentageLabel(
            sampleCount: calibration.pressedSampleCount,
            requiredSampleCount: calibration.requiredSampleCount
        )
    }

    private func progressPercentageLabel(sampleCount: Int, requiredSampleCount: Int) -> String {
        guard requiredSampleCount > 0 else { return "0%" }
        let progress = min(Double(sampleCount) / Double(requiredSampleCount), 1)
        return "\(Int((progress * 100).rounded()))%"
    }

    private func poseCaptureControls(
        primaryTitle: String,
        secondaryTitle: String,
        secondaryDisabled: Bool,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Button(primaryTitle, action: primaryAction)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: poseCalibrationActionWidth, height: poseCalibrationActionHeight)
                .buttonStyle(PrimaryActionButton())
                .disabled(!canCapture)
                .opacity(canCapture ? 1 : 0.45)

            Button(secondaryTitle, action: secondaryAction)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: poseCalibrationActionWidth, height: poseCalibrationActionHeight)
                .buttonStyle(SecondaryActionButton())
                .disabled(secondaryDisabled)
                .opacity(secondaryDisabled ? 0.45 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func handSelectionButton(_ hand: PipetteHandedness) -> some View {
        if appModel.selectedPipetteHand == hand {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
            .frame(width: calibrationActionWidth)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .buttonStyle(PrimaryActionButton())
        } else {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
            .frame(width: calibrationActionWidth)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .buttonStyle(SecondaryActionButton())
        }
    }

    @MainActor
    private func openMixedRealityIfNeeded() async {
        if appModel.immersiveSpaceState == .open {
            return
        }

        appModel.setImmersiveSpaceState(.inTransition)
        let result = await openImmersiveSpace(id: appModel.immersiveSpaceID)
        if case .opened = result {
            appModel.setImmersiveSpaceState(.open)
        } else {
            appModel.setImmersiveSpaceState(.closed)
        }
    }
}

private enum CalibrationStage: Equatable {
    case attachTip
    case chooseHand
    case restPose
    case pressedPose
    case tipAdjustment
    case ready
    case failed

    var stepNumber: Int {
        switch self {
        case .attachTip:
            return 1
        case .chooseHand:
            return 2
        case .restPose:
            return 3
        case .pressedPose:
            return 4
        case .tipAdjustment:
            return 5
        case .ready, .failed:
            return 5
        }
    }

    var title: String {
        switch self {
        case .attachTip:
            return "Attach pipette tip"
        case .chooseHand:
            return "Choose pipette hand"
        case .restPose:
            return "Capture rest position"
        case .pressedPose:
            return "Capture pressed position"
        case .tipAdjustment:
            return "Align pipette tip"
        case .ready:
            return "Pipette ready"
        case .failed:
            return "Calibration needs retry"
        }
    }

    var subtitle: String {
        switch self {
        case .attachTip:
            return "Start with a tip attached so the final alignment matches the real pipette setup."
        case .chooseHand:
            return "Set up the pipette input before starting the guided transfer."
        case .restPose:
            return "Hold the pipette normally without pressing the plunger."
        case .pressedPose:
            return "Press and hold the plunger so the app can learn the pressed state."
        case .tipAdjustment:
            return "Use the red marker to save the real tip offset for this grip."
        case .ready:
            return "Calibration is complete and ready for transfer validation."
        case .failed:
            return "Reset the setup and capture the pipette positions again."
        }
    }

    var instruction: String {
        switch self {
        case .attachTip:
            return "Attach a fresh tip to the pipette before you begin calibration."
        case .chooseHand:
            return "Select the hand holding the pipette. The mixed reality view must be open before capture."
        case .restPose:
            return "Keep your thumb relaxed on the pipette, then capture the resting pose."
        case .pressedPose:
            return "Press the pipette plunger and hold it steady while the samples are captured."
        case .tipAdjustment:
            return "Move the red dot until it sits on the physical pipette tip, then save the tip position."
        case .ready:
            return "The app can now detect pipette presses during the guided workflow."
        case .failed:
            return "The thumb movement was not clear enough. Try again with a stronger press."
        }
    }

    var icon: String {
        switch self {
        case .attachTip:
            return "pipette"
        case .chooseHand:
            return "hand.raised"
        case .restPose:
            return "hand.point.up.left"
        case .pressedPose:
            return "hand.tap"
        case .tipAdjustment:
            return "scope"
        case .ready:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        }
    }

    var illustrationAssetName: String? {
        switch self {
        case .restPose:
            return "RestPipetteCalibration"
        case .pressedPose:
            return "PressedPipetteCalibration"
        case .attachTip, .chooseHand, .tipAdjustment, .ready, .failed:
            return nil
        }
    }

    var illustrationAccessibilityLabel: String {
        switch self {
        case .restPose:
            return "Example grip with the thumb relaxed above the pipette plunger."
        case .pressedPose:
            return "Example grip with the thumb pressing the pipette plunger."
        case .attachTip, .chooseHand, .tipAdjustment, .ready, .failed:
            return ""
        }
    }

    var illustrationSize: CGSize {
        switch self {
        case .restPose, .pressedPose:
            return CGSize(width: 196, height: 158)
        case .attachTip, .chooseHand, .tipAdjustment, .ready, .failed:
            return .zero
        }
    }

    var isPoseCapture: Bool {
        switch self {
        case .restPose, .pressedPose:
            return true
        case .attachTip, .chooseHand, .tipAdjustment, .ready, .failed:
            return false
        }
    }
}

private struct CalibrationPoseIllustration: View {
    let assetName: String
    let accessibilityLabel: String
    let size: CGSize

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .padding(.horizontal, 8)
            .offset(x: -34)
            .accessibilityLabel(accessibilityLabel)
    }
}

private struct CalibrationStepRail: View {
    let currentStep: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { step in
                Capsule()
                    .fill(step <= currentStep ? AppUIStyle.accentColor : Color.white.opacity(0.14))
                    .frame(height: 7)
                    .overlay(alignment: .center) {
                        if step == currentStep {
                            Text("\(step)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(AppUIStyle.accentColor))
                                .offset(y: -18)
                        }
                    }
            }
        }
        .padding(.top, 12)
    }
}

#Preview {
    PipetteCalibrationSetupView()
        .environment(AppModel())
}
