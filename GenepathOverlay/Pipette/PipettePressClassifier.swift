import Foundation
import simd

struct PipetteCalibrationProfile: Sendable, Equatable {
    let restThumbPosition: SIMD3<Float>
    let pressedThumbPosition: SIMD3<Float>
    let pressDirection: SIMD3<Float>
    let restAxialPosition: Float
    let pressSign: Float
    let travelMagnitude: Float
    let pressThreshold: Float
    let releaseThreshold: Float

    init(
        restThumbPosition: SIMD3<Float>,
        pressedThumbPosition: SIMD3<Float>,
        pressDirection: SIMD3<Float>,
        restAxialPosition: Float,
        pressSign: Float,
        travelMagnitude: Float,
        pressThreshold: Float,
        releaseThreshold: Float
    ) {
        self.restThumbPosition = restThumbPosition
        self.pressedThumbPosition = pressedThumbPosition
        self.pressDirection = pressDirection
        self.restAxialPosition = restAxialPosition
        self.pressSign = pressSign
        self.travelMagnitude = travelMagnitude
        self.pressThreshold = pressThreshold
        self.releaseThreshold = releaseThreshold
    }

    func travel(for thumbPosition: SIMD3<Float>) -> Float {
        simd_dot(thumbPosition - restThumbPosition, pressDirection)
    }

    func travel(forAxialPosition axialPosition: Float) -> Float {
        (axialPosition - restAxialPosition) * pressSign
    }

    static func build(
        restSamples: [SIMD3<Float>],
        pressedSamples: [SIMD3<Float>],
        restAxialSamples: [Float] = [],
        pressedAxialSamples: [Float] = [],
        pressAxisHint: SIMD3<Float>? = nil,
        minimumTravel: Float = 0.003
    ) -> PipetteCalibrationProfile? {
        guard !restSamples.isEmpty, !pressedSamples.isEmpty else {
            return nil
        }

        let rest = restSamples.reduce(SIMD3<Float>.zero, +) / Float(restSamples.count)
        let pressed = pressedSamples.reduce(SIMD3<Float>.zero, +) / Float(pressedSamples.count)
        let delta = pressed - rest
        let vectorTravelMagnitude = simd_length(delta)

        guard vectorTravelMagnitude >= minimumTravel else {
            return nil
        }

        let fallbackDirection = delta / vectorTravelMagnitude
        let hintedDirection = normalized(pressAxisHint) ?? fallbackDirection
        let restAxialPosition: Float
        let signedTravelMagnitude: Float
        let sign: Float

        if restAxialSamples.isEmpty == false, pressedAxialSamples.isEmpty == false {
            restAxialPosition = restAxialSamples.reduce(0, +) / Float(restAxialSamples.count)
            let pressedAxialPosition = pressedAxialSamples.reduce(0, +) / Float(pressedAxialSamples.count)
            let axialDelta = pressedAxialPosition - restAxialPosition

            signedTravelMagnitude = abs(axialDelta)
            sign = axialDelta >= 0 ? 1 : -1
        } else {
            let axialDelta = simd_dot(delta, hintedDirection)

            restAxialPosition = simd_dot(rest, hintedDirection)
            signedTravelMagnitude = abs(axialDelta)
            sign = axialDelta >= 0 ? 1 : -1
        }

        guard signedTravelMagnitude >= minimumTravel else {
            return nil
        }

        return PipetteCalibrationProfile(
            restThumbPosition: rest,
            pressedThumbPosition: pressed,
            pressDirection: hintedDirection * sign,
            restAxialPosition: restAxialPosition,
            pressSign: sign,
            travelMagnitude: signedTravelMagnitude,
            pressThreshold: signedTravelMagnitude * 0.58,
            releaseThreshold: signedTravelMagnitude * 0.18
        )
    }

    private static func normalized(_ vector: SIMD3<Float>?) -> SIMD3<Float>? {
        guard let vector else { return nil }

        let lengthSquared = simd_length_squared(vector)
        guard lengthSquared > 0.000001 else {
            return nil
        }

        return vector / sqrt(lengthSquared)
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
        var activeButton: PipetteButtonID?
        var releasedButton: PipetteButtonID?
        var activeButtonSource: PipetteButtonInputSource?
        var releasedButtonSource: PipetteButtonInputSource?
    }

