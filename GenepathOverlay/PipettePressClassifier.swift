import Foundation
import simd

struct PipetteCalibrationProfile: Sendable, Equatable {
    let restThumbPosition: SIMD3<Float>
    let pressedThumbPosition: SIMD3<Float>
    let pressDirection: SIMD3<Float>
    let pressThreshold: Float
    let releaseThreshold: Float

    func travel(for thumbPosition: SIMD3<Float>) -> Float {
        simd_dot(thumbPosition - restThumbPosition, pressDirection)
    }

    static func build(
        restSamples: [SIMD3<Float>],
        pressedSamples: [SIMD3<Float>],
        minimumTravel: Float = 0.003
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

        return PipetteCalibrationProfile(
            restThumbPosition: rest,
            pressedThumbPosition: pressed,
            pressDirection: direction,
            pressThreshold: travelMagnitude * 0.65,
            releaseThreshold: travelMagnitude * 0.35
        )
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
        consecutiveSamplesRequired: Int = 2,
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
        gripConfidence: Float,
        timestamp: Date
    ) -> Output {
        output.gripConfidence = gripConfidence
        output.rawTravel = travel

        guard let calibration, let travel, gripConfidence >= minimumGripConfidence else {
            return clearSignal(at: timestamp)
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
