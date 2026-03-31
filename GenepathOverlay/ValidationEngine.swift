import Foundation
import simd

struct ValidationEngine {
    let wellTolerance: Float
    let minimumConfidence: Float

    init(wellTolerance: Float = 0.009, minimumConfidence: Float = 0.55) {
        self.wellTolerance = wellTolerance
        self.minimumConfidence = minimumConfidence
    }

    func validate(
        detectedPose: DetectedToolPose?,
        expectedCoordinate: Coordinate,
        trackingStatus: TrackingStatus
    ) -> ValidationResult {
        switch trackingStatus {
        case .idle, .preparing, .searching:
            return .blocked("Tracking is not ready yet.")
        case .paused(let message), .lowConfidence(let message), .unavailable(let message):
            return .blocked(message)
        case .preview, .tracking:
            break
        }

        guard let detectedPose else {
            return .blocked("No pipette position has been detected yet.")
        }

        guard detectedPose.confidence >= minimumConfidence else {
            return .blocked("Tracking confidence is too low to validate the current target.")
        }

        guard detectedPose.plate == expectedCoordinate.plate else {
            return .incorrect
        }

        let distance = simd_distance(detectedPose.position, expectedCoordinate.normalizedPosition)
        return distance <= wellTolerance ? .correct : .incorrect
    }

    func feedback(
        for result: ValidationResult,
        phase: WorkflowPhase,
        step: Step
    ) -> ValidationFeedback {
        switch result {
        case .correct:
            return ValidationFeedback(
                tone: .success,
                title: "Correct Position",
                detail: "\(phase.title) target \(step.coordinate(for: phase).well) matched. \(phase.confirmationTitle)"
            )
        case .incorrect:
            return ValidationFeedback(
                tone: .failure,
                title: "Wrong Target Detected",
                detail: "Expected \(step.coordinate(for: phase).well). Retry, or continue and record a warning."
            )
        case .blocked(let reason):
            return ValidationFeedback(
                tone: .warning,
                title: "Validation Blocked",
                detail: reason
            )
        }
    }
}
