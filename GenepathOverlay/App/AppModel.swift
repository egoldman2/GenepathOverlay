//
//  AppModel.swift
//  GenepathOverlay
//
//  Created by Ethan on 17/3/2026.
//

import Foundation
import SwiftUI

/// Maintains app-wide state and orchestrates the pipetting workflow.
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    private var lastHandledPipetteReleaseAt: Date?

    enum Screen {
        case home
        case loadProtocol
        case protocolHistory
        case protocolReview
        case operatorChecklist
        case pipetteCalibration
        case workflowSettings
        case workflow
    }

    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    let coordinateMapper: CoordinateMapper
    let csvParser: CSVParser
    let validationEngine: ValidationEngine
    let trackingManager: TrackingManager
    let overlayRenderer = OverlayRenderer()
    private let protocolHistoryStore = ProtocolHistoryStore()

    var uiState = UIStateManager()
    var sequenceEngine = SequenceEngine()
    var protocolHistory: [ProtocolHistoryEntry] = []
    var trackingSnapshot = TrackingSnapshot.idle
    var currentScreen: Screen = .home
    var pipetteCalibrationOpenedFromSettings = false
    var isShowingTestWellPlate = false {
        didSet {
            trackingManager.setTestPlateSimulationEnabled(isShowingTestWellPlate)
            syncTrackingSnapshot()
        }
    }

    init() {
        let mapper = CoordinateMapper()
        coordinateMapper = mapper
        csvParser = CSVParser(coordinateMapper: mapper)
        validationEngine = ValidationEngine()
        trackingManager = TrackingManager(coordinateMapper: mapper)
        protocolHistory = protocolHistoryStore.load()
        trackingManager.onStateChange = { [weak self] in
            self?.syncTrackingSnapshot()
        }
        uiState.prepareForLaunch()
        if isRunningTests == false {
            trackingManager.startTracking()
        }
        trackingSnapshot = trackingManager.snapshot
    }

    var currentStep: Step? {
        sequenceEngine.currentStep
    }

    var currentPhase: WorkflowPhase {
        sequenceEngine.currentPhase
    }

    var overlayHighlightedCoordinates: [PlateID: Coordinate] {
        guard let currentStep else { return [:] }
        let targetCoordinate = currentStep.coordinate(for: currentPhase)
        return [targetCoordinate.plate: targetCoordinate]
    }

    var progressLabel: String {
        guard let currentStep else {
            return sequenceEngine.totalSteps == 0 ? "No CSV loaded" : "Workflow complete"
        }

        return "Step \(currentStep.sequenceNumber) of \(sequenceEngine.totalSteps)"
    }

    var currentInstructionTitle: String {
        guard let currentStep else {
            return "Import a CSV to begin"
        }

        let coordinate = currentStep.coordinate(for: currentPhase)
        return "\(currentPhase.title): \(coordinate.plate.title) \(coordinate.well)"
    }

    var currentInstructionDetail: String {
        guard let currentStep else {
            return "Select a transfer CSV to build the workflow queue."
        }

        switch currentPhase {
        case .aspiration:
            return "Aspirate \(formattedVolume(currentStep.volume)) from source \(currentStep.source.well), then validate the detected pipette position."
        case .dispense:
            return "Dispense \(formattedVolume(currentStep.volume)) into destination \(currentStep.destination.well), then validate before continuing."
        }
    }

    var trackingMessage: String {
        trackingSnapshot.status.message
    }

    var pipetteInputState: PipettePressState {
        trackingSnapshot.pipetteInput
    }

    var pipetteTrackingMessage: String {
        pipetteInputState.trackingStatus.message
    }

    var pipetteCalibrationMessage: String {
        pipetteInputState.calibration.summary
    }

    var selectedPipetteHand: PipetteHandedness? {
        pipetteInputState.selectedHand
    }

    var selectedPipetteHandLabel: String {
        selectedPipetteHand?.title ?? "Not selected"
    }

    var isPipetteCalibrationComplete: Bool {
        pipetteInputState.calibration.isComplete
    }

    var isPipettePressed: Bool {
        pipetteInputState.isPressed
    }

    var pipettePressLabel: String {
        pipetteInputState.isPressed ? "Pressed" : "Idle"
    }

    var pipetteGripConfidenceLabel: String {
        "\(Int((pipetteInputState.gripConfidence * 100).rounded()))%"
    }

    var pipetteCalibrationProgressLabel: String {
        let calibration = pipetteInputState.calibration
        return "\(calibration.restSampleCount)/\(calibration.requiredSampleCount) rest, \(calibration.pressedSampleCount)/\(calibration.requiredSampleCount) pressed"
    }

    var lastPipetteEventLabel: String {
        if let ended = pipetteInputState.pressEndedAt {
            return "Released \(ended.formatted(date: .omitted, time: .standard))"
        }

        if let began = pipetteInputState.pressBeganAt {
            return "Pressed \(began.formatted(date: .omitted, time: .standard))"
        }

        return "No thumb presses recorded yet"
    }

    var bundledReferenceObjectsLabel: String {
        let names = trackingManager.bundledReferenceObjectNames
        guard !names.isEmpty else {
            return "No bundled reference objects"
        }
        return names.joined(separator: ", ")
    }

    var trackedPlatesLabel: String {
        let trackedPlates = trackingSnapshot.plateAnchors.values
            .filter { $0.confidence > 0.95 }
            .map { anchor in
                anchor.isSimulated ? "\(anchor.plate.title) (Simulated)" : anchor.plate.title
            }
            .sorted()

        guard !trackedPlates.isEmpty else {
            return "No live plate anchors yet"
        }

        return trackedPlates.joined(separator: ", ")
    }

    var isPreviewTracking: Bool {
        if case .preview = trackingSnapshot.status {
            return true
        }
        return false
    }

    var testWellPlateModelName: String {
        TestWellPlateAssetLocator.displayName() ?? "No bundled USDZ found"
    }

    var isTestWellPlateModelAvailable: Bool {
        TestWellPlateAssetLocator.locate() != nil
    }

    var canConfirmValidation: Bool {
        if case .some(.correct) = uiState.validationResult {
            return true
        }
        return false
    }

    var canContinueAnyway: Bool {
        if case .some(.incorrect) = uiState.validationResult {
            return true
        }
        return false
    }

    var manualConfirmButtonTitle: String {
        "Confirm Manually"
    }

    var previewSteps: [Step] {
        Array(sequenceEngine.allSteps.prefix(6))
    }

    func prepareForLaunch() {
        if sequenceEngine.totalSteps == 0 {
            uiState.prepareForLaunch()
        }

        if trackingSnapshot.plateAnchors.isEmpty {
            guard isRunningTests == false else { return }
            trackingManager.startTracking()
            syncTrackingSnapshot()
        }
    }

    func showImporter() {
        uiState.isShowingImporter = true
    }

    func startSession() {
        trackingManager.resetPipetteCalibration(keepSelectedHand: false)
        syncTrackingSnapshot()
        pipetteCalibrationOpenedFromSettings = false
        currentScreen = .loadProtocol
    }

    func goHome() {
        currentScreen = .home
    }

    func goToLoadProtocol() {
        currentScreen = .loadProtocol
    }

    func goToProtocolHistory() {
        currentScreen = .protocolHistory
    }

    func goToProtocolReview() {
        guard sequenceEngine.totalSteps > 0 else { return }
        currentScreen = .protocolReview
    }

    func goToOperatorChecklist() {
        guard sequenceEngine.totalSteps > 0 else { return }
        currentScreen = .operatorChecklist
    }

    func goToPipetteCalibrationFromFlow() {
        guard sequenceEngine.totalSteps > 0 else { return }
        pipetteCalibrationOpenedFromSettings = false
        currentScreen = .pipetteCalibration
    }

    func goToPipetteCalibrationFromSettings() {
        guard sequenceEngine.totalSteps > 0 else { return }
        pipetteCalibrationOpenedFromSettings = true
        currentScreen = .pipetteCalibration
    }

    func goToWorkflowSettings() {
        currentScreen = .workflowSettings
    }

    func leavePipetteCalibration() {
        currentScreen = pipetteCalibrationOpenedFromSettings ? .workflowSettings : .operatorChecklist
    }

    func beginWorkflow() {
        guard sequenceEngine.totalSteps > 0 else { return }
        lastHandledPipetteReleaseAt = pipetteInputState.pressEndedAt
        currentScreen = .workflow
    }

    func importCSV(from url: URL) async {
        uiState.beginCSVLoad()

        do {
            let parser = csvParser
            let steps = try await Task.detached(priority: .userInitiated) {
                try parser.parse(fileAt: url)
            }.value

            uiState.importedFileName = url.lastPathComponent
            uiState.beginMapping()
            sequenceEngine.load(steps: steps)
            saveProtocolHistory(fileName: url.lastPathComponent, steps: steps)
            trackingManager.startTracking()
            syncTrackingSnapshot()
            updateWorkflowPresentation()
            currentScreen = .protocolReview
        } catch {
            sequenceEngine.reset()
            uiState.setError(error.localizedDescription)
            currentScreen = .loadProtocol
        }
    }

    func loadProtocolHistory(_ entry: ProtocolHistoryEntry) {
        do {
            let steps = try entry.makeSteps(using: coordinateMapper)
            uiState.beginCSVLoad()
            uiState.importedFileName = entry.fileName
            uiState.beginMapping()
            sequenceEngine.load(steps: steps)
            saveProtocolHistory(fileName: entry.fileName, steps: steps)
            trackingManager.startTracking()
            syncTrackingSnapshot()
            updateWorkflowPresentation()
            currentScreen = .protocolReview
        } catch {
            uiState.setError("Could not reopen this saved protocol.")
            currentScreen = .loadProtocol
        }
    }

    @discardableResult
    func validateCurrentPhase(simulatingMismatch: Bool = false) -> ValidationResult? {
        guard let currentStep else { return nil }

        uiState.setValidating(currentPhase)

        if isPreviewTracking {
            trackingManager.simulateDetection(
                for: currentStep.coordinate(for: currentPhase),
                mismatch: simulatingMismatch
            )
        }

        syncTrackingSnapshot()

        let result = validationEngine.validate(
            detectedPose: trackingSnapshot.detectedToolPose,
            expectedCoordinate: currentStep.coordinate(for: currentPhase),
            trackingStatus: trackingSnapshot.status
        )
        let feedback = validationEngine.feedback(
            for: result,
            phase: currentPhase,
            step: currentStep
        )

        uiState.setValidationResult(result, feedback: feedback)
        return result
    }

    func retryValidation() {
        trackingManager.clearDetection()
        syncTrackingSnapshot()
        updateWorkflowPresentation()
    }

    func confirmCurrentPhaseManually() {
        guard currentStep != nil else { return }

        sequenceEngine.markWarning(for: currentPhase)
        trackingManager.clearDetection()
        _ = sequenceEngine.advance()
        syncTrackingSnapshot()
        updateWorkflowPresentation()
    }

    func confirmValidationAndAdvance() {
        guard canConfirmValidation else { return }

        trackingManager.clearDetection()
        _ = sequenceEngine.advance()
        syncTrackingSnapshot()
        updateWorkflowPresentation()
    }

    func continueAnyway() {
        guard canContinueAnyway else { return }

        sequenceEngine.markWarning(for: currentPhase)
        trackingManager.clearDetection()
        _ = sequenceEngine.advance()
        syncTrackingSnapshot()
        updateWorkflowPresentation()
    }

    func exportLog() {
        guard uiState.summary != nil else { return }
        uiState.isShowingExporter = true
    }

    func setImmersiveSpaceState(_ state: ImmersiveSpaceState) {
        immersiveSpaceState = state
        trackingManager.setImmersiveSpaceActive(state == .open)
        syncTrackingSnapshot()
    }

    func setPipetteHandedness(_ handedness: PipetteHandedness?) {
        trackingManager.setPipetteHandedness(handedness)
        syncTrackingSnapshot()
    }

    func startRestCalibrationCapture() {
        trackingManager.startRestCalibrationCapture()
        syncTrackingSnapshot()
    }

    func startPressedCalibrationCapture() {
        trackingManager.startPressedCalibrationCapture()
        syncTrackingSnapshot()
    }

    func resetPipetteCalibration() {
        trackingManager.resetPipetteCalibration()
        syncTrackingSnapshot()
    }

    private func updateWorkflowPresentation() {
        if let currentStep {
            uiState.setRunning(step: currentStep, phase: currentPhase)
            return
        }

        guard sequenceEngine.totalSteps > 0 else {
            uiState.prepareForLaunch()
            return
        }

        let summary = sequenceEngine.summary()
        uiState.complete(summary: summary, logText: buildSessionLog(summary: summary))
    }

    private func saveProtocolHistory(fileName: String, steps: [Step]) {
        protocolHistory = protocolHistoryStore.inserting(fileName: fileName, steps: steps, into: protocolHistory)
        protocolHistoryStore.save(protocolHistory)
    }

    private func syncTrackingSnapshot() {
        trackingSnapshot = trackingManager.snapshot
        handleCompletedPipettePressIfNeeded()
    }

    private func handleCompletedPipettePressIfNeeded() {
        guard let releaseAt = trackingSnapshot.pipetteInput.pressEndedAt,
              releaseAt != lastHandledPipetteReleaseAt else {
            return
        }

        lastHandledPipetteReleaseAt = releaseAt

        guard currentScreen == .workflow,
              currentStep != nil,
              uiState.summary == nil else {
            return
        }

        handleAutoWorkflowPipettePress()
    }

    private func handleAutoWorkflowPipettePress() {
        guard pipetteInputState.calibration.isComplete else {
            let result = ValidationResult.blocked("Pipette press detected, but calibration is not complete. Use manual confirm if needed.")
            let feedback = ValidationFeedback(
                tone: .warning,
                title: "Pipette Not Calibrated",
                detail: "Calibrate the pipette button, or use manual confirm if you need to continue."
            )
            uiState.setValidationResult(result, feedback: feedback)
            return
        }

        guard case .ready = pipetteInputState.trackingStatus else {
            let result = ValidationResult.blocked("Pipette press detected, but hand tracking is not ready. Use manual confirm if needed.")
            let feedback = ValidationFeedback(
                tone: .warning,
                title: "Pipette Tracking Not Ready",
                detail: pipetteTrackingMessage
            )
            uiState.setValidationResult(result, feedback: feedback)
            return
        }

        guard let result = validateCurrentPhase() else { return }

        if case .correct = result {
            confirmValidationAndAdvance()
        }
    }

    private func buildSessionLog(summary: WorkflowSummary) -> String {
        var lines: [String] = [
            "GenepathOverlay Session Log",
            "Completed: \(summary.completedAt.formatted(date: .abbreviated, time: .shortened))",
            "Total steps: \(summary.totalSteps)",
            "Aspiration warnings: \(summary.aspirationWarnings)",
            "Dispense warnings: \(summary.dispenseWarnings)",
            "Pipette hand: \(selectedPipetteHandLabel)",
            "Pipette calibration: \(pipetteInputState.calibration.isComplete ? "Complete" : "Incomplete")",
            "Pipette press count: \(pipetteInputState.pressCount)",
            ""
        ]

        for step in sequenceEngine.allSteps {
            lines.append(
                "Step \(step.sequenceNumber),source=\(step.source.well),destination=\(step.destination.well),volume=\(formattedVolume(step.volume)),aspirationWarning=\(step.hasWarning),dispenseWarning=\(step.dispenseWarning)"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func formattedVolume(_ volume: Double) -> String {
        if volume.rounded() == volume {
            return "\(Int(volume)) uL"
        }

        return String(format: "%.1f uL", volume)
    }
}
