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

    mutating func advance() -> Step? {
        guard stepsQueue.indices.contains(currentIndex),
              isAwaitingTipChange == false else {
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

    func summary() -> WorkflowSummary {
        WorkflowSummary(
            totalSteps: stepsQueue.count,
            aspirationWarnings: stepsQueue.filter(\.hasWarning).count,
            dispenseWarnings: stepsQueue.filter(\.dispenseWarning).count,
            completedAt: Date()
        )
    }
}
