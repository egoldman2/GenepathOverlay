import Foundation
import simd

struct PipetteCalibrationProfile: Sendable, Equatable {
    let restThumbPosition: SIMD3<Float>
    let pressedThumbPosition: SIMD3<Float>
    let pressDirection: SIMD3<Float>
    let pressThreshold: Float
    let releaseThreshold: Float
    let maxLateralError: Float

    init(
        restThumbPosition: SIMD3<Float>,
        pressedThumbPosition: SIMD3<Float>,
        pressDirection: SIMD3<Float>,
        pressThreshold: Float,
        releaseThreshold: Float,
        maxLateralError: Float = 0.008
    ) {
        self.restThumbPosition = restThumbPosition
        self.pressedThumbPosition = pressedThumbPosition
        self.pressDirection = pressDirection
        self.pressThreshold = pressThreshold
        self.releaseThreshold = releaseThreshold
        self.maxLateralError = maxLateralError
    }

    func travel(for thumbPosition: SIMD3<Float>) -> Float {
        simd_dot(thumbPosition - restThumbPosition, pressDirection)
    }

    func lateralError(for thumbPosition: SIMD3<Float>) -> Float {
        let delta = thumbPosition - restThumbPosition
        let axialTravel = simd_dot(delta, pressDirection)
        let lateralOffset = delta - pressDirection * axialTravel
        return simd_length(lateralOffset)
    }

    static func build(
        restSamples: [SIMD3<Float>],
        pressedSamples: [SIMD3<Float>],
        minimumTravel: Float = 0.004
    ) -> PipetteCalibrationProfile? {
        guard !restSamples.isEmpty, !pressedSamples.isEmpty else {
            return nil
        }

        let rest = restSamples.reduce(SIMD3<Float>.zero, +) / Float(restSamples.count)
        let pressed = pressedSamples.reduce(SIMD3<Float>.zero, +) / Float(pressedSamples.count)
        let delta = pressed - rest
        let travelMagnitude = simd_length(delta)

        guard travelMagnitude >= minimumTravel else {
            return nil
        }

        let direction = delta / travelMagnitude
        let lateralEnvelope = maxLateralEnvelope(
            samples: restSamples + pressedSamples,
            rest: rest,
            direction: direction
        )

        return PipetteCalibrationProfile(
            restThumbPosition: rest,
            pressedThumbPosition: pressed,
            pressDirection: direction,
            pressThreshold: travelMagnitude * 0.75,
            releaseThreshold: travelMagnitude * 0.30,
            maxLateralError: max(0.006, min(0.014, lateralEnvelope * 2.5 + travelMagnitude * 0.25))
        )
    }

    private static func maxLateralEnvelope(
        samples: [SIMD3<Float>],
        rest: SIMD3<Float>,
        direction: SIMD3<Float>
    ) -> Float {
        samples.reduce(0) { currentMax, sample in
            let delta = sample - rest
            let axialTravel = simd_dot(delta, direction)
            let lateralOffset = delta - direction * axialTravel
            return max(currentMax, simd_length(lateralOffset))
        }
    }
}

struct PipettePressClassifier {
    struct Output: Sendable, Equatable {
        var gripConfidence: Float = 0
        var isPressed = false
        var pressBeganAt: Date?
        var pressEndedAt: Date?
        var pressCount = 0
        var rawTravel: Float?
        var smoothedTravel: Float?
        var lateralError: Float?
    }

    let smoothingSampleCount: Int
    let consecutiveSamplesRequired: Int
    let minimumGripConfidence: Float

    private(set) var calibration: PipetteCalibrationProfile?
    private(set) var output = Output()
    private var smoothedTravelSamples: [Float] = []
    private var aboveThresholdCount = 0
    private var belowThresholdCount = 0

    init(
        smoothingSampleCount: Int = 5,
        consecutiveSamplesRequired: Int = 3,
        minimumGripConfidence: Float = 0.55
    ) {
        self.smoothingSampleCount = smoothingSampleCount
        self.consecutiveSamplesRequired = consecutiveSamplesRequired
        self.minimumGripConfidence = minimumGripConfidence
    }

    mutating func reset() {
        calibration = nil
        output = Output()
        smoothedTravelSamples.removeAll()
        aboveThresholdCount = 0
        belowThresholdCount = 0
    }

    mutating func setCalibration(_ calibration: PipetteCalibrationProfile) {
        self.calibration = calibration
        output = Output()
        smoothedTravelSamples.removeAll()
        aboveThresholdCount = 0
        belowThresholdCount = 0
    }

    mutating func clearSignal(at timestamp: Date) -> Output {
        output.gripConfidence = 0
        output.rawTravel = nil
        output.smoothedTravel = nil
        output.lateralError = nil
        smoothedTravelSamples.removeAll()
        aboveThresholdCount = 0
        belowThresholdCount = 0

        if output.isPressed {
            output.isPressed = false
            output.pressEndedAt = timestamp
        }

        return output
    }

    mutating func update(
        travel: Float?,
        lateralError: Float? = nil,
        gripConfidence: Float,
        timestamp: Date
    ) -> Output {
        output.gripConfidence = gripConfidence
        output.rawTravel = travel
        output.lateralError = lateralError

        guard let calibration, let travel, gripConfidence >= minimumGripConfidence else {
            return clearSignal(at: timestamp)
        }

        if let lateralError, lateralError > calibration.maxLateralError {
            smoothedTravelSamples.removeAll()
            aboveThresholdCount = 0
            belowThresholdCount = 0
            output.smoothedTravel = nil
            return output
        }

        smoothedTravelSamples.append(travel)
        if smoothedTravelSamples.count > smoothingSampleCount {
            smoothedTravelSamples.removeFirst(smoothedTravelSamples.count - smoothingSampleCount)
        }

        let smoothedTravel = smoothedTravelSamples.reduce(0, +) / Float(smoothedTravelSamples.count)
        output.smoothedTravel = smoothedTravel

        if smoothedTravel >= calibration.pressThreshold {
            aboveThresholdCount += 1
            belowThresholdCount = 0

            if output.isPressed == false, aboveThresholdCount >= consecutiveSamplesRequired {
                output.isPressed = true
                output.pressBeganAt = timestamp
                output.pressCount += 1
            }
        } else if smoothedTravel <= calibration.releaseThreshold {
            belowThresholdCount += 1
            aboveThresholdCount = 0

            if output.isPressed, belowThresholdCount >= consecutiveSamplesRequired {
                output.isPressed = false
                output.pressEndedAt = timestamp
            }
        } else {
            aboveThresholdCount = 0
            belowThresholdCount = 0
        }

        return output
    }
}
