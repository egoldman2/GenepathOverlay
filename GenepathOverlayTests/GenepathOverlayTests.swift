//
//  GenepathOverlayTests.swift
//  GenepathOverlayTests
//
//  Created by Ethan on 17/3/2026.
//

import Testing
@testable import GenepathOverlay

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
        #expect(topLeft.normalizedPosition.x < bottomRight.normalizedPosition.x)
        #expect(topLeft.normalizedPosition.z < bottomRight.normalizedPosition.z)
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
}
