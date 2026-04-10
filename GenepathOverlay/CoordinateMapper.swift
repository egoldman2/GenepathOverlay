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
    struct PlateLayout: Sendable, Equatable {
        let rows: Int
        let columns: Int
        let rowLabels: [Character]
        let columnSpacing: Float
        let rowSpacing: Float
        let wellYOffset: Float
        let firstWellOffset: SIMD3<Float>
        let plateOutlineExtent: SIMD3<Float>
        let wellHighlightRadius: Float
        let wellHighlightHeight: Float

        var allWellNames: [String] {
            rowLabels.flatMap { rowLabel in
                (1...columns).map { column in
                    "\(rowLabel)\(column)"
                }
            }
        }
    }

    private let rowLabels = Array("ABCDEFGH")
    private let xSpacing: Float = 0.009
    private let zSpacing: Float = 0.009
    private let yOffset: Float = 0.0105
    private let plateOutlineExtentValue = SIMD3<Float>(0.128, 0.015, 0.085)
    private let sourcePlatePosition = SIMD3<Float>(-0.24, 1.02, -0.9)
    private let destinationPlatePosition = SIMD3<Float>(0.24, 1.02, -0.9)

    nonisolated var plateLayout: PlateLayout {
        PlateLayout(
            rows: rowLabels.count,
            columns: 12,
            rowLabels: rowLabels,
            columnSpacing: xSpacing,
            rowSpacing: zSpacing,
            wellYOffset: yOffset,
            firstWellOffset: SIMD3<Float>(-0.0495, yOffset, -0.0315),
            plateOutlineExtent: plateOutlineExtentValue,
            wellHighlightRadius: min(xSpacing, zSpacing) * 0.33,
            wellHighlightHeight: 0.004
        )
    }

    nonisolated func coordinate(for plate: PlateID, well: String) throws -> Coordinate {
        let sanitizedWell = well.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let layout = plateLayout
        guard sanitizedWell.count >= 2,
              let rowCharacter = sanitizedWell.first,
              let rowIndex = layout.rowLabels.firstIndex(of: rowCharacter),
              let column = Int(sanitizedWell.dropFirst()),
              (1...layout.columns).contains(column) else {
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
        plateLayout.plateOutlineExtent
    }

    nonisolated func localPosition(for row: Int, column: Int) -> SIMD3<Float> {
        let layout = plateLayout
        return SIMD3<Float>(
            Float(column) * layout.columnSpacing + layout.firstWellOffset.x,
            layout.wellYOffset,
            Float(row) * layout.rowSpacing + layout.firstWellOffset.z
        )
    }

    nonisolated func allCoordinates(for plate: PlateID) -> [Coordinate] {
        let layout = plateLayout

        return (0..<layout.rows).flatMap { row in
            (0..<layout.columns).map { column in
                Coordinate(
                    plate: plate,
                    well: "\(layout.rowLabels[row])\(column + 1)",
                    row: row,
                    column: column,
                    normalizedPosition: localPosition(for: row, column: column)
                )
            }
        }
    }

    nonisolated func alternateCoordinate(for coordinate: Coordinate) -> Coordinate {
        let layout = plateLayout
        let nextColumn = min(coordinate.column + 1, layout.columns - 1)
        let nextRow = nextColumn == coordinate.column ? min(coordinate.row + 1, layout.rows - 1) : coordinate.row
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
