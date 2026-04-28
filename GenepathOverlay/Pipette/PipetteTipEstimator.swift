import Foundation
import simd

struct PipetteHandPose: Sendable, Equatable {
    let originFromAnchorTransform: simd_float4x4
    /// The tracked thumb point used as the hand reference. The pipette occludes
    /// most of the hand, so tip estimation must not depend on palm/knuckle joints.
    let gripReferencePosition: SIMD3<Float>

    func worldPosition(forAnchorPosition anchorPosition: SIMD3<Float>) -> SIMD3<Float> {
        (originFromAnchorTransform * SIMD4<Float>(anchorPosition, 1)).xyz
    }

    func anchorPosition(forWorldPosition worldPosition: SIMD3<Float>) -> SIMD3<Float> {
        (simd_inverse(originFromAnchorTransform) * SIMD4<Float>(worldPosition, 1)).xyz
    }
}

struct PipetteTipEstimatorProfile: Sendable, Equatable {
    let tipOffsetInHandSpace: SIMD3<Float>
    let tipLength: Float

    var calibrationConfidence: Float {
        0.9
    }

    static func build(
        from pressProfile: PipetteCalibrationProfile,
        tipLength: Float = 0.25
    ) -> PipetteTipEstimatorProfile? {
        let lengthSquared = simd_length_squared(pressProfile.pressDirection)
        guard lengthSquared > 0.000001 else {
            return nil
        }

        return PipetteTipEstimatorProfile(
            tipOffsetInHandSpace: simd_normalize(pressProfile.pressDirection) * tipLength,
            tipLength: tipLength
        )
    }
}

struct PipetteTipEstimator: Sendable {
    private let smoothingSampleCount: Int
    private(set) var profile: PipetteTipEstimatorProfile?
    private var smoothedTipSamples: [SIMD3<Float>] = []

    init(smoothingSampleCount: Int = 5) {
        self.smoothingSampleCount = smoothingSampleCount
    }

    mutating func reset() {
        profile = nil
        smoothedTipSamples.removeAll()
    }

    mutating func setProfile(_ profile: PipetteTipEstimatorProfile) {
        self.profile = profile
        smoothedTipSamples.removeAll()
    }

    mutating func estimateTipWorldPosition(for handPose: PipetteHandPose) -> SIMD3<Float>? {
        guard let profile else { return nil }

        let rawTipPosition = handPose.worldPosition(
            forAnchorPosition: handPose.gripReferencePosition + profile.tipOffsetInHandSpace
        )

        smoothedTipSamples.append(rawTipPosition)
        if smoothedTipSamples.count > smoothingSampleCount {
            smoothedTipSamples.removeFirst(smoothedTipSamples.count - smoothingSampleCount)
        }

        let total = smoothedTipSamples.reduce(SIMD3<Float>.zero, +)
        return total / Float(smoothedTipSamples.count)
    }
}

struct PipetteTipResolution: Sendable {
    let detectedPose: DetectedToolPose?
    let closestCoordinate: Coordinate?
    let tipWorldPosition: SIMD3<Float>
    let confidence: Float
    let status: String
}

struct PipetteTipWellResolver: Sendable {
    let wellTolerance: Float
    let maximumTipHeightError: Float
    let minimumPlateConfidence: Float

    init(
        wellTolerance: Float = 0.0045,
        maximumTipHeightError: Float = 0.035,
        minimumPlateConfidence: Float = 0.55
    ) {
        self.wellTolerance = wellTolerance
        self.maximumTipHeightError = maximumTipHeightError
        self.minimumPlateConfidence = minimumPlateConfidence
    }

    func resolve(
        tipWorldPosition: SIMD3<Float>,
        plateAnchors: [PlateID: PlateAnchorState],
        coordinateMapper: CoordinateMapper,
        calibrationConfidence: Float
    ) -> PipetteTipResolution {
        var bestCandidate: (coordinate: Coordinate, localPosition: SIMD3<Float>, distanceXZ: Float, heightError: Float, plateConfidence: Float)?

        for plate in PlateID.allCases {
            guard let anchor = plateAnchors[plate], anchor.confidence >= minimumPlateConfidence else {
                continue
            }

            let localTipPosition = (simd_inverse(anchor.transform) * SIMD4<Float>(tipWorldPosition, 1)).xyz
            guard let nearestCoordinate = nearestCoordinate(
                on: plate,
                to: localTipPosition,
                coordinateMapper: coordinateMapper
            ) else {
                continue
            }

            let distanceXZ = xzDistance(localTipPosition, nearestCoordinate.normalizedPosition)
            let heightError = abs(localTipPosition.y - nearestCoordinate.normalizedPosition.y)

            if bestCandidate == nil || distanceXZ < bestCandidate!.distanceXZ {
                bestCandidate = (
                    coordinate: nearestCoordinate,
                    localPosition: localTipPosition,
                    distanceXZ: distanceXZ,
                    heightError: heightError,
                    plateConfidence: anchor.confidence
                )
            }
        }

        guard let bestCandidate else {
            return PipetteTipResolution(
                detectedPose: nil,
                closestCoordinate: nil,
                tipWorldPosition: tipWorldPosition,
                confidence: 0,
                status: "Waiting for plate anchors."
            )
        }

        let distanceScore = scaledConfidence(
            value: bestCandidate.distanceXZ,
            maximum: wellTolerance,
            floor: 0.65
        )
        let heightScore = scaledConfidence(
            value: bestCandidate.heightError,
            maximum: maximumTipHeightError,
            floor: 0.65
        )
        let confidence = min(bestCandidate.plateConfidence, calibrationConfidence, distanceScore, heightScore)

        guard bestCandidate.distanceXZ <= wellTolerance else {
            return PipetteTipResolution(
                detectedPose: nil,
                closestCoordinate: bestCandidate.coordinate,
                tipWorldPosition: tipWorldPosition,
                confidence: confidence,
                status: "Tip near \(bestCandidate.coordinate.plate.title) \(bestCandidate.coordinate.well), outside well tolerance."
            )
        }

        guard bestCandidate.heightError <= maximumTipHeightError else {
            return PipetteTipResolution(
                detectedPose: nil,
                closestCoordinate: bestCandidate.coordinate,
                tipWorldPosition: tipWorldPosition,
                confidence: confidence,
                status: "Tip is too far above the well plane."
            )
        }

        return PipetteTipResolution(
            detectedPose: DetectedToolPose(
                plate: bestCandidate.coordinate.plate,
                position: bestCandidate.localPosition,
                confidence: confidence
            ),
            closestCoordinate: bestCandidate.coordinate,
            tipWorldPosition: tipWorldPosition,
            confidence: confidence,
            status: "Tip over \(bestCandidate.coordinate.plate.title) \(bestCandidate.coordinate.well)."
        )
    }

    private func nearestCoordinate(
        on plate: PlateID,
        to localPosition: SIMD3<Float>,
        coordinateMapper: CoordinateMapper
    ) -> Coordinate? {
        coordinateMapper.nearestCoordinate(for: plate, to: localPosition)
    }

    private func xzDistance(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Float {
        let delta = SIMD2<Float>(lhs.x - rhs.x, lhs.z - rhs.z)
        return simd_length(delta)
    }

    private func scaledConfidence(value: Float, maximum: Float, floor: Float) -> Float {
        guard maximum > 0 else { return 0 }
        guard value <= maximum else { return max(0, 1 - value / maximum) }
        return max(0, min(1, floor + (1 - floor) * (1 - value / maximum)))
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
