import Foundation
import simd

enum PlateID: String, CaseIterable, Identifiable, Sendable {
    case source
    case destination

    var id: String { rawValue }

    var title: String {
        switch self {
        case .source:
            return "Source"
        case .destination:
            return "Destination"
        }
    }
}

struct Coordinate: Identifiable, Sendable, Equatable {
    let plate: PlateID
    let well: String
    let row: Int
    let column: Int
    let normalizedPosition: SIMD3<Float>

    var id: String { "\(plate.rawValue)-\(well)" }
}

struct Step: Identifiable, Sendable, Equatable {
    let id: UUID
    let sequenceNumber: Int
    let source: Coordinate
    let destination: Coordinate
    let volume: Double
    var hasWarning: Bool
    var dispenseWarning: Bool

    init(
        sequenceNumber: Int,
        source: Coordinate,
        destination: Coordinate,
        volume: Double,
        hasWarning: Bool = false,
        dispenseWarning: Bool = false
    ) {
        self.id = UUID()
        self.sequenceNumber = sequenceNumber
        self.source = source
        self.destination = destination
        self.volume = volume
        self.hasWarning = hasWarning
        self.dispenseWarning = dispenseWarning
    }

    func coordinate(for phase: WorkflowPhase) -> Coordinate {
        switch phase {
        case .aspiration:
            return source
        case .dispense:
            return destination
        }
    }
}

enum WorkflowPhase: String, Sendable, Equatable {
    case aspiration
    case dispense

    var title: String {
        switch self {
        case .aspiration:
            return "Aspiration"
        case .dispense:
            return "Dispense"
        }
    }

    var actionTitle: String {
        switch self {
        case .aspiration:
            return "Validate Aspiration"
        case .dispense:
            return "Validate Dispense"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .aspiration:
            return "Confirm & Move To Dispense"
        case .dispense:
            return "Confirm & Continue"
        }
    }
}

enum ValidationResult: Sendable {
    case correct
    case incorrect
    case blocked(String)
}

enum ValidationTone: Sendable {
    case neutral
    case success
    case failure
    case warning
}

struct ValidationFeedback: Sendable {
    let tone: ValidationTone
    let title: String
    let detail: String

    static let idle = ValidationFeedback(
        tone: .neutral,
        title: "Awaiting Validation",
        detail: "Import a CSV to begin the guided pipetting workflow."
    )
}

enum TrackingStatus: Sendable {
    case idle
    case preparing
    case preview(String)
    case searching(String)
    case tracking
    case paused(String)
    case lowConfidence(String)
    case unavailable(String)

    var message: String {
        switch self {
        case .idle:
            return "Tracking idle."
        case .preparing:
            return "Preparing tracking session."
        case .preview(let message),
             .searching(let message),
             .paused(let message),
             .lowConfidence(let message),
             .unavailable(let message):
            return message
        case .tracking:
            return "Live tracking is active."
        }
    }
}

enum PipetteHandedness: String, CaseIterable, Identifiable, Sendable, Equatable {
    case left
    case right

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum PipetteCalibrationStep: Sendable, Equatable {
    case handNotSelected
    case waitingForHand
    case readyForRest
    case collectingRest
    case readyForPress
    case collectingPress
    case complete
    case failed
}

struct PipetteCalibrationState: Sendable, Equatable {
    var selectedHand: PipetteHandedness?
    var step: PipetteCalibrationStep
    var restSampleCount: Int
    var pressedSampleCount: Int
    var requiredSampleCount: Int
    var errorMessage: String?

    var isComplete: Bool {
        step == .complete
    }

    var summary: String {
        switch step {
        case .handNotSelected:
            return "Select the hand holding the pipette to begin calibration."
        case .waitingForHand:
            return "Show the selected hand in the mixed reality view to start calibration."
        case .readyForRest:
            return "Hold the pipette at rest, then capture the resting thumb pose."
        case .collectingRest:
            return "Capturing resting thumb pose (\(restSampleCount)/\(requiredSampleCount))."
        case .readyForPress:
            return "Press and hold the pipette button, then capture the pressed thumb pose."
        case .collectingPress:
            return "Capturing pressed thumb pose (\(pressedSampleCount)/\(requiredSampleCount))."
        case .complete:
            return "Calibration complete. Live thumb-press detection is active."
        case .failed:
            return errorMessage ?? "Calibration failed. Reset and try again."
        }
    }

    static let idle = PipetteCalibrationState(
        selectedHand: nil,
        step: .handNotSelected,
        restSampleCount: 0,
        pressedSampleCount: 0,
        requiredSampleCount: 24,
        errorMessage: nil
    )
}

enum PipetteInputTrackingStatus: Sendable, Equatable {
    case idle
    case waitingForImmersiveSpace
    case requestingAuthorization
    case waitingForHand
    case calibrating
    case ready
    case unavailable(String)

    var message: String {
        switch self {
        case .idle:
            return "Pipette input is idle."
        case .waitingForImmersiveSpace:
            return "Open the mixed reality view to start pipette input tracking."
        case .requestingAuthorization:
            return "Requesting hand-tracking access."
        case .waitingForHand:
            return "Waiting for the selected pipette hand."
        case .calibrating:
            return "Collecting thumb calibration samples."
        case .ready:
            return "Thumb-press detection is active."
        case .unavailable(let message):
            return message
        }
    }
}

struct PlateAnchorState: Sendable {
    let plate: PlateID
    var transform: simd_float4x4
    var position: SIMD3<Float>
    var localBoundsCenter: SIMD3<Float>
    var localBoundsExtent: SIMD3<Float>
    var confidence: Float
    var isSimulated: Bool = false
}

struct DetectedToolPose: Sendable {
    let plate: PlateID
    let position: SIMD3<Float>
    let confidence: Float
}

struct PipettePressState: Sendable, Equatable {
    var selectedHand: PipetteHandedness?
    var calibration: PipetteCalibrationState
    var trackingStatus: PipetteInputTrackingStatus
    var gripConfidence: Float
    var isPressed: Bool
    var pressBeganAt: Date?
    var pressEndedAt: Date?
    var pressCount: Int
    var currentTravel: Float?

    static let idle = PipettePressState(
        selectedHand: nil,
        calibration: .idle,
        trackingStatus: .waitingForImmersiveSpace,
        gripConfidence: 0,
        isPressed: false,
        pressBeganAt: nil,
        pressEndedAt: nil,
        pressCount: 0,
        currentTravel: nil
    )
}

struct TrackingSnapshot: Sendable {
    var status: TrackingStatus
    var plateAnchors: [PlateID: PlateAnchorState]
    var detectedToolPose: DetectedToolPose?
    var pipetteInput: PipettePressState

    static let idle = TrackingSnapshot(
        status: .idle,
        plateAnchors: [:],
        detectedToolPose: nil,
        pipetteInput: .idle
    )
}

enum AppState {
    case idle
    case loadingCSV
    case mapping
    case runningStep(Step)
    case validatingAspiration
    case validatingDispense
    case completed

    var title: String {
        switch self {
        case .idle:
            return "Idle"
        case .loadingCSV:
            return "Loading CSV"
        case .mapping:
            return "Mapping Coordinates"
        case .runningStep(let step):
            return "Running Step \(step.sequenceNumber)"
        case .validatingAspiration:
            return "Validating Aspiration"
        case .validatingDispense:
            return "Validating Dispense"
        case .completed:
            return "Completed"
        }
    }
}

struct WorkflowSummary: Sendable {
    let totalSteps: Int
    let aspirationWarnings: Int
    let dispenseWarnings: Int
    let completedAt: Date
}
