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
    private var objectTrackingTask: Task<Void, Never>?
    private var anchorUpdatesTask: Task<Void, Never>?
    private var filters: [PlateID: MovingAverageFilter] = [
        .source: MovingAverageFilter(),
        .destination: MovingAverageFilter()
    ]
    private var referenceObjectAssignments: [UUID: PlateID] = [:]
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
        snapshot.status = .preparing
        snapshot.detectedToolPose = nil
        installPreviewAnchors(message: "Preparing object tracking session.")

        objectTrackingTask = Task { [weak self] in
            guard let self else { return }
            await self.startObjectTrackingIfPossible()
        }
    }

    func stopTracking() {
        objectTrackingTask?.cancel()
        anchorUpdatesTask?.cancel()
        objectTrackingTask = nil
        anchorUpdatesTask = nil
        referenceObjectAssignments = [:]
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

    private func installPreviewAnchors(message: String) {
        var anchors: [PlateID: PlateAnchorState] = snapshot.plateAnchors

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

        snapshot = TrackingSnapshot(
            status: .preview(message),
            plateAnchors: anchors,
            detectedToolPose: snapshot.detectedToolPose
        )
    }

    private func startObjectTrackingIfPossible() async {
        guard #available(visionOS 2.0, *) else {
            installPreviewAnchors(message: "Object tracking requires visionOS 2.0 or newer. Preview anchors are active.")
            return
        }

        guard ObjectTrackingProvider.isSupported else {
            installPreviewAnchors(message: "Object tracking is not supported on this device. Preview anchors are active.")
            return
        }

        do {
            let referenceObjects = try await loadReferenceObjects()
            bundledReferenceObjectNames = referenceObjects.map(\.name)
            guard !referenceObjects.isEmpty else {
                let discoveredFiles = discoveredReferenceObjectFiles.joined(separator: ", ")
                let detail = discoveredFiles.isEmpty
                    ? "No .referenceObject files were found in the app bundle."
                    : "Found bundled files (\(discoveredFiles)) but none could be loaded as ARKit reference objects."
                installPreviewAnchors(message: "\(detail) Preview anchors are active.")
                return
            }

            assignReferenceObjects(referenceObjects)

            let authorization = await session.requestAuthorization(for: ObjectTrackingProvider.requiredAuthorizations)
            if authorization.values.contains(where: { $0 != .allowed }) {
                installPreviewAnchors(message: "World sensing permission was not granted. Preview anchors are active.")
                return
            }

            let provider = ObjectTrackingProvider(referenceObjects: referenceObjects)
            anchorUpdatesTask = Task { [weak self] in
                guard let self else { return }
                await self.consumeObjectAnchorUpdates(from: provider)
            }

            snapshot.status = .searching("Object tracking is running. Look directly at the source plate to detect the reference object.")
            try await session.run([provider])
        } catch {
            installPreviewAnchors(message: "Object tracking failed to start (\(error.localizedDescription)). Preview anchors are active.")
        }
    }

    @available(visionOS 2.0, *)
    private func loadReferenceObjects() async throws -> [ReferenceObject] {
        let urls = referenceObjectURLs()
        discoveredReferenceObjectFiles = urls.map(\.lastPathComponent)
        var loadedObjects: [ReferenceObject] = []

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let referenceObject = try await ReferenceObject(from: url)
                loadedObjects.append(referenceObject)
            } catch {
                continue
            }
        }

        return loadedObjects
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
                snapshot.status = .lowConfidence("Lost tracking for the \(plate.title.lowercased()) plate.")
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

        snapshot.plateAnchors[plate] = PlateAnchorState(
            plate: plate,
            transform: liveTransform,
            position: livePosition,
            localBoundsCenter: anchor.boundingBox.center,
            localBoundsExtent: anchor.boundingBox.extent,
            confidence: confidence
        )

        snapshot.status = anchor.isTracked
            ? .tracking
            : .lowConfidence("Tracking confidence dropped for the \(plate.title.lowercased()) plate.")
    }
}

private extension simd_float4x4 {
    var translation: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
