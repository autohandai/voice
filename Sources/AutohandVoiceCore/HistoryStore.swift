import Foundation

public enum HistoryOutcome: String, Codable, Sendable {
    case inserted
    case insertionFailed = "insertion_failed"

    public var label: String {
        switch self {
        case .inserted: "Inserted"
        case .insertionFailed: "Insertion failed"
        }
    }
}

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public var outcome: HistoryOutcome

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        outcome: HistoryOutcome
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.outcome = outcome
    }

    public func matches(_ query: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }
}

public struct HistoryStore: Sendable {
    public let url: URL

    public init(url: URL = Brand.historyURL) {
        self.url = url
    }

    public func load(
        now: Date = Date(),
        retentionDays: Int = 30,
        maximumItems: Int = 500
    ) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let entries = try JSONDecoder.history.decode(
            [HistoryEntry].self,
            from: Data(contentsOf: url)
        )
        let pruned = Self.prune(
            entries,
            now: now,
            retentionDays: retentionDays,
            maximumItems: maximumItems
        )
        if pruned != entries {
            try save(pruned)
        }
        return pruned
    }

    @discardableResult
    public func append(
        text: String,
        outcome: HistoryOutcome,
        at date: Date = Date(),
        retentionDays: Int = 30,
        maximumItems: Int = 500
    ) throws -> HistoryEntry {
        let entry = HistoryEntry(
            text: text,
            createdAt: date,
            outcome: outcome
        )
        var entries = try load(
            now: date,
            retentionDays: retentionDays,
            maximumItems: maximumItems
        )
        entries.insert(entry, at: 0)
        try save(
            Self.prune(
                entries,
                now: date,
                retentionDays: retentionDays,
                maximumItems: maximumItems
            )
        )
        return entry
    }

    public func updateOutcome(
        id: UUID,
        outcome: HistoryOutcome
    ) throws {
        var entries = try load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].outcome = outcome
        try save(entries)
    }

    public func delete(id: UUID) throws {
        var entries = try load()
        entries.removeAll { $0.id == id }
        try save(entries)
    }

    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func save(_ entries: [HistoryEntry]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.history.encode(entries)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func prune(
        _ entries: [HistoryEntry],
        now: Date,
        retentionDays: Int,
        maximumItems: Int
    ) -> [HistoryEntry] {
        let cutoff = now.addingTimeInterval(
            -TimeInterval(max(1, retentionDays)) * 86_400
        )
        return entries
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(1, maximumItems))
            .map { $0 }
    }
}

private extension JSONEncoder {
    static var history: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var history: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
