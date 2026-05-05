import SwiftUI

struct PipetteCalibrationSetupView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    private let settingsPresentationOverride: Bool?
    private let onBack: (() -> Void)?

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

    private var stage: CalibrationStage {
        if appModel.isPipetteCalibrationComplete {
            return .ready
        }

        if appModel.selectedPipetteHand == nil {
            return .chooseHand
        }

        switch appModel.pipetteInputState.calibration.step {
        case .readyForPress, .collectingPress:
            return .pressedPose
        case .failed:
            return .failed
        default:
            return .restPose
        }
    }

    var body: some View {
        ScrollView {
            AppSetupCard {
                header

                VStack(alignment: .leading, spacing: 10) {
                    Text(isSettingsMode ? "Pipette Calibration" : "Pipette calibration")
                        .font(.system(size: 34, weight: .bold, design: .rounded))

                    AppSubtitleText(stageSubtitle)
                }

                CalibrationStepRail(currentStep: stage.stepNumber)

                stageCard

                footerActions
            }
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

            if isSettingsMode == false {
                SetupProgressIndicator(currentStep: 4, totalSteps: 4)
            }
        }
    }

    @ViewBuilder
    private var stageCard: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text(stage.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppUIStyle.primaryTextColor)

                Text(stage.instruction)
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
                .overlay(Color.white.opacity(0.12))

            HStack(alignment: .center, spacing: 18) {
                stageControls

                Spacer(minLength: 8)

                calibrationProgressGroup
            }
        }
        .padding(24)
        .background(CalibrationGlassBackground(cornerRadius: 24))
    }

    @ViewBuilder
    private var stageControls: some View {
        switch stage {
        case .chooseHand:
            HStack(spacing: 12) {
                handSelectionButton(.left)
                handSelectionButton(.right)
            }

        case .restPose:
            HStack(spacing: 12) {
                captureOrOpenButton(title: "Capture Rest Position") {
                    appModel.startRestCalibrationCapture()
                }

                Button("Change Hand") {
                    appModel.setPipetteHandedness(nil)
                }
                .buttonStyle(SecondaryActionButton())
            }

        case .pressedPose:
            HStack(spacing: 12) {
                captureOrOpenButton(title: "Capture Pressed Position") {
                    appModel.startPressedCalibrationCapture()
                }

                Button("Recapture Rest") {
                    appModel.startRestCalibrationCapture()
                }
                .buttonStyle(SecondaryActionButton())
                .disabled(!canCapture)
                .opacity(canCapture ? 1 : 0.45)
            }

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
                .buttonStyle(PrimaryActionButton())

                Button("Recalibrate") {
                    appModel.resetPipetteCalibration()
                }
                .buttonStyle(SecondaryActionButton())
            }

        case .failed:
            HStack(spacing: 12) {
                Button("Try Again") {
                    appModel.resetPipetteCalibration()
                }
                .buttonStyle(PrimaryActionButton())

                Button("Change Hand") {
                    appModel.setPipetteHandedness(nil)
                }
                .buttonStyle(SecondaryActionButton())
            }
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

    private var calibrationProgressGroup: some View {
        HStack(spacing: 16) {
            CalibrationProgressBadge(
                title: "Rest",
                value: restProgressPercentageLabel,
                isComplete: isRestCaptureComplete,
                detail: restProgressCountLabel
            )
            CalibrationProgressBadge(
                title: "Press",
                value: pressProgressPercentageLabel,
                isComplete: isPressCaptureComplete,
                detail: pressProgressCountLabel
            )
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        HStack {
            if appModel.immersiveSpaceState == .open {
                Label("Mixed Reality View open", systemImage: "visionpro")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.58))
            } else if stage != .ready {
                mixedRealityControl
            }

            Spacer(minLength: 0)

            footerSecondaryAction
        }
    }

    @ViewBuilder
    private var footerSecondaryAction: some View {
        if stage == .ready {
            Button("Recalibrate") {
                appModel.resetPipetteCalibration()
            }
            .buttonStyle(SecondaryActionButton())
        } else if isSettingsMode == false {
            Button("Skip Calibration") {
                appModel.beginWorkflow()
            }
            .buttonStyle(SecondaryActionButton())
        }
    }

    private var stageSubtitle: String {
        if let selectedHand = appModel.selectedPipetteHand {
            return "Calibrating for \(selectedHand.title.lowercased()) hand."
        }

        return stage.subtitle
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

    private var restProgressCountLabel: String {
        let calibration = appModel.pipetteInputState.calibration
        return "\(calibration.restSampleCount) of \(calibration.requiredSampleCount) rest samples captured"
    }

    private var pressProgressCountLabel: String {
        let calibration = appModel.pipetteInputState.calibration
        return "\(calibration.pressedSampleCount) of \(calibration.requiredSampleCount) pressed samples captured"
    }

    private func progressPercentageLabel(sampleCount: Int, requiredSampleCount: Int) -> String {
        guard requiredSampleCount > 0 else { return "0%" }
        let progress = min(Double(sampleCount) / Double(requiredSampleCount), 1)
        return "\(Int((progress * 100).rounded()))%"
    }

    @ViewBuilder
    private func captureOrOpenButton(title: String, action: @escaping () -> Void) -> some View {
        if appModel.immersiveSpaceState == .open {
            Button(title, action: action)
                .buttonStyle(PrimaryActionButton())
                .disabled(!canCapture)
                .opacity(canCapture ? 1 : 0.45)
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

    @ViewBuilder
    private func handSelectionButton(_ hand: PipetteHandedness) -> some View {
        if appModel.selectedPipetteHand == hand {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
            .buttonStyle(PrimaryActionButton())
        } else {
            Button(hand.title) {
                appModel.setPipetteHandedness(hand)
            }
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
    case chooseHand
    case restPose
    case pressedPose
    case ready
    case failed

    var stepNumber: Int {
        switch self {
        case .chooseHand:
            return 1
        case .restPose:
            return 2
        case .pressedPose:
            return 3
        case .ready, .failed:
            return 4
        }
    }

    var title: String {
        switch self {
        case .chooseHand:
            return "Choose pipette hand"
        case .restPose:
            return "Capture rest position"
        case .pressedPose:
            return "Capture pressed position"
        case .ready:
            return "Pipette ready"
        case .failed:
            return "Calibration needs retry"
        }
    }

    var subtitle: String {
        switch self {
        case .chooseHand:
            return "Set up the pipette input before starting the guided transfer."
        case .restPose:
            return "Hold the pipette normally without pressing the plunger."
        case .pressedPose:
            return "Press and hold the plunger so the app can learn the pressed state."
        case .ready:
            return "Calibration is complete and ready for transfer validation."
        case .failed:
            return "Reset the setup and capture the pipette positions again."
        }
    }

    var instruction: String {
        switch self {
        case .chooseHand:
            return "Select the hand holding the pipette. The mixed reality view must be open before capture."
        case .restPose:
            return "Keep your thumb relaxed on the pipette, then capture the resting pose."
        case .pressedPose:
            return "Press the pipette plunger and hold it steady while the samples are captured."
        case .ready:
            return "The app can now detect pipette presses during the guided workflow."
        case .failed:
            return "The thumb movement was not clear enough. Try again with a stronger press."
        }
    }

    var icon: String {
        switch self {
        case .chooseHand:
            return "hand.raised"
        case .restPose:
            return "hand.point.up.left"
        case .pressedPose:
            return "hand.tap"
        case .ready:
            return "checkmark"
        case .failed:
            return "exclamationmark"
        }
    }
}

private struct CalibrationStepRail: View {
    let currentStep: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(1...4, id: \.self) { step in
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

private struct CalibrationProgressBadge: View {
    let title: String
    let value: String
    let isComplete: Bool
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.16), lineWidth: 3)
                    .frame(width: 28, height: 28)

                if isComplete {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppUIStyle.accentColor)
                } else {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(AppUIStyle.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                }
            }

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.64))

            Text(isComplete ? "Ready" : value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppUIStyle.primaryTextColor)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Capsule().fill(Color.white.opacity(0.07)))
        .background(Capsule().fill(.regularMaterial))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .help(detail)
    }

    private var progress: CGFloat {
        let number = value.replacingOccurrences(of: "%", with: "")
        guard let percentage = Double(number) else { return 0 }
        return CGFloat(min(max(percentage / 100, 0), 1))
    }
}

private struct CalibrationGlassBackground: View {
    var cornerRadius: CGFloat = 20

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

#Preview {
    PipetteCalibrationSetupView()
        .environment(AppModel())
}