    private let smoothingAlpha: Float
    private let baselineAdaptationAlpha: Float
    private let pressDwellDuration: TimeInterval
    private let releaseDwellDuration: TimeInterval
    private let rearmDwellDuration: TimeInterval
    private let cooldownDuration: TimeInterval
    let minimumGripConfidence: Float

    private(set) var calibration: PipetteCalibrationProfile?
    private(set) var output = Output()
    private var filteredTravel: Float?
    private var restTravelOffset: Float = 0
    private var pressCandidateBeganAt: Date?
    private var releaseCandidateBeganAt: Date?
    private var rearmCandidateBeganAt: Date?
    private var cooldownUntil: Date?
    private var isArmed = false
    private var pressPeakTravel: Float = 0

    init(
        smoothingSampleCount: Int = 1,
        consecutiveSamplesRequired: Int = 1,
        releaseSamplesRequired: Int = 1,
        minimumGripConfidence: Float = 0.20,
        maximumDroppedSamples: Int = 0,
        smoothingAlpha: Float = 0.42,
        baselineAdaptationAlpha: Float = 0.04,
        pressDwellDuration: TimeInterval = 0.08,
        releaseDwellDuration: TimeInterval = 0.12,
        rearmDwellDuration: TimeInterval = 0.18,
        cooldownDuration: TimeInterval = 0.45
    ) {
        self.smoothingAlpha = smoothingAlpha
        self.baselineAdaptationAlpha = baselineAdaptationAlpha
        self.pressDwellDuration = pressDwellDuration
        self.releaseDwellDuration = releaseDwellDuration
        self.rearmDwellDuration = rearmDwellDuration
        self.cooldownDuration = cooldownDuration
        self.minimumGripConfidence = minimumGripConfidence
    }

    mutating func reset() {
        calibration = nil
        output = Output()
        resetRuntimeState()
    }

    mutating func setCalibration(_ calibration: PipetteCalibrationProfile) {
        self.calibration = calibration
        output = Output()
        resetRuntimeState()
    }

    mutating func clearSignal(at timestamp: Date) -> Output {
        output.gripConfidence = 0
        output.rawTravel = nil
        output.smoothedTravel = nil

        if output.isPressed {
            output.isPressed = false
        }

        output.pressBeganAt = nil
        output.pressEndedAt = nil
        output.activeButton = nil
        output.releasedButton = nil
        output.activeButtonSource = nil
        output.releasedButtonSource = nil
        resetRuntimeState()
        return output
    }

    mutating func update(
        travel: Float?,
        lateralError: Float? = nil,
        gripConfidence: Float,
        timestamp: Date,
        button: PipetteButtonID = .plunger
    ) -> Output {
        output.gripConfidence = gripConfidence
        output.rawTravel = travel
        output.releasedButton = nil
        output.releasedButtonSource = nil

        guard let calibration else {
            return clearSignal(at: timestamp)
        }

        guard let travel, gripConfidence >= minimumGripConfidence else {
            output.smoothedTravel = nil
            pressCandidateBeganAt = nil
            releaseCandidateBeganAt = nil
            output.activeButton = output.isPressed ? output.activeButton : nil
            output.activeButtonSource = output.isPressed ? output.activeButtonSource : nil
            return output
        }

        let filtered = filterTravel(travel)
        var adjustedTravel = filtered - restTravelOffset
        output.smoothedTravel = adjustedTravel

        if output.isPressed {
            pressPeakTravel = max(pressPeakTravel, adjustedTravel)
            pressCandidateBeganAt = nil
            rearmCandidateBeganAt = nil
            updateReleaseState(
                adjustedTravel: adjustedTravel,
                calibration: calibration,
                timestamp: timestamp
            )
            return output
        }

        releaseCandidateBeganAt = nil
        adaptRestBaselineIfPossible(filteredTravel: filtered, adjustedTravel: adjustedTravel, calibration: calibration)
        adjustedTravel = filtered - restTravelOffset
        output.smoothedTravel = adjustedTravel

        updateArmedState(adjustedTravel: adjustedTravel, calibration: calibration, timestamp: timestamp)

        guard isArmed,
              cooldownUntil.map({ timestamp >= $0 }) ?? true else {
            pressCandidateBeganAt = nil
            return output
        }

        if adjustedTravel >= calibration.pressThreshold {
            if pressCandidateBeganAt == nil {
                pressCandidateBeganAt = timestamp
            }

            guard let pressStartedAt = pressCandidateBeganAt,
                  timestamp.timeIntervalSince(pressStartedAt) >= pressDwellDuration else {
                return output
            }

            output.isPressed = true
            output.pressBeganAt = timestamp
            output.pressCount += 1
            output.activeButton = button
            output.releasedButton = nil
            output.activeButtonSource = .handTracking
            output.releasedButtonSource = nil
            isArmed = false
            pressPeakTravel = adjustedTravel
            pressCandidateBeganAt = nil
            rearmCandidateBeganAt = nil
        } else {
            pressCandidateBeganAt = nil
        }

        return output
    }

