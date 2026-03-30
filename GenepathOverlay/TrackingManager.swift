import ARKit
import Foundation
import simd

@MainActor
final class TrackingManager {
    private struct MovingAverageFilter {
        private let maxSamples: Int
        private var samples: [SIMD3<Float>] = []

        init(maxSamples: Int = 5) {
            self.maxSamples = maxSamples
        }

        mutating func add(_ sample: SIMD3<Float>) -> SIMD3<Float> {
            samples.append(sample)
            if samples.count > maxSamples {
                samples.removeFirst(samples.count - maxSamples)
            }

            let total = samples.reduce(SIMD3<Float>.zero, +)
            return total / Float(samples.count)
        }
    }

    private let session = ARKitSession()
    private let coordinateMapper: CoordinateMapper
    private var filters: [PlateID: MovingAverageFilter] = [
        .source: MovingAverageFilter(),
        .destination: MovingAverageFilter()
    ]

    private(set) var snapshot = TrackingSnapshot.idle

    init(coordinateMapper: CoordinateMapper) {
        self.coordinateMapper = coordinateMapper
    }

    func startTracking() {
        snapshot.status = .preparing

        var anchors: [PlateID: PlateAnchorState] = [:]
        for plate in PlateID.allCases {
            let position = coordinateMapper.plateWorldPosition(for: plate)
            let smoothedPosition = filters[plate]?.add(position) ?? position
            anchors[plate] = PlateAnchorState(
                plate: plate,
                position: smoothedPosition,
                confidence: 0.94
            )
        }

        let referenceObjectExists = Bundle.main.url(forResource: "Plate", withExtension: "referenceObject") != nil
        let trackingStatus: TrackingStatus

        if referenceObjectExists {
            trackingStatus = .preview("Reference assets are bundled. Provider hookup is the next step, but preview anchors are active now.")
        } else {
            trackingStatus = .preview("TrackingManager is running in preview mode until trained plate and pipette reference assets are added.")
        }

        snapshot = TrackingSnapshot(
            status: trackingStatus,
            plateAnchors: anchors,
            detectedToolPose: nil
        )
    }

    func stopTracking() {
        session.stop()
        snapshot = .idle
    }

    func pauseTracking(reason: String) {
        snapshot.status = .paused(reason)
    }

    func clearDetection() {
        snapshot.detectedToolPose = nil
    }

    func simulateDetection(for coordinate: Coordinate, mismatch: Bool = false) {
        let target = mismatch ? coordinateMapper.alternateCoordinate(for: coordinate) : coordinate
        let smoothedPosition = filters[target.plate]?.add(target.normalizedPosition) ?? target.normalizedPosition

        snapshot.detectedToolPose = DetectedToolPose(
            plate: target.plate,
            position: smoothedPosition,
            confidence: 0.92
        )
    }
}
