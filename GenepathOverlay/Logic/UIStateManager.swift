import Foundation

struct UIStateManager {
    var appState: AppState = .idle
    var isShowingImporter = false
    var isShowingExporter = false
    var importedFileName: String?
    var errorMessage: String?
    var validationResult: ValidationResult?
    var validationFeedback: ValidationFeedback = .idle
    var summary: WorkflowSummary?
    var logDocument = SessionLogDocument()

    mutating func prepareForLaunch() {
        appState = .idle
        isShowingImporter = false
        isShowingExporter = false
        importedFileName = nil
        errorMessage = nil
        validationResult = nil
        validationFeedback = .idle
        summary = nil
    }

    mutating func beginCSVLoad() {
        appState = .loadingCSV
        errorMessage = nil
        validationResult = nil
        validationFeedback = ValidationFeedback(
            tone: .neutral,
            title: "Loading CSV",
            detail: "Parsing transfer rows and preparing the workflow."
        )
        summary = nil
    }

    mutating func beginMapping() {
        appState = .mapping
        validationFeedback = ValidationFeedback(
            tone: .neutral,
            title: "Mapping Coordinates",
            detail: "Converting source and destination wells into spatial positions."
        )
    }

    mutating func setAwaitingVolumeVerification(step: Step, state: VolumeVerificationState) {
        appState = .verifyingVolume(step, state)
        validationResult = nil
        validationFeedback = ValidationFeedback(
            tone: .neutral,
            title: "Verify Dispense Amount",
            detail: "Set the pipette volume before starting Step \(step.sequenceNumber)."
        )
    }

    mutating func setRunning(step: Step, phase: WorkflowPhase) {
        appState = .runningStep(step)
        validationResult = nil
        validationFeedback = ValidationFeedback(
            tone: .neutral,
            title: "\(phase.title) Ready",
            detail: "Press and release the pipette at target \(step.coordinate(for: phase).well), or confirm manually if detection misses it."
        )
    }

    mutating func setAwaitingTipChange(before step: Step, state: TipChangeState) {
        appState = .awaitingTipChange(step, state)
        validationResult = nil
        validationFeedback = ValidationFeedback(tone: .warning, title: state.title, detail: state.detail(for: step))
    }

    mutating func setValidating(_ phase: WorkflowPhase) {
        switch phase {
        case .aspiration:
            appState = .validatingAspiration
        case .dispense:
            appState = .validatingDispense
        }
    }

    mutating func setValidationResult(_ result: ValidationResult, feedback: ValidationFeedback) {
        validationResult = result
        validationFeedback = feedback
    }

    mutating func complete(summary: WorkflowSummary, logText: String) {
        appState = .completed
        validationResult = nil
        validationFeedback = ValidationFeedback(
            tone: .success,
            title: "Workflow Complete",
            detail: "All transfer steps have been processed."
        )
        self.summary = summary
        logDocument = SessionLogDocument(text: logText)
    }

    mutating func setError(_ message: String) {
        errorMessage = message
        validationResult = nil
        validationFeedback = ValidationFeedback(
            tone: .failure,
            title: "Import Failed",
            detail: message
        )
        appState = .idle
    }
}

private extension TipChangeState {
    func detail(for step: Step) -> String {
        switch self {
        case .awaitingEjection:
            return "Press and release the pipette eject button to remove the used tip before aspirating from source \(step.source.well). If detection misses it, use manual eject to continue."
        case .awaitingReplacement:
            return "Attach a fresh tip, then confirm before aspirating from source \(step.source.well)."
        }
    }
}
