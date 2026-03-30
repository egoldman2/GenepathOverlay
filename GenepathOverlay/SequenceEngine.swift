import Foundation

struct SequenceEngine {
    private(set) var stepsQueue: [Step] = []
    private(set) var currentIndex = 0
    private(set) var currentPhase: WorkflowPhase = .aspiration

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
    }

    mutating func reset() {
        stepsQueue = []
        currentIndex = 0
        currentPhase = .aspiration
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
        guard stepsQueue.indices.contains(currentIndex) else { return nil }

        if currentPhase == .aspiration {
            currentPhase = .dispense
            return currentStep
        }

        currentPhase = .aspiration
        currentIndex += 1
        return currentStep
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
