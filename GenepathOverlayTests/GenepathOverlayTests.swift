//
//  GenepathOverlayTests.swift
//  GenepathOverlayTests
//
//  Created by Ethan on 17/3/2026.
//

import Testing
@testable import GenepathOverlay
import Foundation
import simd

struct GenepathOverlayTests {
    @Test func csvParserBuildsStructuredSteps() throws {
        let parser = CSVParser(coordinateMapper: CoordinateMapper())
        let csv = """
        source,destination,volume
        A1,B2,50
        H12,C3,20
        """

        let steps = try parser.parse(csv: csv)

        #expect(steps.count == 2)
        #expect(steps[0].source.well == "A1")
        #expect(steps[0].destination.well == "B2")
        #expect(steps[0].volume == 50)
        #expect(steps[1].source.well == "H12")
    }

    @Test func coordinateMapperMapsPlateCorners() throws {
        let mapper = CoordinateMapper()

        let topLeft = try mapper.coordinate(for: .source, well: "A1")
        let bottomRight = try mapper.coordinate(for: .destination, well: "H12")

        #expect(topLeft.row == 0)
        #expect(topLeft.column == 0)
        #expect(bottomRight.row == 7)
        #expect(bottomRight.column == 11)
        #expect(topLeft.normalizedPosition.x > bottomRight.normalizedPosition.x)
        #expect(topLeft.normalizedPosition.z > bottomRight.normalizedPosition.z)
    }

    @Test func coordinateMapperBuildsCompleteWellLayout() throws {
        let mapper = CoordinateMapper()

        let sourceCoordinates = mapper.allCoordinates(for: .source)

        #expect(sourceCoordinates.count == 96)
        #expect(Set(sourceCoordinates.map(\.well)).count == 96)
        #expect(sourceCoordinates.first?.well == "A1")
        #expect(sourceCoordinates.last?.well == "H12")

        let a2 = try mapper.coordinate(for: .source, well: "A2")
        let b1 = try mapper.coordinate(for: .source, well: "B1")
        let a1 = try mapper.coordinate(for: .source, well: "A1")

        #expect(abs((a1.normalizedPosition.x - a2.normalizedPosition.x) - mapper.plateLayout.columnSpacing) < 0.0001)
        #expect(abs((a1.normalizedPosition.z - b1.normalizedPosition.z) - mapper.plateLayout.rowSpacing) < 0.0001)
    }

    @Test func sequenceEngineAdvancesAcrossAspirationAndDispense() throws {
        let mapper = CoordinateMapper()
        let source = try mapper.coordinate(for: .source, well: "A1")
        let destination = try mapper.coordinate(for: .destination, well: "B2")
        let step = Step(sequenceNumber: 1, source: source, destination: destination, volume: 25)

        var engine = SequenceEngine()
        engine.load(steps: [step])

        #expect(engine.currentPhase == .aspiration)
        _ = engine.advance()
        #expect(engine.currentPhase == .dispense)
        let nextStep = engine.advance()
        #expect(nextStep == nil)
    }

    @Test func pipetteCalibrationBuildsThresholdsFromRestAndPressSamples() {
        let restSamples = Array(repeating: SIMD3<Float>(0, 0, 0), count: 12)
        let pressedSamples = Array(repeating: SIMD3<Float>(0, 0, 0.01), count: 12)

        let profile = PipetteCalibrationProfile.build(restSamples: restSamples, pressedSamples: pressedSamples)

        #expect(profile != nil)
        #expect(profile?.pressThreshold ?? 0 > profile?.releaseThreshold ?? 0)
        #expect(abs((profile?.travel(for: SIMD3<Float>(0, 0, 0.01)) ?? 0) - 0.01) < 0.0001)
    }

