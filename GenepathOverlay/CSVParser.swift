import Foundation

enum CSVParserError: LocalizedError {
    case emptyFile
    case noTransferRows
    case invalidRow(Int)
    case invalidVolume(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The selected CSV file is empty."
        case .noTransferRows:
            return "The CSV does not contain any transfer rows."
        case .invalidRow(let rowNumber):
            return "Row \(rowNumber) is malformed."
        case .invalidVolume(let rowNumber, let value):
            return "Row \(rowNumber) contains an invalid volume value: \(value)."
        }
    }
}

struct CSVParser: Sendable {
    private let coordinateMapper: CoordinateMapper

    init(coordinateMapper: CoordinateMapper) {
        self.coordinateMapper = coordinateMapper
    }

    nonisolated func parse(fileAt url: URL) throws -> [Step] {
        let rawCSV = try String(contentsOf: url, encoding: .utf8)
        return try parse(csv: rawCSV)
    }

    nonisolated func parse(csv: String) throws -> [Step] {
        let normalizedCSV = csv
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalizedCSV
            .components(separatedBy: "\n")
            .map(sanitizedField)
            .filter { !$0.isEmpty }

        guard let headerLine = lines.first else {
            throw CSVParserError.emptyFile
        }

        let headerColumns = columns(from: headerLine)
        guard headerColumns.count >= 3 else {
            throw CSVParserError.invalidRow(1)
        }

        var steps: [Step] = []

        for (offset, line) in lines.dropFirst().enumerated() {
            let rowNumber = offset + 2
            let row = columns(from: line)
            guard row.count >= 3 else {
                throw CSVParserError.invalidRow(rowNumber)
            }

            let sourceCoordinate = try coordinateMapper.coordinate(
                for: .source,
                well: sanitizedField(row[0])
            )
            let destinationCoordinate = try coordinateMapper.coordinate(
                for: .destination,
                well: sanitizedField(row[1])
            )

            let volumeString = sanitizedField(row[2])
            guard let volume = Double(volumeString) else {
                throw CSVParserError.invalidVolume(rowNumber, volumeString)
            }

            steps.append(
                Step(
                    sequenceNumber: steps.count + 1,
                    source: sourceCoordinate,
                    destination: destinationCoordinate,
                    volume: volume
                )
            )
        }

        guard !steps.isEmpty else {
            throw CSVParserError.noTransferRows
        }

        return steps
    }

    private nonisolated func sanitizedField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated func columns(from line: String) -> [String] {
        line
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { sanitizedField(String($0)) }
    }
}
