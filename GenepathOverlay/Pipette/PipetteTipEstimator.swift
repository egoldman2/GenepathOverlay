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

    func worldDirection(forAnchorDirection anchorDirection: SIMD3<Float>) -> SIMD3<Float> {
        (originFromAnchorTransform * SIMD4<Float>(anchorDirection, 0)).xyz
    }
}

struct PipetteTipEstimatorProfile: Sendable, Equatable {
    let tipDirectionInHandSpace: SIMD3<Float>
    let tipLength: Float

    var calibrationConfidence: Float {
        0.9
    }

    static func build(
        from pressProfile: PipetteCalibrationProfile,
        tipDirectionInHandSpace: SIMD3<Float>,
        tipLength: Float = 0.25
    ) -> PipetteTipEstimatorProfile? {
        let lengthSquared = simd_length_squared(pressProfile.pressDirection)
        let directionLengthSquared = simd_length_squared(tipDirectionInHandSpace)
        guard lengthSquared > 0.000001, directionLengthSquared > 0.000001 else {
            return nil
        }

        return PipetteTipEstimatorProfile(
            tipDirectionInHandSpace: tipDirectionInHandSpace / sqrt(directionLengthSquared),
            tipLength: tipLength
        )
    }
}

struct PipetteTipEstimator: Sendable {
    private let smoothingSampleCount: Int
    private(set) var profile: PipetteTipEstimatorProfile?
    private var smoothedTipSamples: [SIMD3<Float>] = []

    init(smoothingSampleCount: Int = 12) {
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

        let gripWorldPosition = handPose.worldPosition(forAnchorPosition: handPose.gripReferencePosition)
        let tipDirection = handPose.worldDirection(forAnchorDirection: profile.tipDirectionInHandSpace)
        let rawTipPosition = gripWorldPosition + normalized(tipDirection) * profile.tipLength

        smoothedTipSamples.append(rawTipPosition)
        if smoothedTipSamples.count > smoothingSampleCount {
            smoothedTipSamples.removeFirst(smoothedTipSamples.count - smoothingSampleCount)
        }

        let total = smoothedTipSamples.reduce(SIMD3<Float>.zero, +)
        return total / Float(smoothedTipSamples.count)
    }

    private func normalized(_ vector: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(vector)
        guard lengthSquared > 0.000001 else { return SIMD3<Float>(0, -1, 0) }
        return vector / sqrt(lengthSquared)
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
    let minimumPlateConfidence: Float

    init(
        wellTolerance: Float = 0.014,
        minimumPlateConfidence: Float = 0.10
    ) {
        self.wellTolerance = wellTolerance
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

        let projectedLocalPosition = SIMD3<Float>(
            bestCandidate.localPosition.x,
            bestCandidate.coordinate.normalizedPosition.y,
            bestCandidate.localPosition.z
        )
        let distanceScore = scaledConfidence(
            value: bestCandidate.distanceXZ,
            maximum: wellTolerance,
            floor: 0.65
        )
        let confidence = min(bestCandidate.plateConfidence, calibrationConfidence, distanceScore)
        let detectedConfidence = max(confidence, 0.30)
        let status = bestCandidate.distanceXZ <= wellTolerance
            ? "Tip over \(bestCandidate.coordinate.plate.title) \(bestCandidate.coordinate.well)."
            : "Tip nearest \(bestCandidate.coordinate.plate.title) \(bestCandidate.coordinate.well)."

        return PipetteTipResolution(
            detectedPose: DetectedToolPose(
                plate: bestCandidate.coordinate.plate,
                position: projectedLocalPosition,
                confidence: detectedConfidence
            ),
            closestCoordinate: bestCandidate.coordinate,
            tipWorldPosition: tipWorldPosition,
            confidence: detectedConfidence,
            status: status
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