    @Test func pipettePressClassifierCountsOnlyRisingEdges() {
        var classifier = PipettePressClassifier(smoothingSampleCount: 1, consecutiveSamplesRequired: 2, minimumGripConfidence: 0.55)
        let profile = PipetteCalibrationProfile(
            restThumbPosition: .zero,
            pressedThumbPosition: SIMD3<Float>(0, 0, 0.01),
            pressDirection: SIMD3<Float>(0, 0, 1),
            pressThreshold: 0.0065,
            releaseThreshold: 0.0035
        )
        classifier.setCalibration(profile)

        let start = Date()
        _ = classifier.update(travel: 0.0, gripConfidence: 0.9, timestamp: start)
        _ = classifier.update(travel: 0.008, gripConfidence: 0.9, timestamp: start.addingTimeInterval(0.1))
        let pressed = classifier.update(travel: 0.009, gripConfidence: 0.9, timestamp: start.addingTimeInterval(0.2))
        let held = classifier.update(travel: 0.01, gripConfidence: 0.9, timestamp: start.addingTimeInterval(0.3))
        _ = classifier.update(travel: 0.002, gripConfidence: 0.9, timestamp: start.addingTimeInterval(0.4))
        let released = classifier.update(travel: 0.001, gripConfidence: 0.9, timestamp: start.addingTimeInterval(0.5))

        #expect(pressed.isPressed)
        #expect(pressed.pressCount == 1)
        #expect(held.pressCount == 1)
        #expect(released.isPressed == false)
        #expect(released.pressCount == 1)
        #expect(released.pressEndedAt != nil)
    }

    @Test func pipettePressClassifierIgnoresInputWithoutCalibration() {
        var classifier = PipettePressClassifier(smoothingSampleCount: 1, consecutiveSamplesRequired: 1, minimumGripConfidence: 0.55)
        let output = classifier.update(travel: 0.02, gripConfidence: 0.95, timestamp: Date())

        #expect(output.isPressed == false)
        #expect(output.pressCount == 0)
        #expect(output.smoothedTravel == nil)
    }

    @Test func pipettePressClassifierReleasesWhenGripIsLost() {
        var classifier = PipettePressClassifier(smoothingSampleCount: 1, consecutiveSamplesRequired: 1, minimumGripConfidence: 0.55)
        let profile = PipetteCalibrationProfile(
            restThumbPosition: .zero,
            pressedThumbPosition: SIMD3<Float>(0, 0, 0.01),
            pressDirection: SIMD3<Float>(0, 0, 1),
            pressThreshold: 0.0065,
            releaseThreshold: 0.0035
        )
        classifier.setCalibration(profile)

        let start = Date()
        _ = classifier.update(travel: 0.008, gripConfidence: 0.9, timestamp: start)
        let output = classifier.update(travel: 0.008, gripConfidence: 0.1, timestamp: start.addingTimeInterval(0.1))

        #expect(output.isPressed == false)
        #expect(output.pressCount == 1)
        #expect(output.pressEndedAt != nil)
    }

    @Test func pipetteTipEstimatorUsesThumbReferenceWithoutPalmJoints() throws {
        let pressProfile = PipetteCalibrationProfile(
            restThumbPosition: .zero,
            pressedThumbPosition: SIMD3<Float>(0, -0.01, 0),
            pressDirection: SIMD3<Float>(0, -1, 0),
            pressThreshold: 0.0065,
            releaseThreshold: 0.0035
        )
        let profile = try #require(PipetteTipEstimatorProfile.build(from: pressProfile))
        var estimator = PipetteTipEstimator(smoothingSampleCount: 1)
        estimator.setProfile(profile)

        let thumbReference = SIMD3<Float>(0.03, 0.01, -0.02)
        let handPose = PipetteHandPose(
            originFromAnchorTransform: simd_float4x4(translation: SIMD3<Float>(0.2, 0.9, -0.6)),
            gripReferencePosition: thumbReference
        )

        let estimatedTip = estimator.estimateTipWorldPosition(for: handPose)
        let tip = try #require(estimatedTip)
        let expectedTip = handPose.worldPosition(forAnchorPosition: thumbReference + profile.tipOffsetInHandSpace)

        #expect(simd_distance(tip, expectedTip) < 0.0001)
        #expect(abs(simd_length(profile.tipOffsetInHandSpace) - 0.25) < 0.0001)
    }

