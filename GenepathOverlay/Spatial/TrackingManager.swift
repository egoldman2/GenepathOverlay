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

    private struct PipetteHandObservation {
        let thumbLocalPosition: SIMD3<Float>
        let thumbWorldPosition: SIMD3<Float>
        let thumbWorldDirection: SIMD3<Float>?
        let handPose: PipetteHandPose
        let gripConfidence: Float
    }

    private let session = ARKitSession()
    private let coordinateMapper: CoordinateMapper
    private var trackingTask: Task<Void, Never>?
    private var objectAnchorUpdatesTask: Task<Void, Never>?
    private var handAnchorUpdatesTask: Task<Void, Never>?
    private var handFeasibilityTask: Task<Void, Never>?

    private var trackingStatus: TrackingStatus = .idle
    private var basePlateAnchors: [PlateID: PlateAnchorState] = [:]
    private var detectedToolPose: DetectedToolPose?
    private var isTestPlateSimulationEnabled = false
    private var filters: [PlateID: MovingAverageFilter] = [
        .source: MovingAverageFilter(),
        .destination: MovingAverageFilter()
    ]
    private var referenceObjectAssignments: [UUID: PlateID] = [:]

    private var immersiveSpaceActive = false
    private var hasSeenAnyHandAnchor = false
    private var selectedHandSeenRecently = false
    private var hasEvaluatedHandTrackingAvailability = false
    private var handTrackingSupported = false
    private var requestedHandAuthorization = false
    private var handAuthorizationGranted = false
    private let selectedHandLossGraceInterval: TimeInterval = 0.5
    private let handSnapshotPublishInterval: TimeInterval = 1.0 / 30.0
    private var lastSelectedHandObservationAt: Date?
    private var lastHandSnapshotPublishedAt = Date.distantPast

    private var pipetteHandedness: PipetteHandedness?
    private var pipetteCalibrationState = PipetteCalibrationState.idle
    private var pipetteTrackingStatus: PipetteInputTrackingStatus = .waitingForImmersiveSpace
    private var pipettePressClassifier = PipettePressClassifier()
    private var pipetteTipEstimator = PipetteTipEstimator()
    private let pipetteTipWellResolver = PipetteTipWellResolver()
    private var restCalibrationSamples: [SIMD3<Float>] = []
    private var pressedCalibrationSamples: [SIMD3<Float>] = []
    private var latestPipetteOutput = PipettePressClassifier.Output()
    private var latestThumbWorldPosition: SIMD3<Float>?
    private var latestThumbWorldDirection: SIMD3<Float>?
    private var latestTipWorldPosition: SIMD3<Float>?
    private var latestTipConfidence: Float = 0
    private var latestTipStatus = "Tip tracking is idle."

    private(set) var bundledReferenceObjectNames: [String] = [] {
        didSet { onStateChange?() }
    }
    private(set) var discoveredReferenceObjectFiles: [String] = [] {
        didSet { onStateChange?() }
    }
    var onStateChange: (() -> Void)?

    private(set) var snapshot = TrackingSnapshot.idle {
        didSet { onStateChange?() }
    }

    init(coordinateMapper: CoordinateMapper) {
        self.coordinateMapper = coordinateMapper
    }

    func startTracking() {
        stopTracking()
        resetPipetteCalibration(keepSelectedHand: false)
        trackingStatus = .preparing
        detectedToolPose = nil
        publishSnapshot()
        installPreviewAnchors(message: "Preparing object tracking session.")

        trackingTask = Task { [weak self] in
            guard let self else { return }
            await self.startProvidersIfPossible()
        }
    }

    func stopTracking() {
        trackingTask?.cancel()
        objectAnchorUpdatesTask?.cancel()
        handAnchorUpdatesTask?.cancel()
        handFeasibilityTask?.cancel()
        trackingTask = nil
        objectAnchorUpdatesTask = nil
        handAnchorUpdatesTask = nil
        handFeasibilityTask = nil
        referenceObjectAssignments = [:]
        session.stop()

        trackingStatus = .idle
        basePlateAnchors = [:]
        detectedToolPose = nil
        hasSeenAnyHandAnchor = false
        selectedHandSeenRecently = false
        hasEvaluatedHandTrackingAvailability = false
        handTrackingSupported = false
        requestedHandAuthorization = false
        handAuthorizationGranted = false
        lastSelectedHandObservationAt = nil
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        pipetteTipEstimator.reset()
        latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    private func publishSnapshotForHandUpdate() {
        let now = Date()
        let pressStateChanged = latestPipetteOutput.isPressed != snapshot.pipetteInput.isPressed ||
            latestPipetteOutput.pressBeganAt != snapshot.pipetteInput.pressBeganAt ||
            latestPipetteOutput.pressEndedAt != snapshot.pipetteInput.pressEndedAt ||
            latestPipetteOutput.pressCount != snapshot.pipetteInput.pressCount

        guard pressStateChanged || now.timeIntervalSince(lastHandSnapshotPublishedAt) >= handSnapshotPublishInterval else {
            return
        }

        lastHandSnapshotPublishedAt = now
        publishSnapshot()
    }

    func pauseTracking(reason: String) {
        trackingStatus = .paused(reason)
        publishSnapshot()
    }

    func clearDetection() {
        detectedToolPose = nil
        publishSnapshot()
    }

    func simulateDetection(for coordinate: Coordinate, mismatch: Bool = false) {
        let target = mismatch ? coordinateMapper.alternateCoordinate(for: coordinate) : coordinate
        let smoothedPosition = filters[target.plate]?.add(target.normalizedPosition) ?? target.normalizedPosition

        detectedToolPose = DetectedToolPose(
            plate: target.plate,
            position: smoothedPosition,
            confidence: 0.92
        )
        publishSnapshot()
    }

    func setTestPlateSimulationEnabled(_ enabled: Bool) {
        isTestPlateSimulationEnabled = enabled
        publishSnapshot()
    }

    func setImmersiveSpaceActive(_ isActive: Bool) {
        immersiveSpaceActive = isActive

        if isActive {
            scheduleHandFeasibilityGateIfNeeded()
        } else {
            handFeasibilityTask?.cancel()
            selectedHandSeenRecently = false
            lastSelectedHandObservationAt = nil
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Tip tracking is idle."
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
        }

        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func setPipetteHandedness(_ handedness: PipetteHandedness?) {
        guard pipetteHandedness != handedness else { return }
        pipetteHandedness = handedness
        resetPipetteCalibration(keepSelectedHand: true)
    }

    func startRestCalibrationCapture() {
        guard pipetteHandedness != nil else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Choose the pipette hand before capturing calibration."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        guard immersiveSpaceActive else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Open the mixed reality view before calibrating the pipette input."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        restCalibrationSamples.removeAll()
        pressedCalibrationSamples.removeAll()
        pipettePressClassifier.reset()
        pipetteTipEstimator.reset()
        latestPipetteOutput = PipettePressClassifier.Output()
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        detectedToolPose = nil
        pipetteCalibrationState.selectedHand = pipetteHandedness
        pipetteCalibrationState.restSampleCount = 0
        pipetteCalibrationState.pressedSampleCount = 0
        pipetteCalibrationState.errorMessage = nil
        pipetteCalibrationState.step = .collectingRest
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func startPressedCalibrationCapture() {
        guard pipetteCalibrationState.step == .readyForPress || pipetteCalibrationState.step == .complete else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Capture the resting thumb pose before recording the pressed pose."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        pressedCalibrationSamples.removeAll()
        pipetteTipEstimator.reset()
        pipetteCalibrationState.pressedSampleCount = 0
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        detectedToolPose = nil
        pipetteCalibrationState.errorMessage = nil
        pipetteCalibrationState.step = .collectingPress
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func resetPipetteCalibration(keepSelectedHand: Bool = true) {
        let selectedHand = keepSelectedHand ? pipetteHandedness : nil

        if keepSelectedHand == false {
            pipetteHandedness = nil
        }

        restCalibrationSamples.removeAll()
        pressedCalibrationSamples.removeAll()
        pipettePressClassifier.reset()
        pipetteTipEstimator.reset()
        latestPipetteOutput = PipettePressClassifier.Output()
        lastSelectedHandObservationAt = nil
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        detectedToolPose = nil
        pipetteCalibrationState = .idle
        pipetteCalibrationState.selectedHand = selectedHand
        pipetteCalibrationState.step = selectedHand == nil ? .handNotSelected : .waitingForHand
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    private func installPreviewAnchors(message: String) {
        var anchors: [PlateID: PlateAnchorState] = basePlateAnchors

        for plate in PlateID.allCases {
            let position = coordinateMapper.plateWorldPosition(for: plate)
            let smoothedPosition = filters[plate]?.add(position) ?? position
            anchors[plate] = PlateAnchorState(
                plate: plate,
                transform: coordinateMapper.plateWorldTransform(for: plate),
                position: smoothedPosition,
                localBoundsCenter: coordinateMapper.plateOutlineCenter(for: plate),
                localBoundsExtent: coordinateMapper.plateOutlineExtent(for: plate),
                confidence: 0.94
            )
        }

        trackingStatus = .preview(message)
        basePlateAnchors = anchors
        publishSnapshot()
    }

    private func startProvidersIfPossible() async {
        guard #available(visionOS 2.0, *) else {
            installPreviewAnchors(message: "Object tracking requires visionOS 2.0 or newer. Preview anchors are active.")
            pipetteTrackingStatus = .unavailable("Hand tracking requires visionOS 2.0 or newer.")
            publishSnapshot()
            return
        }

        do {
            let candidateReferenceObjectURLs = referenceObjectURLs()
            discoveredReferenceObjectFiles = candidateReferenceObjectURLs.map(\.lastPathComponent)

            let referenceObjects: [ReferenceObject]
            if ObjectTrackingProvider.isSupported {
                referenceObjects = try await loadReferenceObjects(from: candidateReferenceObjectURLs)
                bundledReferenceObjectNames = referenceObjects.map(\.name)
            } else {
                referenceObjects = []
                bundledReferenceObjectNames = []
                installPreviewAnchors(message: "Object tracking is not supported on this device. Preview anchors are active.")
            }

            if ObjectTrackingProvider.isSupported == false {
                // Preview anchors are already installed above.
            } else if referenceObjects.isEmpty {
                let discoveredFiles = discoveredReferenceObjectFiles.joined(separator: ", ")
                let detail = discoveredFiles.isEmpty
                    ? "No .referenceObject files were found in the app bundle."
                    : "Found bundled files (\(discoveredFiles)) but none could be loaded as ARKit reference objects."
                installPreviewAnchors(message: "\(detail) Preview anchors are active.")
            } else {
                assignReferenceObjects(referenceObjects)
            }

            hasEvaluatedHandTrackingAvailability = true
            handTrackingSupported = HandTrackingProvider.isSupported

            let objectProvider = referenceObjects.isEmpty || ObjectTrackingProvider.isSupported == false
                ? nil
                : ObjectTrackingProvider(referenceObjects: referenceObjects)
            let handProvider = handTrackingSupported ? HandTrackingProvider() : nil

            let authorizationTypes = authorizationTypes(objectProviderAvailable: objectProvider != nil, handProviderAvailable: handProvider != nil)
            if authorizationTypes.isEmpty == false {
                requestedHandAuthorization = handProvider != nil
                let authorization = await session.requestAuthorization(for: authorizationTypes)
                handAuthorizationGranted = handProvider == nil || authorization.allSatisfy { auth, status in
                    auth == .handTracking ? status == .allowed : true
                }

                if objectProvider != nil,
                   authorization[.worldSensing] != .allowed {
                    installPreviewAnchors(message: "World sensing permission was not granted. Preview anchors are active.")
                }
            } else {
                handAuthorizationGranted = handProvider == nil
            }

            if handProvider != nil, handAuthorizationGranted == false {
                pipetteTrackingStatus = .unavailable("Hand-tracking permission was not granted.")
            }

            var providers: [any DataProvider] = []

            if let objectProvider {
                providers.append(objectProvider)
                objectAnchorUpdatesTask = Task { [weak self] in
                    guard let self else { return }
                    await self.consumeObjectAnchorUpdates(from: objectProvider)
                }
            }

            if let handProvider, handAuthorizationGranted {
                providers.append(handProvider)
                handAnchorUpdatesTask = Task { [weak self] in
                    guard let self else { return }
                    await self.consumeHandAnchorUpdates(from: handProvider)
                }
                scheduleHandFeasibilityGateIfNeeded()
            }

            trackingStatus = .searching("Object tracking is running. Look directly at the source and destination plates to detect their reference objects.")
            updatePipetteTrackingStatus()
            publishSnapshot()

            guard providers.isEmpty == false else {
                return
            }

            try await session.run(providers)
        } catch {
            installPreviewAnchors(message: "Object tracking failed to start (\(error.localizedDescription)). Preview anchors are active.")
            pipetteTrackingStatus = .unavailable("Hand tracking failed to start (\(error.localizedDescription)).")
            publishSnapshot()
        }
    }

    @available(visionOS 2.0, *)
    private func consumeObjectAnchorUpdates(from provider: ObjectTrackingProvider) async {
        for await update in provider.anchorUpdates {
            if Task.isCancelled { return }

            guard let plate = referenceObjectAssignments[update.anchor.referenceObject.id] else {
                continue
            }

            switch update.event {
            case .added, .updated:
                handleTrackedAnchor(update.anchor, plate: plate)
            case .removed:
                trackingStatus = .lowConfidence("Lost tracking for the \(plate.title.lowercased()) plate.")
                publishSnapshot()
            }
        }
    }

    @available(visionOS 2.0, *)
    private func consumeHandAnchorUpdates(from provider: HandTrackingProvider) async {
        for await update in provider.anchorUpdates {
            if Task.isCancelled { return }

            let anchor = update.anchor
            if anchor.isTracked {
                hasSeenAnyHandAnchor = true
                handFeasibilityTask?.cancel()
            }

            guard anchorMatchesSelectedHand(anchor) else {
                updatePipetteTrackingStatus()
                publishSnapshot()
                continue
            }

            switch update.event {
            case .added, .updated:
                handleSelectedHandAnchor(anchor)
            case .removed:
                handleSelectedHandLoss()
            }
        }
    }

    @available(visionOS 2.0, *)
    private func handleTrackedAnchor(_ anchor: ObjectAnchor, plate: PlateID) {
        let translation = anchor.originFromAnchorTransform.translation
        let livePosition = translation
        var liveTransform = anchor.originFromAnchorTransform
        liveTransform.columns.3 = SIMD4<Float>(livePosition.x, livePosition.y, livePosition.z, 1)
        let confidence: Float = anchor.isTracked ? 0.98 : 0.45

        basePlateAnchors[plate] = PlateAnchorState(
            plate: plate,
            transform: liveTransform,
            position: livePosition,
            localBoundsCenter: anchor.boundingBox.center,
            localBoundsExtent: anchor.boundingBox.extent,
            confidence: confidence
        )
        trackingStatus = anchor.isTracked
            ? .tracking
            : .lowConfidence("Tracking confidence dropped for the \(plate.title.lowercased()) plate.")
        publishSnapshot()
    }

    @available(visionOS 2.0, *)
    private func handleSelectedHandAnchor(_ anchor: HandAnchor) {
        guard let observation = makePipetteHandObservation(from: anchor) else {
            handleSelectedHandLoss()
            return
        }

        lastSelectedHandObservationAt = Date()
        latestThumbWorldPosition = observation.thumbWorldPosition
        if let thumbWorldDirection = observation.thumbWorldDirection {
            latestThumbWorldDirection = thumbWorldDirection
        }
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        selectedHandSeenRecently = true

        switch pipetteCalibrationState.step {
        case .handNotSelected:
            break
        case .waitingForHand:
            pipetteCalibrationState.step = .readyForRest
        case .collectingRest:
            restCalibrationSamples.append(observation.thumbLocalPosition)
            pipetteCalibrationState.restSampleCount = restCalibrationSamples.count
            if restCalibrationSamples.count >= pipetteCalibrationState.requiredSampleCount {
                pipetteCalibrationState.step = .readyForPress
            }
        case .collectingPress:
            pressedCalibrationSamples.append(observation.thumbLocalPosition)
            pipetteCalibrationState.pressedSampleCount = pressedCalibrationSamples.count
            if pressedCalibrationSamples.count >= pipetteCalibrationState.requiredSampleCount {
                finishPressCalibration()
            }
        case .readyForRest, .readyForPress, .complete, .failed:
            break
        }

        let travel = pipettePressClassifier.calibration?.travel(for: observation.thumbLocalPosition)
        latestPipetteOutput = pipettePressClassifier.update(
            travel: travel,
            gripConfidence: observation.gripConfidence,
            timestamp: Date()
        )
        updatePipetteTipEstimate(using: observation)

        updatePipetteTrackingStatus()
        publishSnapshotForHandUpdate()
    }

    private func updatePipetteTipEstimate(using observation: PipetteHandObservation) {
        guard let profile = pipetteTipEstimator.profile else {
            detectedToolPose = nil
            if pipetteCalibrationState.step == .complete {
                latestTipStatus = "Tip calibration is not available."
            }
            return
        }

        guard let tipWorldPosition = pipetteTipEstimator.estimateTipWorldPosition(for: observation.handPose) else {
            latestTipStatus = "Tip calibration is not available."
            return
        }

        let resolution = pipetteTipWellResolver.resolve(
            tipWorldPosition: tipWorldPosition,
            plateAnchors: currentPlateAnchors(),
            coordinateMapper: coordinateMapper,
            calibrationConfidence: profile.calibrationConfidence
        )

        latestTipWorldPosition = tipWorldPosition
        latestTipConfidence = resolution.confidence
        latestTipStatus = resolution.status
        detectedToolPose = resolution.detectedPose
    }

    private func currentPlateAnchors() -> [PlateID: PlateAnchorState] {
        var anchors = basePlateAnchors

        if isTestPlateSimulationEnabled {
            anchors[.source] = PlateAnchorState(
                plate: .source,
                transform: coordinateMapper.plateWorldTransform(for: .source),
                position: coordinateMapper.plateWorldPosition(for: .source),
                localBoundsCenter: coordinateMapper.plateOutlineCenter(for: .source),
                localBoundsExtent: coordinateMapper.plateOutlineExtent(for: .source),
                confidence: 0.99,
                isSimulated: true
            )
        }

        return anchors
    }

    private func handleSelectedHandLoss() {
        guard shouldTreatSelectedHandAsLost(at: Date()) else {
            selectedHandSeenRecently = true
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Waiting for selected hand."
            detectedToolPose = nil
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        selectedHandSeenRecently = false
        lastSelectedHandObservationAt = nil
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Waiting for selected hand."
        detectedToolPose = nil
        latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())

        if pipetteHandedness != nil,
           pipetteCalibrationState.isComplete == false,
           pipetteCalibrationState.step != .handNotSelected {
            pipetteCalibrationState.step = .waitingForHand
        }

        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    private func finishPressCalibration() {
        guard let profile = PipetteCalibrationProfile.build(
            restSamples: restCalibrationSamples,
            pressedSamples: pressedCalibrationSamples
        ) else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Thumb travel was too small to calibrate. Try pressing further and recapture."
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Tip tracking is idle."
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
            return
        }

        guard let tipProfile = PipetteTipEstimatorProfile.build(from: profile) else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Could not estimate the fixed pipette tip direction from thumb travel."
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Tip tracking is idle."
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
            return
        }

        pipettePressClassifier.setCalibration(profile)
        pipetteTipEstimator.setProfile(tipProfile)
        latestPipetteOutput = PipettePressClassifier.Output()
        pipetteCalibrationState.step = .complete
        pipetteCalibrationState.errorMessage = nil
        latestTipStatus = "Fixed 25 cm tip tracking is active."
    }

    @available(visionOS 2.0, *)
    private func makePipetteHandObservation(from anchor: HandAnchor) -> PipetteHandObservation? {
        guard anchor.isTracked, let handSkeleton = anchor.handSkeleton else {
            return nil
        }

        guard
            let thumbPadLocalPoint = thumbTrackingPoint(in: handSkeleton),
            let thumbPadWorldPoint = thumbTrackingPoint(in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform)
        else {
            return nil
        }

        let thumbDirection =
            pipetteDirection(in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform)
            ?? thumbDirection(in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform)

        return PipetteHandObservation(
            thumbLocalPosition: thumbPadLocalPoint,
            thumbWorldPosition: thumbPadWorldPoint,
            thumbWorldDirection: thumbDirection,
            handPose: PipetteHandPose(
                originFromAnchorTransform: anchor.originFromAnchorTransform,
                gripReferencePosition: thumbPadLocalPoint
            ),
            gripConfidence: 1
        )
    }

    @available(visionOS 2.0, *)
    private func thumbTrackingPoint(in skeleton: HandSkeleton) -> SIMD3<Float>? {
        thumbTrackingPoint(using: { joint in
            jointLocalPosition(joint, in: skeleton)
        })
    }

    @available(visionOS 2.0, *)
    private func thumbTrackingPoint(
        in skeleton: HandSkeleton,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        thumbTrackingPoint(using: { joint in
            jointPosition(joint, in: skeleton, anchorTransform: anchorTransform)
        })
    }

    @available(visionOS 2.0, *)
    private var thumbTrackingJoints: [HandSkeleton.JointName] {
        let fallbackJoints: [HandSkeleton.JointName] = [
            .thumbTip,
            .thumbIntermediateTip,
            .thumbKnuckle
        ]
        return fallbackJoints
    }

    @available(visionOS 2.0, *)
    private func thumbTrackingPoint(
        using positionForJoint: (HandSkeleton.JointName) -> SIMD3<Float>?
    ) -> SIMD3<Float>? {
        if let tip = positionForJoint(.thumbTip),
           let intermediate = positionForJoint(.thumbIntermediateTip) {
            return tip * 0.75 + intermediate * 0.25
        }

        for joint in thumbTrackingJoints {
            if let position = positionForJoint(joint) {
                return position
            }
        }

        return nil
    }

    @available(visionOS 2.0, *)
    private func jointPosition(
        _ jointName: HandSkeleton.JointName,
        in skeleton: HandSkeleton,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        let joint = skeleton.joint(jointName)
        guard joint.isTracked else {
            return nil
        }

        return (anchorTransform * joint.anchorFromJointTransform).translation
    }

    @available(visionOS 2.0, *)
    private func jointLocalPosition(
        _ jointName: HandSkeleton.JointName,
        in skeleton: HandSkeleton
    ) -> SIMD3<Float>? {
        let joint = skeleton.joint(jointName)
        guard joint.isTracked else {
            return nil
        }

        return joint.anchorFromJointTransform.translation
    }

    private func shouldTreatSelectedHandAsLost(at timestamp: Date) -> Bool {
        guard let lastSelectedHandObservationAt else {
            return true
        }

        return timestamp.timeIntervalSince(lastSelectedHandObservationAt) > selectedHandLossGraceInterval
    }

    @available(visionOS 2.0, *)
    private func pipetteDirection(
        in skeleton: HandSkeleton,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        guard
            let wrist = jointPosition(.forearmWrist, in: skeleton, anchorTransform: anchorTransform),
            let indexKnuckle = jointPosition(.indexFingerKnuckle, in: skeleton, anchorTransform: anchorTransform),
            let littleKnuckle = jointPosition(.littleFingerKnuckle, in: skeleton, anchorTransform: anchorTransform)
        else {
            return nil
        }

        let knuckleCenter = (indexKnuckle + littleKnuckle) * 0.5
        return normalizedDirection(knuckleCenter - wrist)
    }

    @available(visionOS 2.0, *)
    private func thumbDirection(
        in skeleton: HandSkeleton,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        guard
            let thumbTip = jointPosition(.thumbTip, in: skeleton, anchorTransform: anchorTransform)
                ?? jointPosition(.thumbIntermediateTip, in: skeleton, anchorTransform: anchorTransform),
            let thumbKnuckle = jointPosition(.thumbKnuckle, in: skeleton, anchorTransform: anchorTransform)
        else {
            return nil
        }

        return normalizedDirection(thumbTip - thumbKnuckle)
    }

    private func normalizedDirection(_ delta: SIMD3<Float>) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(delta)
        guard lengthSquared > 0.000001 else {
            return SIMD3<Float>(0, -1, 0)
        }

        return delta / sqrt(lengthSquared)
    }

    private func updatePipetteTrackingStatus() {
        if immersiveSpaceActive == false {
            pipetteTrackingStatus = .waitingForImmersiveSpace
            return
        }

        if hasEvaluatedHandTrackingAvailability, handTrackingSupported == false {
            pipetteTrackingStatus = .unavailable("Hand tracking is not supported on this device.")
            return
        }

        if requestedHandAuthorization, handAuthorizationGranted == false {
            pipetteTrackingStatus = .unavailable("Hand-tracking permission was not granted.")
            return
        }

        if pipetteHandedness == nil {
            pipetteTrackingStatus = requestedHandAuthorization ? .idle : .requestingAuthorization
            return
        }

        if hasSeenAnyHandAnchor == false {
            pipetteTrackingStatus = requestedHandAuthorization ? .waitingForHand : .requestingAuthorization
            return
        }

        if selectedHandSeenRecently == false {
            pipetteTrackingStatus = .waitingForHand
            return
        }

        pipetteTrackingStatus = pipetteCalibrationState.isComplete ? .ready : .calibrating
    }

    private func scheduleHandFeasibilityGateIfNeeded() {
        if case .unavailable = pipetteTrackingStatus {
            return
        }

        guard immersiveSpaceActive, hasSeenAnyHandAnchor == false else {
            return
        }

        handFeasibilityTask?.cancel()
        handFeasibilityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            self.finishHandFeasibilityCheck()
        }
    }

    private func finishHandFeasibilityCheck() {
        guard immersiveSpaceActive, hasSeenAnyHandAnchor == false, requestedHandAuthorization else {
            return
        }

        pipetteTrackingStatus = .unavailable(
            "Hand tracking did not produce anchors in the current mixed immersive space. This mode may be unsupported on this device/runtime."
        )
        publishSnapshot()
    }

    @available(visionOS 2.0, *)
    private func loadReferenceObjects(from urls: [URL]) async throws -> [ReferenceObject] {
        var loadedObjects: [ReferenceObject] = []

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let referenceObject = try await loadBundledReferenceObject(from: url)
                loadedObjects.append(referenceObject)
            } catch {
                continue
            }
        }

        return loadedObjects
    }

    @available(visionOS 2.0, *)
    private func loadBundledReferenceObject(from url: URL) async throws -> ReferenceObject {
        let resourceName = url.deletingPathExtension().lastPathComponent

        if Bundle.main.url(forResource: resourceName, withExtension: "referenceobject") != nil {
            return try await ReferenceObject(named: resourceName, from: .main)
        }

        return try await ReferenceObject(from: url)
    }

    private func referenceObjectURLs() -> [URL] {
        let bundleRoot = Bundle.main.bundleURL
        let fileManager = FileManager.default
        let candidateURLs = (try? fileManager.contentsOfDirectory(
            at: bundleRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return candidateURLs.filter { $0.pathExtension.lowercased() == "referenceobject" }
    }

    @available(visionOS 2.0, *)
    private func assignReferenceObjects(_ referenceObjects: [ReferenceObject]) {
        referenceObjectAssignments = [:]

        for (index, referenceObject) in referenceObjects.enumerated() {
            let normalizedName = referenceObject.name.lowercased()
            let plate: PlateID

            if normalizedName.contains("destination") || normalizedName.contains("dest") {
                plate = .destination
            } else if normalizedName.contains("source") {
                plate = .source
            } else {
                plate = index == 0 ? .destination : .source
            }

            referenceObjectAssignments[referenceObject.id] = plate
        }
    }

    private func authorizationTypes(
        objectProviderAvailable: Bool,
        handProviderAvailable: Bool
    ) -> [ARKitSession.AuthorizationType] {
        var types: [ARKitSession.AuthorizationType] = []

        if objectProviderAvailable {
            types.append(contentsOf: ObjectTrackingProvider.requiredAuthorizations)
        }

        if handProviderAvailable {
            types.append(contentsOf: HandTrackingProvider.requiredAuthorizations)
        }

        return Array(Set(types))
    }

    @available(visionOS 2.0, *)
    private func anchorMatchesSelectedHand(_ anchor: HandAnchor) -> Bool {
        guard let pipetteHandedness else {
            return false
        }

        switch (pipetteHandedness, anchor.chirality) {
        case (.left, .left), (.right, .right):
            return true
        default:
            return false
        }
    }

    private func publishSnapshot() {
        let mergedAnchors = currentPlateAnchors()

        snapshot = TrackingSnapshot(
            status: trackingStatus,
            plateAnchors: mergedAnchors,
            detectedToolPose: detectedToolPose,
            pipetteInput: PipettePressState(
                selectedHand: pipetteHandedness,
                calibration: pipetteCalibrationState,
                trackingStatus: pipetteTrackingStatus,
                gripConfidence: latestPipetteOutput.gripConfidence,
                thumbWorldPosition: latestThumbWorldPosition,
                thumbWorldDirection: latestThumbWorldDirection,
                tipWorldPosition: latestTipWorldPosition,
                tipConfidence: latestTipConfidence,
                tipStatus: latestTipStatus,
                isPressed: latestPipetteOutput.isPressed,
                pressBeganAt: latestPipetteOutput.pressBeganAt,
                pressEndedAt: latestPipetteOutput.pressEndedAt,
                pressCount: latestPipetteOutput.pressCount,
                currentTravel: latestPipetteOutput.smoothedTravel
            )
        )
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
