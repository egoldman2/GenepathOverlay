import Foundation
import simd

enum CoordinateMapperError: LocalizedError {
    case invalidWell(String)

    var errorDescription: String? {
        switch self {
        case .invalidWell(let well):
            return "The well identifier '\(well)' is not valid for a 96-well plate."
        }
    }
}

struct CoordinateMapper: Sendable {
    private let rowLabels = Array("ABCDEFGH")
    private let xSpacing: Float = 0.014
    private let zSpacing: Float = 0.014
    private let yOffset: Float = 0.012
    private let plateOutlineExtent = SIMD3<Float>(0.128, 0.015, 0.085)
    private let sourcePlatePosition = SIMD3<Float>(-0.24, 1.02, -0.9)
    private let destinationPlatePosition = SIMD3<Float>(0.24, 1.02, -0.9)

    nonisolated func coordinate(for plate: PlateID, well: String) throws -> Coordinate {
        let sanitizedWell = well.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard sanitizedWell.count >= 2,
              let rowCharacter = sanitizedWell.first,
              let rowIndex = rowLabels.firstIndex(of: rowCharacter),
              let column = Int(sanitizedWell.dropFirst()),
              (1...12).contains(column) else {
            throw CoordinateMapperError.invalidWell(well)
        }

        return Coordinate(
            plate: plate,
            well: sanitizedWell,
            row: rowIndex,
            column: column - 1,
            normalizedPosition: localPosition(for: rowIndex, column: column - 1)
        )
    }

    nonisolated func plateWorldPosition(for plate: PlateID) -> SIMD3<Float> {
        switch plate {
        case .source:
            return sourcePlatePosition
        case .destination:
            return destinationPlatePosition
        }
    }

    nonisolated func plateWorldTransform(for plate: PlateID) -> simd_float4x4 {
        simd_float4x4(translation: plateWorldPosition(for: plate))
    }

    nonisolated func plateOutlineCenter(for plate: PlateID) -> SIMD3<Float> {
        .zero
    }

    nonisolated func plateOutlineExtent(for plate: PlateID) -> SIMD3<Float> {
        plateOutlineExtent
    }

    nonisolated func localPosition(for row: Int, column: Int) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(column) * xSpacing - 0.077,
            yOffset,
            Float(row) * zSpacing - 0.049
        )
    }

    nonisolated func alternateCoordinate(for coordinate: Coordinate) -> Coordinate {
        let nextColumn = min(coordinate.column + 1, 11)
        let nextRow = nextColumn == coordinate.column ? min(coordinate.row + 1, 7) : coordinate.row
        let rowLabel = rowLabels[nextRow]
        let alternateWell = "\(rowLabel)\(nextColumn + 1)"

        return (try? self.coordinate(for: coordinate.plate, well: alternateWell)) ?? coordinate
    }
}

extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4<Float>(translation.x, translation.y, translation.z, 1)
    }
}
