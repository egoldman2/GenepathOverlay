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
        let thumbRelativePosition: SIMD3<Float>
        let buttonTravelPosition: Float
        let thumbWorldPosition: SIMD3<Float>
        let thumbWorldDirection: SIMD3<Float>?
        let tipDirectionInHandSpace: SIMD3<Float>
        let handPose: PipetteHandPose
        let gripConfidence: Float
    }

    private struct PipetteGripObservation {
        let handPose: PipetteHandPose
        let gripConfidence: Float
    }

    private struct PipetteVisibleGrip {
        let center: SIMD3<Float>
        let shaftReference: SIMD3<Float>
        let tipDirectionInHandSpace: SIMD3<Float>
        let confidence: Float
    }

    @available(visionOS 2.0, *)
    private struct LoadedReferenceObject {
        let object: ReferenceObject
        let fileName: String
        let plate: PlateID
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
    private let selectedHandLossGraceInterval: TimeInterval = 1.5
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
    private var restButtonTravelSamples: [Float] = []
    private var restTipDirectionSamples: [SIMD3<Float>] = []
    private var pressedCalibrationSamples: [SIMD3<Float>] = []
    private var pressedButtonTravelSamples: [Float] = []
    private var latestPipetteOutput = PipettePressClassifier.Output()
    private var latestThumbWorldPosition: SIMD3<Float>?
    private var latestThumbWorldDirection: SIMD3<Float>?
    private var latestTipWorldPosition: SIMD3<Float>?
    private var latestTipConfidence: Float = 0
    private var latestTipStatus = "Tip tracking is idle."
    private var latestTipHandPose: PipetteHandPose?
    private var manualTipOffsetInHandSpace: SIMD3<Float> = TrackingManager.loadSavedManualTipOffset()
    private var isTipEstimateFrozen = false
    private var frozenTipWorldPosition: SIMD3<Float>?
    private var frozenManualTipOffsetBaselineInHandSpace: SIMD3<Float>?

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
        latestTipHandPose = nil
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
            latestPipetteOutput.pressCount != snapshot.pipetteInput.pressCount ||
            latestPipetteOutput.activeButton != snapshot.pipetteInput.activeButton ||
            latestPipetteOutput.releasedButton != snapshot.pipetteInput.releasedButton ||
            latestPipetteOutput.activeButtonSource != snapshot.pipetteInput.activeButtonSource ||
            latestPipetteOutput.releasedButtonSource != snapshot.pipetteInput.releasedButtonSource

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

    func recordExternalPipetteButtonRelease(_ button: PipetteButtonID) {
        let releaseAt = Date()
        latestPipetteOutput.isPressed = false
        latestPipetteOutput.pressBeganAt = releaseAt.addingTimeInterval(-0.18)
        latestPipetteOutput.pressEndedAt = releaseAt
        latestPipetteOutput.pressCount += 1
        latestPipetteOutput.rawTravel = nil
        latestPipetteOutput.smoothedTravel = nil
        latestPipetteOutput.gripConfidence = max(latestPipetteOutput.gripConfidence, 1)
        latestPipetteOutput.activeButton = nil
        latestPipetteOutput.releasedButton = button
        latestPipetteOutput.activeButtonSource = nil
        latestPipetteOutput.releasedButtonSource = .externalButton
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
            clearFrozenTipEstimate()
            selectedHandSeenRecently = false
            lastSelectedHandObservationAt = nil
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Tip tracking is idle."
            latestTipHandPose = nil
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
        }

        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func setPipetteHandedness(_ handedness: PipetteHandedness?) {
        guard pipetteHandedness != handedness else { return }
        pipetteHandedness = handedness
        resetPipetteCalibration(
            keepSelectedHand: true,
            keepTipAttachment: pipetteCalibrationState.isTipAttachmentConfirmed
        )
    }

    func confirmCalibrationTipAttached() {
        guard pipetteCalibrationState.isTipAttachmentConfirmed == false else { return }
        pipetteCalibrationState.isTipAttachmentConfirmed = true
        pipetteCalibrationState.errorMessage = nil
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func startRestCalibrationCapture() {
        guard pipetteCalibrationState.isTipAttachmentConfirmed else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Attach a pipette tip before capturing calibration."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

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
        restButtonTravelSamples.removeAll()
        restTipDirectionSamples.removeAll()
        pressedCalibrationSamples.removeAll()
        pressedButtonTravelSamples.removeAll()
        pipettePressClassifier.reset()
        pipetteTipEstimator.reset()
        clearFrozenTipEstimate()
        latestPipetteOutput = PipettePressClassifier.Output()
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        latestTipHandPose = nil
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
        guard pipetteCalibrationState.isTipAttachmentConfirmed else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Attach a pipette tip before capturing calibration."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        guard pipetteCalibrationState.step == .readyForPress || pipetteCalibrationState.step == .complete else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Capture the resting thumb pose before recording the pressed pose."
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        pressedCalibrationSamples.removeAll()
        pressedButtonTravelSamples.removeAll()
        pipetteTipEstimator.reset()
        clearFrozenTipEstimate()
        pipetteCalibrationState.pressedSampleCount = 0
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        latestTipHandPose = nil
        detectedToolPose = nil
        pipetteCalibrationState.errorMessage = nil
        pipetteCalibrationState.step = .collectingPress
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func resetPipetteCalibration(
        keepSelectedHand: Bool = true,
        keepTipAttachment: Bool = false
    ) {
        let selectedHand = keepSelectedHand ? pipetteHandedness : nil
        let isTipAttachmentConfirmed = keepTipAttachment ? pipetteCalibrationState.isTipAttachmentConfirmed : false

        if keepSelectedHand == false {
            pipetteHandedness = nil
        }

        restCalibrationSamples.removeAll()
        restButtonTravelSamples.removeAll()
        restTipDirectionSamples.removeAll()
        pressedCalibrationSamples.removeAll()
        pressedButtonTravelSamples.removeAll()
        pipettePressClassifier.reset()
        pipetteTipEstimator.reset()
        clearFrozenTipEstimate()
        latestPipetteOutput = PipettePressClassifier.Output()
        lastSelectedHandObservationAt = nil
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        latestTipWorldPosition = nil
        latestTipConfidence = 0
        latestTipStatus = "Tip tracking is idle."
        latestTipHandPose = nil
        detectedToolPose = nil
        pipetteCalibrationState = .idle
        pipetteCalibrationState.selectedHand = selectedHand
        pipetteCalibrationState.isTipAttachmentConfirmed = isTipAttachmentConfirmed
        pipetteCalibrationState.step = selectedHand == nil ? .handNotSelected : .waitingForHand
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func saveManualPipetteTipOffset() {
        guard pipetteCalibrationState.step == .adjustingTip else { return }
        saveManualTipOffset(manualTipOffsetInHandSpace)
        clearFrozenTipEstimate()
        pipetteCalibrationState.step = .complete
        latestTipStatus = "Grip-based tip tracking is active."
        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    func resetManualPipetteTipOffset() {
        clearFrozenTipEstimate()
        let oldWorldOffset = latestTipHandPose?.worldDirection(forAnchorDirection: manualTipOffsetInHandSpace) ?? .zero
        manualTipOffsetInHandSpace = .zero
        saveManualTipOffset(manualTipOffsetInHandSpace)
        updateCurrentTipAfterManualOffsetChange(worldDelta: -oldWorldOffset)
    }

    func toggleFrozenManualPipetteTipEstimate() {
        guard pipetteCalibrationState.step == .adjustingTip else { return }

        if isTipEstimateFrozen {
            clearFrozenTipEstimate()
            latestTipStatus = "Move the red tip marker onto the real pipette tip."
            publishSnapshot()
            return
        }

        guard let latestTipWorldPosition else { return }

        isTipEstimateFrozen = true
        frozenTipWorldPosition = latestTipWorldPosition
        frozenManualTipOffsetBaselineInHandSpace = manualTipOffsetInHandSpace
        latestTipStatus = "Move the real pipette tip onto the frozen marker, then save the offset."
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

            let loadedReferenceObjects: [LoadedReferenceObject]
            let referenceObjects: [ReferenceObject]
            if ObjectTrackingProvider.isSupported {
                loadedReferenceObjects = try await loadReferenceObjects(from: candidateReferenceObjectURLs)
                referenceObjects = loadedReferenceObjects.map(\.object)
                bundledReferenceObjectNames = loadedReferenceObjects.map {
                    "\($0.fileName) -> \($0.plate.title) (\($0.object.name))"
                }
            } else {
                loadedReferenceObjects = []
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
                assignReferenceObjects(loadedReferenceObjects)
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
            if let gripObservation = makePipetteGripObservation(from: anchor) {
                handleSelectedGripAnchor(gripObservation)
            } else {
                handleSelectedHandObservationDropout()
            }
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
            restCalibrationSamples.append(observation.thumbRelativePosition)
            restButtonTravelSamples.append(observation.buttonTravelPosition)
            restTipDirectionSamples.append(observation.tipDirectionInHandSpace)
            pipetteCalibrationState.restSampleCount = restCalibrationSamples.count
            if restCalibrationSamples.count >= pipetteCalibrationState.requiredSampleCount {
                pipetteCalibrationState.step = .readyForPress
            }
        case .collectingPress:
            pressedCalibrationSamples.append(observation.thumbRelativePosition)
            pressedButtonTravelSamples.append(observation.buttonTravelPosition)
            pipetteCalibrationState.pressedSampleCount = pressedCalibrationSamples.count
            if pressedCalibrationSamples.count >= pipetteCalibrationState.requiredSampleCount {
                finishPressCalibration()
            }
        case .readyForRest, .readyForPress, .adjustingTip, .complete, .failed:
            break
        }

        let travel = pipettePressClassifier.calibration?.travel(forAxialPosition: observation.buttonTravelPosition)
        latestPipetteOutput = pipettePressClassifier.update(
            travel: travel,
            gripConfidence: observation.gripConfidence,
            timestamp: Date()
        )
        updatePipetteTipEstimate(using: observation)

        updatePipetteTrackingStatus()
        publishSnapshotForHandUpdate()
    }

    private func handleSelectedGripAnchor(_ observation: PipetteGripObservation) {
        lastSelectedHandObservationAt = Date()
        selectedHandSeenRecently = true
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
        updatePipetteTipEstimate(using: observation)
        updatePipetteTrackingStatus()
        publishSnapshotForHandUpdate()
    }

    private func updatePipetteTipEstimate(using observation: PipetteHandObservation) {
        let gripObservation = PipetteGripObservation(
            handPose: observation.handPose,
            gripConfidence: observation.gripConfidence
        )
        updatePipetteTipEstimate(using: gripObservation)
    }

    private func updatePipetteTipEstimate(using observation: PipetteGripObservation) {
        if pipetteTipEstimator.profile == nil {
            if let tipProfile = PipetteTipEstimatorProfile.build(
                tipDirectionInHandSpace: observation.handPose.tipDirectionInHandSpace ?? SIMD3<Float>(0, -1, 0),
                tipLength: 0.18
            ) {
                pipetteTipEstimator.setProfile(tipProfile)
            } else {
                detectedToolPose = nil
                if pipetteCalibrationState.step == .complete {
                    latestTipStatus = "Tip calibration is not available."
                }
                return
            }
        }
        guard let profile = pipetteTipEstimator.profile else { return }

        let offsetInHandSpace = frozenManualTipOffsetBaselineInHandSpace ?? manualTipOffsetInHandSpace
        let adjustedHandPose = PipetteHandPose(
            originFromAnchorTransform: observation.handPose.originFromAnchorTransform,
            gripReferencePosition: observation.handPose.gripReferencePosition + offsetInHandSpace,
            tipDirectionInHandSpace: observation.handPose.tipDirectionInHandSpace
        )

        guard let liveTipWorldPosition = pipetteTipEstimator.estimateTipWorldPosition(for: adjustedHandPose) else {
            latestTipStatus = "Tip calibration is not available."
            return
        }

        latestTipHandPose = observation.handPose
        let tipWorldPosition: SIMD3<Float>

        if pipetteCalibrationState.step == .adjustingTip,
           isTipEstimateFrozen,
           let frozenTipWorldPosition,
           let baselineOffset = frozenManualTipOffsetBaselineInHandSpace {
            let worldDelta = frozenTipWorldPosition - liveTipWorldPosition
            manualTipOffsetInHandSpace = baselineOffset + observation.handPose.anchorDirection(forWorldDirection: worldDelta)
            tipWorldPosition = frozenTipWorldPosition
            latestTipStatus = "Move the real pipette tip onto the frozen marker, then save the offset."
        } else {
            tipWorldPosition = liveTipWorldPosition
        }

        let calibrationConfidence = min(pipetteTipEstimator.profile?.calibrationConfidence ?? profile.calibrationConfidence, observation.gripConfidence)

        let resolution = pipetteTipWellResolver.resolve(
            tipWorldPosition: tipWorldPosition,
            plateAnchors: currentPlateAnchors(),
            coordinateMapper: coordinateMapper,
            calibrationConfidence: calibrationConfidence
        )

        latestTipWorldPosition = tipWorldPosition
        latestTipConfidence = resolution.confidence
        if isTipEstimateFrozen == false {
            latestTipStatus = resolution.status
        }
        detectedToolPose = resolution.detectedPose
    }

    private func updateCurrentTipAfterManualOffsetChange(worldDelta: SIMD3<Float>) {
        if simd_length_squared(worldDelta) > 0, let latestTipWorldPosition {
            pipetteTipEstimator.offsetFilteredTipPosition(by: worldDelta)
            self.latestTipWorldPosition = latestTipWorldPosition + worldDelta
        }

        if let latestTipWorldPosition {
            let resolution = pipetteTipWellResolver.resolve(
                tipWorldPosition: latestTipWorldPosition,
                plateAnchors: currentPlateAnchors(),
                coordinateMapper: coordinateMapper,
                calibrationConfidence: pipetteTipEstimator.profile?.calibrationConfidence ?? 0
            )
            latestTipConfidence = resolution.confidence
            latestTipStatus = resolution.status
            detectedToolPose = resolution.detectedPose
        }

        publishSnapshot()
    }

    private func clearFrozenTipEstimate() {
        isTipEstimateFrozen = false
        frozenTipWorldPosition = nil
        frozenManualTipOffsetBaselineInHandSpace = nil
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
            if isTipEstimateFrozen, let frozenTipWorldPosition {
                latestTipWorldPosition = frozenTipWorldPosition
                latestTipConfidence = min(latestTipConfidence, 0.15)
                latestTipStatus = "Frozen tip marker is holding position."
            } else if latestTipWorldPosition != nil {
                latestTipConfidence = min(latestTipConfidence, 0.15)
                latestTipStatus = "Holding last tip estimate."
            } else {
                latestTipConfidence = 0
                latestTipStatus = "Waiting for selected hand."
                detectedToolPose = nil
            }
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        selectedHandSeenRecently = false
        lastSelectedHandObservationAt = nil
        latestThumbWorldPosition = nil
        latestThumbWorldDirection = nil
        if isTipEstimateFrozen, let frozenTipWorldPosition {
            latestTipWorldPosition = frozenTipWorldPosition
            latestTipConfidence = 0
            latestTipStatus = "Frozen tip marker is waiting for the selected hand."
        } else {
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Waiting for selected hand."
        }
        latestTipHandPose = nil
        detectedToolPose = nil
        latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())

        if pipetteHandedness != nil,
           pipetteCalibrationState.isComplete == false,
           pipetteCalibrationState.step != .handNotSelected,
           pipetteCalibrationState.step != .adjustingTip {
            pipetteCalibrationState.step = .waitingForHand
        }

        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    private func handleSelectedHandObservationDropout() {
        guard shouldTreatSelectedHandAsLost(at: Date()) else {
            selectedHandSeenRecently = true
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            if isTipEstimateFrozen, let frozenTipWorldPosition {
                latestTipWorldPosition = frozenTipWorldPosition
                latestTipConfidence = min(latestTipConfidence, 0.15)
                latestTipStatus = "Frozen tip marker is holding position."
            } else if latestTipWorldPosition != nil {
                latestTipConfidence = min(latestTipConfidence, 0.15)
                latestTipStatus = "Holding last tip estimate."
            } else {
                latestTipConfidence = 0
                latestTipStatus = "Waiting for visible grip landmarks."
                detectedToolPose = nil
            }
            updatePipetteTrackingStatus()
            publishSnapshot()
            return
        }

        handleSelectedHandLoss()
    }

    private func finishPressCalibration() {
        guard let restTipDirection = averagedDirection(restTipDirectionSamples) else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Could not estimate the pipette shaft direction. Keep the thumb and fingertips visible while calibrating."
            latestThumbWorldPosition = nil
            latestThumbWorldDirection = nil
            latestTipWorldPosition = nil
            latestTipConfidence = 0
            latestTipStatus = "Tip tracking is idle."
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
            return
        }

        guard let profile = PipetteCalibrationProfile.build(
            restSamples: restCalibrationSamples,
            pressedSamples: pressedCalibrationSamples,
            restAxialSamples: restButtonTravelSamples,
            pressedAxialSamples: pressedButtonTravelSamples,
            pressAxisHint: restTipDirection
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

        guard let tipProfile = PipetteTipEstimatorProfile.build(
                from: profile,
                tipDirectionInHandSpace: restTipDirection,
                tipLength: 0.18
        ) else {
            pipetteCalibrationState.step = .failed
            pipetteCalibrationState.errorMessage = "Could not initialize grip-based pipette tip tracking."
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
        clearFrozenTipEstimate()
        pipetteCalibrationState.step = .adjustingTip
        pipetteCalibrationState.errorMessage = nil
        latestTipStatus = "Move the red tip marker onto the real pipette tip."
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

        guard let grip = visibleGripCluster(in: handSkeleton, thumbLocalPoint: thumbPadLocalPoint),
              grip.confidence >= 0.20 else {
            return nil
        }

        let tipWorldDirection = worldDirection(
            forAnchorDirection: grip.tipDirectionInHandSpace,
            anchorTransform: anchor.originFromAnchorTransform
        )
        let thumbRelativePosition = thumbPadLocalPoint - grip.center
        let buttonTravelPosition = simd_dot(thumbRelativePosition, grip.tipDirectionInHandSpace)

        return PipetteHandObservation(
            thumbLocalPosition: thumbPadLocalPoint,
            thumbRelativePosition: thumbRelativePosition,
            buttonTravelPosition: buttonTravelPosition,
            thumbWorldPosition: thumbPadWorldPoint,
            thumbWorldDirection: tipWorldDirection,
            tipDirectionInHandSpace: grip.tipDirectionInHandSpace,
            handPose: PipetteHandPose(
                originFromAnchorTransform: anchor.originFromAnchorTransform,
                gripReferencePosition: grip.shaftReference,
                tipDirectionInHandSpace: grip.tipDirectionInHandSpace
            ),
            gripConfidence: grip.confidence
        )
    }

    @available(visionOS 2.0, *)
    private func makePipetteGripObservation(from anchor: HandAnchor) -> PipetteGripObservation? {
        guard anchor.isTracked, let handSkeleton = anchor.handSkeleton else {
            return nil
        }

        let thumbLocalPoint = thumbTrackingPoint(in: handSkeleton)
        guard let grip = visibleGripCluster(in: handSkeleton, thumbLocalPoint: thumbLocalPoint),
              grip.confidence >= 0.20 else {
            return nil
        }

        return PipetteGripObservation(
            handPose: PipetteHandPose(
                originFromAnchorTransform: anchor.originFromAnchorTransform,
                gripReferencePosition: grip.shaftReference,
                tipDirectionInHandSpace: grip.tipDirectionInHandSpace
            ),
            gripConfidence: grip.confidence
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
            .thumbIntermediateBase,
            .thumbKnuckle
        ]
        return fallbackJoints
    }

    @available(visionOS 2.0, *)
    private func thumbTrackingPoint(
        using positionForJoint: (HandSkeleton.JointName) -> SIMD3<Float>?
    ) -> SIMD3<Float>? {
        if let tip = positionForJoint(.thumbTip),
           let intermediate = positionForJoint(.thumbIntermediateTip),
           let base = positionForJoint(.thumbIntermediateBase) {
            return tip * 0.60 + intermediate * 0.30 + base * 0.10
        }

        if let tip = positionForJoint(.thumbTip),
           let intermediate = positionForJoint(.thumbIntermediateTip) {
            return tip * 0.70 + intermediate * 0.30
        }

        for joint in thumbTrackingJoints {
            if let position = positionForJoint(joint) {
                return position
            }
        }

        return nil
    }

    @available(visionOS 2.0, *)
    private func visibleGripCluster(
        in skeleton: HandSkeleton,
        thumbLocalPoint: SIMD3<Float>?
    ) -> PipetteVisibleGrip? {
        let orderedGripJoints: [HandSkeleton.JointName] = [
            .indexFingerTip,
            .middleFingerTip,
            .ringFingerTip,
            .littleFingerTip
        ]
        let orderedPoints = orderedGripJoints.compactMap { jointLocalPosition($0, in: skeleton) }
        let points = orderedPoints
        guard points.count >= 2 else {
            return nil
        }

        let center = points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
        let spread = points
            .map { simd_distance($0, center) }
            .reduce(0, +) / Float(points.count)
        let visibilityConfidence = Float(points.count) / Float(orderedGripJoints.count)
        let spreadConfidence: Float = spread < 0.006 ? 0.45 : 1

        guard let shaftDirection = pipetteShaftDirection(
            orderedFingerTips: orderedPoints,
            thumbLocalPoint: thumbLocalPoint,
            gripCenter: center
        ) else {
            return nil
        }

        let thumbBase = jointLocalPosition(.thumbIntermediateBase, in: skeleton) ?? thumbLocalPoint
        let shaftReference = thumbBase.map { $0 * 0.65 + center * 0.35 } ?? center
        return PipetteVisibleGrip(
            center: center,
            shaftReference: shaftReference,
            tipDirectionInHandSpace: shaftDirection,
            confidence: min(1, visibilityConfidence * spreadConfidence)
        )
    }

    private func pipetteShaftDirection(
        orderedFingerTips: [SIMD3<Float>],
        thumbLocalPoint: SIMD3<Float>?,
        gripCenter: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let fallbackDirection = thumbLocalPoint.flatMap { thumbLocalPoint in
            normalizedDirection(gripCenter - thumbLocalPoint)
        }
        guard orderedFingerTips.count >= 3 else {
            return fallbackDirection
        }

        let upperCount = orderedFingerTips.count / 2
        let upperPoints = Array(orderedFingerTips.prefix(max(1, upperCount)))
        let lowerPoints = Array(orderedFingerTips.suffix(max(1, orderedFingerTips.count - upperCount)))
        let upperCenter = average(upperPoints)
        let lowerCenter = average(lowerPoints)

        guard var shaftDirection = normalizedDirection(lowerCenter - upperCenter) else {
            return fallbackDirection
        }

        if let fallbackDirection, simd_dot(shaftDirection, fallbackDirection) < 0 {
            shaftDirection = -shaftDirection
        } else if fallbackDirection == nil,
                  let profile = pipetteTipEstimator.profile,
                  simd_dot(shaftDirection, profile.tipDirectionInHandSpace) < 0 {
            shaftDirection = -shaftDirection
        }

        if let fallbackDirection {
            return normalizedDirection(shaftDirection * 0.95 + fallbackDirection * 0.05)
        }

        return shaftDirection
    }

    private func average(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard points.isEmpty == false else { return .zero }
        return points.reduce(SIMD3<Float>.zero, +) / Float(points.count)
    }

    private func normalizedDirection(_ direction: SIMD3<Float>) -> SIMD3<Float>? {
        let lengthSquared = simd_length_squared(direction)
        guard lengthSquared > 0.000001 else {
            return nil
        }

        return direction / sqrt(lengthSquared)
    }

    private func worldDirection(
        forAnchorDirection anchorDirection: SIMD3<Float>,
        anchorTransform: simd_float4x4
    ) -> SIMD3<Float> {
        (anchorTransform * SIMD4<Float>(anchorDirection, 0)).xyz
    }

    private func averagedDirection(_ samples: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard samples.isEmpty == false else { return nil }
        let average = samples.reduce(SIMD3<Float>.zero, +) / Float(samples.count)
        let lengthSquared = simd_length_squared(average)
        guard lengthSquared > 0.000001 else { return nil }
        return average / sqrt(lengthSquared)
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
    private func loadReferenceObjects(from urls: [URL]) async throws -> [LoadedReferenceObject] {
        var loadedObjects: [LoadedReferenceObject] = []
        var assignedPlates: [PlateID] = []

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let plate = plateID(forReferenceObjectFileName: url.lastPathComponent),
                  assignedPlates.contains(plate) == false else {
                continue
            }

            do {
                let referenceObject = try await loadBundledReferenceObject(from: url)
                loadedObjects.append(LoadedReferenceObject(
                    object: referenceObject,
                    fileName: url.lastPathComponent,
                    plate: plate
                ))
                assignedPlates.append(plate)
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
    private func assignReferenceObjects(_ referenceObjects: [LoadedReferenceObject]) {
        referenceObjectAssignments = [:]

        for referenceObject in referenceObjects {
            referenceObjectAssignments[referenceObject.object.id] = referenceObject.plate
        }
    }

    private func plateID(forReferenceObjectFileName fileName: String) -> PlateID? {
        let normalizedFileName = fileName.lowercased()

        if normalizedFileName.contains("destination") || normalizedFileName.contains("dest") {
            return .destination
        }

        if normalizedFileName.contains("source") {
            return .source
        }

        return nil
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

    private static var manualTipOffsetDefaultsKey: String {
        "PipetteManualTipOffsetInHandSpace"
    }

    private static func loadSavedManualTipOffset() -> SIMD3<Float> {
        let values = UserDefaults.standard.array(forKey: manualTipOffsetDefaultsKey) as? [Double]
        guard let values, values.count == 3 else {
            return .zero
        }

        return SIMD3<Float>(
            Float(values[0]),
            Float(values[1]),
            Float(values[2])
        )
    }

    private func saveManualTipOffset(_ offset: SIMD3<Float>) {
        UserDefaults.standard.set(
            [Double(offset.x), Double(offset.y), Double(offset.z)],
            forKey: Self.manualTipOffsetDefaultsKey
        )
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
                tipOffsetDistance: simd_length(manualTipOffsetInHandSpace),
                isPressed: latestPipetteOutput.isPressed,
                pressBeganAt: latestPipetteOutput.pressBeganAt,
                pressEndedAt: latestPipetteOutput.pressEndedAt,
                pressCount: latestPipetteOutput.pressCount,
                currentTravel: latestPipetteOutput.smoothedTravel,
                isTipEstimateFrozen: isTipEstimateFrozen,
                activeButton: latestPipetteOutput.activeButton,
                releasedButton: latestPipetteOutput.releasedButton,
                activeButtonSource: latestPipetteOutput.activeButtonSource,
                releasedButtonSource: latestPipetteOutput.releasedButtonSource
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
