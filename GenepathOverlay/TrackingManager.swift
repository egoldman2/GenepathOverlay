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

    private struct HandFrame {
        let origin: SIMD3<Float>
        let xAxis: SIMD3<Float>
        let yAxis: SIMD3<Float>
        let zAxis: SIMD3<Float>

        func localCoordinates(of worldPoint: SIMD3<Float>) -> SIMD3<Float> {
            let delta = worldPoint - origin
            return SIMD3<Float>(
                simd_dot(delta, xAxis),
                simd_dot(delta, yAxis),
                simd_dot(delta, zAxis)
            )
        }
    }

    private struct PipetteHandObservation {
        let thumbLocalPosition: SIMD3<Float>
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

    private var pipetteHandedness: PipetteHandedness?
    private var pipetteCalibrationState = PipetteCalibrationState.idle
    private var pipetteTrackingStatus: PipetteInputTrackingStatus = .waitingForImmersiveSpace
    private var pipettePressClassifier = PipettePressClassifier()
    private var restCalibrationSamples: [SIMD3<Float>] = []
    private var pressedCalibrationSamples: [SIMD3<Float>] = []
    private var latestPipetteOutput = PipettePressClassifier.Output()

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
        latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
        updatePipetteTrackingStatus()
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
        latestPipetteOutput = PipettePressClassifier.Output()
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
        pipetteCalibrationState.pressedSampleCount = 0
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
        latestPipetteOutput = PipettePressClassifier.Output()
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

            trackingStatus = .searching("Object tracking is running. Look directly at the source plate to detect the reference object.")
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

        updatePipetteTrackingStatus()
        publishSnapshot()
    }

    private func handleSelectedHandLoss() {
        selectedHandSeenRecently = false
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
            latestPipetteOutput = pipettePressClassifier.clearSignal(at: Date())
            return
        }

        pipettePressClassifier.setCalibration(profile)
        latestPipetteOutput = PipettePressClassifier.Output()
        pipetteCalibrationState.step = .complete
        pipetteCalibrationState.errorMessage = nil
    }

    @available(visionOS 2.0, *)
    private func makePipetteHandObservation(from anchor: HandAnchor) -> PipetteHandObservation? {
        guard anchor.isTracked, let handSkeleton = anchor.handSkeleton else {
            return nil
        }

        guard
            let wrist = jointPosition(.forearmWrist, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let indexKnuckle = jointPosition(.indexFingerKnuckle, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let littleKnuckle = jointPosition(.littleFingerKnuckle, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let thumbTip = jointPosition(.thumbTip, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let indexTip = jointPosition(.indexFingerTip, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let middleKnuckle = jointPosition(.middleFingerKnuckle, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let middleTip = jointPosition(.middleFingerTip, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let ringKnuckle = jointPosition(.ringFingerKnuckle, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let ringTip = jointPosition(.ringFingerTip, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform),
            let littleTip = jointPosition(.littleFingerTip, in: handSkeleton, anchorTransform: anchor.originFromAnchorTransform)
        else {
            return nil
        }

        guard let handFrame = makeHandFrame(wrist: wrist, indexKnuckle: indexKnuckle, littleKnuckle: littleKnuckle) else {
            return nil
        }

        let gripConfidence = average([
            gripScore(wrist: wrist, knuckle: indexKnuckle, tip: indexTip),
            gripScore(wrist: wrist, knuckle: middleKnuckle, tip: middleTip),
            gripScore(wrist: wrist, knuckle: ringKnuckle, tip: ringTip),
            gripScore(wrist: wrist, knuckle: littleKnuckle, tip: littleTip)
        ])

        return PipetteHandObservation(
            thumbLocalPosition: handFrame.localCoordinates(of: thumbTip),
            gripConfidence: gripConfidence
        )
    }

    private func makeHandFrame(
        wrist: SIMD3<Float>,
        indexKnuckle: SIMD3<Float>,
        littleKnuckle: SIMD3<Float>
    ) -> HandFrame? {
        let knuckleCenter = (indexKnuckle + littleKnuckle) * 0.5
        var zAxis = knuckleCenter - wrist
        let xReference = indexKnuckle - littleKnuckle

        guard simd_length_squared(zAxis) > 0.000001, simd_length_squared(xReference) > 0.000001 else {
            return nil
        }

        zAxis = simd_normalize(zAxis)
        var yAxis = simd_cross(zAxis, xReference)
        guard simd_length_squared(yAxis) > 0.000001 else {
            return nil
        }

        yAxis = simd_normalize(yAxis)
        let xAxis = simd_normalize(simd_cross(yAxis, zAxis))

        return HandFrame(origin: wrist, xAxis: xAxis, yAxis: yAxis, zAxis: zAxis)
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

    private func gripScore(
        wrist: SIMD3<Float>,
        knuckle: SIMD3<Float>,
        tip: SIMD3<Float>
    ) -> Float {
        let knuckleDistance = max(simd_distance(wrist, knuckle), 0.001)
        let tipDistance = simd_distance(wrist, tip)
        let ratio = tipDistance / knuckleDistance
        return simd_clamp((1.35 - ratio) / 0.55, 0, 1)
    }

    private func average(_ values: [Float]) -> Float {
        guard values.isEmpty == false else { return 0 }
        return values.reduce(0, +) / Float(values.count)
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
                plate = index == 0 ? .source : .destination
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
        var mergedAnchors = basePlateAnchors

        if isTestPlateSimulationEnabled {
            mergedAnchors[.source] = PlateAnchorState(
                plate: .source,
                transform: coordinateMapper.plateWorldTransform(for: .source),
                position: coordinateMapper.plateWorldPosition(for: .source),
                localBoundsCenter: coordinateMapper.plateOutlineCenter(for: .source),
                localBoundsExtent: coordinateMapper.plateOutlineExtent(for: .source),
                confidence: 0.99,
                isSimulated: true
            )
        }

        snapshot = TrackingSnapshot(
            status: trackingStatus,
            plateAnchors: mergedAnchors,
            detectedToolPose: detectedToolPose,
            pipetteInput: PipettePressState(
                selectedHand: pipetteHandedness,
                calibration: pipetteCalibrationState,
                trackingStatus: pipetteTrackingStatus,
                gripConfidence: latestPipetteOutput.gripConfidence,
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
