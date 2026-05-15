import Foundation

struct SequenceEngine {
    private(set) var stepsQueue: [Step] = []
    private(set) var currentIndex = 0
    private(set) var currentPhase: WorkflowPhase = .aspiration
    private(set) var tipChangeState: TipChangeState?

    var isAwaitingTipChange: Bool {
        tipChangeState != nil
    }

    var currentStep: Step? {
        guard stepsQueue.indices.contains(currentIndex) else { return nil }
        return stepsQueue[currentIndex]
    }

    var currentVolumeVerificationState: VolumeVerificationState? {
        currentStep.map(VolumeVerificationState.init(step:))
    }

    var requiresVolumeVerification: Bool {
        guard let currentStep,
              currentPhase == .aspiration,
              isAwaitingTipChange == false else {
            return false
        }

        return currentStep.isVolumeConfirmed == false
    }

    var totalSteps: Int {
        stepsQueue.count
    }

    var allSteps: [Step] {
        stepsQueue
    }

    mutating func load(steps: [Step]) {
        stepsQueue = steps
        currentIndex = 0
        currentPhase = .aspiration
        tipChangeState = nil
    }

    mutating func reset() {
        stepsQueue = []
        currentIndex = 0
        currentPhase = .aspiration
        tipChangeState = nil
    }

    mutating func restartCurrentRun() {
        for index in stepsQueue.indices {
            stepsQueue[index].volumeConfirmedAt = nil
            stepsQueue[index].volumeConfirmedValue = nil
            stepsQueue[index].hasWarning = false
            stepsQueue[index].dispenseWarning = false
        }
        currentIndex = 0
        currentPhase = .aspiration
        tipChangeState = nil
    }

    mutating func markWarning(for phase: WorkflowPhase) {
        guard stepsQueue.indices.contains(currentIndex) else { return }

        switch phase {
        case .aspiration:
            stepsQueue[currentIndex].hasWarning = true
        case .dispense:
            stepsQueue[currentIndex].dispenseWarning = true
        }
    }

    mutating func confirmVolumeForCurrentStep(value: Double? = nil, at confirmedAt: Date = Date()) -> Bool {
        guard stepsQueue.indices.contains(currentIndex),
              currentPhase == .aspiration,
              isAwaitingTipChange == false else {
            return false
        }

        stepsQueue[currentIndex].volumeConfirmedValue = value ?? stepsQueue[currentIndex].volume
        stepsQueue[currentIndex].volumeConfirmedAt = confirmedAt
        return true
    }

    mutating func advance() -> Step? {
        guard stepsQueue.indices.contains(currentIndex),
              isAwaitingTipChange == false,
              requiresVolumeVerification == false else {
            return currentStep
        }

        if currentPhase == .aspiration {
            currentPhase = .dispense
            return currentStep
        }

        currentPhase = .aspiration
        currentIndex += 1
        tipChangeState = stepsQueue.indices.contains(currentIndex) ? .awaitingEjection : nil
        return currentStep
    }

    mutating func confirmTipEjection() {
        guard tipChangeState == .awaitingEjection else { return }
        tipChangeState = .awaitingReplacement
    }

    mutating func confirmTipReplacement() {
        guard tipChangeState == .awaitingReplacement else { return }
        tipChangeState = nil
    }

    mutating func skipToCompletion() {
        guard stepsQueue.isEmpty == false else { return }
        currentIndex = stepsQueue.count
        currentPhase = .aspiration
        tipChangeState = nil
    }

    func summary() -> WorkflowSummary {
        WorkflowSummary(
            totalSteps: stepsQueue.count,
            volumeConfirmations: stepsQueue.filter(\.isVolumeConfirmed).count,
            aspirationWarnings: stepsQueue.filter(\.hasWarning).count,
            dispenseWarnings: stepsQueue.filter(\.dispenseWarning).count,
            completedAt: Date()
        )
    }
}
