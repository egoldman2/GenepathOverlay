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

    var uiState = UIStateManager()
    var sequenceEngine = SequenceEngine()
    var trackingSnapshot = TrackingSnapshot.idle
    var isShowingWelcomeScreen = true
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
        trackingManager.onStateChange = { [weak self] in
            self?.syncTrackingSnapshot()
        }
        uiState.prepareForLaunch()
        trackingManager.startTracking()
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
        return [.source: currentStep.source]
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

    var previewSteps: [Step] {
        Array(sequenceEngine.allSteps.prefix(6))
    }

    func prepareForLaunch() {
        if sequenceEngine.totalSteps == 0 {
            uiState.prepareForLaunch()
        }

        if trackingSnapshot.plateAnchors.isEmpty {
            trackingManager.startTracking()
            syncTrackingSnapshot()
        }
    }

    func showImporter() {
        uiState.isShowingImporter = true
    }

    func dismissWelcomeScreen() {
        isShowingWelcomeScreen = false
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
            trackingManager.startTracking()
            syncTrackingSnapshot()
            updateWorkflowPresentation()
        } catch {
            sequenceEngine.reset()
            uiState.setError(error.localizedDescription)
        }
    }

    func validateCurrentPhase(simulatingMismatch: Bool = false) {
        guard let currentStep else { return }

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
    }

    func retryValidation() {
        trackingManager.clearDetection()
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

    private func syncTrackingSnapshot() {
        trackingSnapshot = trackingManager.snapshot
    }

    private func buildSessionLog(summary: WorkflowSummary) -> String {
        var lines: [String] = [
            "GenepathOverlay Session Log",
            "Completed: \(summary.completedAt.formatted(date: .abbreviated, time: .shortened))",
            "Total steps: \(summary.totalSteps)",
            "Aspiration warnings: \(summary.aspirationWarnings)",
            "Dispense warnings: \(summary.dispenseWarnings)",
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
