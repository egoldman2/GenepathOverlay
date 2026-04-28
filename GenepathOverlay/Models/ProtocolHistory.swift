import Foundation

struct ProtocolHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let fileName: String
    let importedAt: Date
    let rows: [ProtocolHistoryRow]

    var stepCount: Int {
        rows.count
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        importedAt: Date = Date(),
        steps: [Step]
    ) {
        self.id = id
        self.fileName = fileName
        self.importedAt = importedAt
        rows = steps.map { step in
            ProtocolHistoryRow(
                sourceWell: step.source.well,
                destinationWell: step.destination.well,
                volume: step.volume
            )
        }
    }

    func makeSteps(using coordinateMapper: CoordinateMapper) throws -> [Step] {
        try rows.enumerated().map { index, row in
            Step(
                sequenceNumber: index + 1,
                source: try coordinateMapper.coordinate(for: .source, well: row.sourceWell),
                destination: try coordinateMapper.coordinate(for: .destination, well: row.destinationWell),
                volume: row.volume
            )
        }
    }

    func matches(fileName: String, steps: [Step]) -> Bool {
        self.fileName == fileName && rows == steps.map { step in
            ProtocolHistoryRow(
                sourceWell: step.source.well,
                destinationWell: step.destination.well,
                volume: step.volume
            )
        }
    }
}

struct ProtocolHistoryRow: Codable, Equatable, Sendable {
    let sourceWell: String
    let destinationWell: String
    let volume: Double
}

struct ProtocolHistoryStore {
    private let storageKey = "GenepathOverlay.ProtocolHistory.v1"
    private let maxEntries = 8

    func load() -> [ProtocolHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return []
        }

        return (try? JSONDecoder().decode([ProtocolHistoryEntry].self, from: data)) ?? []
    }

    func save(_ entries: [ProtocolHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(entries) else {
            return
        }

        UserDefaults.standard.set(data, forKey: storageKey)
    }

    func inserting(fileName: String, steps: [Step], into entries: [ProtocolHistoryEntry]) -> [ProtocolHistoryEntry] {
        let newEntry = ProtocolHistoryEntry(fileName: fileName, steps: steps)
        let existingEntries = entries.filter { $0.matches(fileName: fileName, steps: steps) == false }
        return Array(([newEntry] + existingEntries).prefix(maxEntries))
    }
}