    @Test func pipetteTipResolverDetectsNearestWellFromWorldTip() throws {
        let mapper = CoordinateMapper()
        let resolver = PipetteTipWellResolver()
        let a1 = try mapper.coordinate(for: .source, well: "A1")
        let sourceAnchor = testAnchor(for: .source, mapper: mapper)
        let tipWorldPosition = (sourceAnchor.transform * SIMD4<Float>(a1.normalizedPosition + SIMD3<Float>(0.001, 0.002, 0.001), 1)).xyz

        let resolution = resolver.resolve(
            tipWorldPosition: tipWorldPosition,
            plateAnchors: [.source: sourceAnchor],
            coordinateMapper: mapper,
            calibrationConfidence: 0.9
        )

        #expect(resolution.detectedPose != nil)
        #expect(resolution.closestCoordinate?.well == "A1")
        #expect(resolution.detectedPose?.plate == .source)
        #expect((resolution.detectedPose?.confidence ?? 0) >= 0.55)
    }

    @Test func pipetteTipResolverRejectsTipBetweenWells() throws {
        let mapper = CoordinateMapper()
        let resolver = PipetteTipWellResolver()
        let a1 = try mapper.coordinate(for: .source, well: "A1")
        let sourceAnchor = testAnchor(for: .source, mapper: mapper)
        let betweenWells = a1.normalizedPosition + SIMD3<Float>(-0.0048, 0, -0.0048)
        let tipWorldPosition = (sourceAnchor.transform * SIMD4<Float>(betweenWells, 1)).xyz

        let resolution = resolver.resolve(
            tipWorldPosition: tipWorldPosition,
            plateAnchors: [.source: sourceAnchor],
            coordinateMapper: mapper,
            calibrationConfidence: 0.9
        )

        #expect(resolution.detectedPose == nil)
        #expect(resolution.closestCoordinate != nil)
    }

    @Test func pipetteTipResolverRejectsTipTooHighAbovePlate() throws {
        let mapper = CoordinateMapper()
        let resolver = PipetteTipWellResolver()
        let a1 = try mapper.coordinate(for: .source, well: "A1")
        let sourceAnchor = testAnchor(for: .source, mapper: mapper)
        let highTip = a1.normalizedPosition + SIMD3<Float>(0, 0.05, 0)
        let tipWorldPosition = (sourceAnchor.transform * SIMD4<Float>(highTip, 1)).xyz

        let resolution = resolver.resolve(
            tipWorldPosition: tipWorldPosition,
            plateAnchors: [.source: sourceAnchor],
            coordinateMapper: mapper,
            calibrationConfidence: 0.9
        )

        #expect(resolution.detectedPose == nil)
        #expect(resolution.status.contains("well plane"))
    }

    @Test func validationAcceptsHandExtrapolatedDetectedPose() throws {
        let mapper = CoordinateMapper()
        let expected = try mapper.coordinate(for: .source, well: "A1")
        let detected = DetectedToolPose(
            plate: .source,
            position: expected.normalizedPosition + SIMD3<Float>(0.001, 0, 0.001),
            confidence: 0.88
        )
        let result = ValidationEngine(wellTolerance: 0.0045).validate(
            detectedPose: detected,
            expectedCoordinate: expected,
            trackingStatus: .tracking
        )

        if case .correct = result {
            #expect(true)
        } else {
            #expect(Bool(false))
        }
    }

    private func testAnchor(for plate: PlateID, mapper: CoordinateMapper) -> PlateAnchorState {
        PlateAnchorState(
            plate: plate,
            transform: mapper.plateWorldTransform(for: plate),
            position: mapper.plateWorldPosition(for: plate),
            localBoundsCenter: mapper.plateOutlineCenter(for: plate),
            localBoundsExtent: mapper.plateOutlineExtent(for: plate),
            confidence: 0.96
        )
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}