    private mutating func resetRuntimeState() {
        filteredTravel = nil
        restTravelOffset = 0
        pressCandidateBeganAt = nil
        releaseCandidateBeganAt = nil
        rearmCandidateBeganAt = nil
        cooldownUntil = nil
        isArmed = false
        pressPeakTravel = 0
    }

    private mutating func filterTravel(_ travel: Float) -> Float {
        guard let previous = filteredTravel else {
            filteredTravel = travel
            return travel
        }

        let filtered = previous + (travel - previous) * smoothingAlpha
        filteredTravel = filtered
        return filtered
    }

    private mutating func adaptRestBaselineIfPossible(
        filteredTravel: Float,
        adjustedTravel: Float,
        calibration: PipetteCalibrationProfile
    ) {
        let baselineWindow = calibration.pressThreshold * 0.60
        guard adjustedTravel <= baselineWindow else {
            return
        }

        restTravelOffset += (filteredTravel - restTravelOffset) * baselineAdaptationAlpha
    }

    private mutating func updateArmedState(
        adjustedTravel: Float,
        calibration: PipetteCalibrationProfile,
        timestamp: Date
    ) {
        let rearmThreshold = max(calibration.releaseThreshold, calibration.travelMagnitude * 0.22)
        guard adjustedTravel <= rearmThreshold else {
            rearmCandidateBeganAt = nil
            return
        }

        if rearmCandidateBeganAt == nil {
            rearmCandidateBeganAt = timestamp
        }

        if let rearmStartedAt = rearmCandidateBeganAt,
           timestamp.timeIntervalSince(rearmStartedAt) >= rearmDwellDuration,
           cooldownUntil.map({ timestamp >= $0 }) ?? true {
            isArmed = true
        }
    }

    private mutating func updateReleaseState(
        adjustedTravel: Float,
        calibration: PipetteCalibrationProfile,
        timestamp: Date
    ) {
        let hasReturnedToRest = adjustedTravel <= calibration.releaseThreshold
        let hasMovedUpFromPeak = pressPeakTravel - adjustedTravel >= calibration.travelMagnitude * 0.40

        guard hasReturnedToRest, hasMovedUpFromPeak else {
            releaseCandidateBeganAt = nil
            return
        }

        if releaseCandidateBeganAt == nil {
            releaseCandidateBeganAt = timestamp
        }

        if let releaseStartedAt = releaseCandidateBeganAt,
           timestamp.timeIntervalSince(releaseStartedAt) >= releaseDwellDuration {
            output.isPressed = false
            output.pressEndedAt = timestamp
            output.releasedButton = output.activeButton
            output.releasedButtonSource = output.activeButtonSource
            output.activeButton = nil
            output.activeButtonSource = nil
            cooldownUntil = timestamp.addingTimeInterval(cooldownDuration)
            isArmed = false
            releaseCandidateBeganAt = nil
            rearmCandidateBeganAt = timestamp
            pressPeakTravel = 0
        }
    }
}
