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

struct PlateAnchorState: Sendable {
    let plate: PlateID
    var transform: simd_float4x4
    var position: SIMD3<Float>
    var localBoundsCenter: SIMD3<Float>
    var localBoundsExtent: SIMD3<Float>
    var confidence: Float
}

struct DetectedToolPose: Sendable {
    let plate: PlateID
    let position: SIMD3<Float>
    let confidence: Float
}

struct TrackingSnapshot: Sendable {
    var status: TrackingStatus
    var plateAnchors: [PlateID: PlateAnchorState]
    var detectedToolPose: DetectedToolPose?

    static let idle = TrackingSnapshot(
        status: .idle,
        plateAnchors: [:],
        detectedToolPose: nil
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
