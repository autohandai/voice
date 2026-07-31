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

public enum HistoryStoreError: Error, Equatable, LocalizedError {
    case fileTooLarge
    case itemTooLarge

    public var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The local history file exceeds its storage limit."
        case .itemTooLarge:
            "This transcript is too large for local history."
        }
    }
}

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let text: String
    public let createdAt: Date
    public var outcome: HistoryOutcome
    public let rawFinal: RawFinalTranscript?
    public let revision: TranscriptRevision?
    public let languageCode: String?
    public let duration: TimeInterval?
    public var failureCategory: VoiceFailureCategory?

    public init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date,
        outcome: HistoryOutcome,
        rawFinal: RawFinalTranscript? = nil,
        revision: TranscriptRevision? = nil,
        languageCode: String? = nil,
        duration: TimeInterval? = nil,
        failureCategory: VoiceFailureCategory? = nil
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.outcome = outcome
        self.rawFinal = rawFinal
        self.revision = revision
        self.languageCode = languageCode
        self.duration = duration.map { min(max($0, 0), 1_200) }
        self.failureCategory = failureCategory
    }

    public func matches(_ query: String) -> Bool {
        query.isEmpty || text.localizedCaseInsensitiveContains(query)
    }
}

public struct HistoryStore: Sendable {
    public static let maximumFileBytes = 4 * 1_024 * 1_024
    public let url: URL

    public init(url: URL = Brand.historyURL) {
        self.url = url
    }

    public func load(
        now: Date = Date(),
        retentionDays: Int = 30,
        maximumItems: Int = 500,
        maximumBytes: Int = Self.maximumFileBytes
    ) throws -> [HistoryEntry] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let fileSize = (
            try FileManager.default.attributesOfItem(
                atPath: url.path
            )[.size] as? NSNumber
        )?.intValue ?? 0
        guard fileSize <= Self.maximumFileBytes else {
            throw HistoryStoreError.fileTooLarge
        }
        let entries = try JSONDecoder.history.decode(
            [HistoryEntry].self,
            from: Data(contentsOf: url)
        )
        let pruned = Self.prune(
            entries,
            now: now,
            retentionDays: retentionDays,
            maximumItems: maximumItems,
            maximumBytes: maximumBytes
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
        maximumItems: Int = 500,
        maximumBytes: Int = Self.maximumFileBytes,
        rawFinal: RawFinalTranscript? = nil,
        revision: TranscriptRevision? = nil,
        duration: TimeInterval? = nil,
        failureCategory: VoiceFailureCategory? = nil
    ) throws -> HistoryEntry {
        let entry = HistoryEntry(
            text: text,
            createdAt: date,
            outcome: outcome,
            rawFinal: rawFinal,
            revision: revision,
            languageCode: rawFinal?.languageCode,
            duration: duration,
            failureCategory: failureCategory
        )
        let entryBytes = try JSONEncoder.history.encode([entry]).count
        guard entryBytes <= min(
            max(1_024, maximumBytes),
            Self.maximumFileBytes
        ) else {
            throw HistoryStoreError.itemTooLarge
        }
        var entries = try load(
            now: date,
            retentionDays: retentionDays,
            maximumItems: maximumItems,
            maximumBytes: maximumBytes
        )
        entries.insert(entry, at: 0)
        try save(
            Self.prune(
                entries,
                now: date,
                retentionDays: retentionDays,
                maximumItems: maximumItems,
                maximumBytes: maximumBytes
            )
        )
        return entry
    }

    public func updateOutcome(
        id: UUID,
        outcome: HistoryOutcome,
        failureCategory: VoiceFailureCategory? = nil
    ) throws {
        var entries = try load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        entries[index].outcome = outcome
        entries[index].failureCategory = failureCategory
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
        maximumItems: Int,
        maximumBytes: Int
    ) -> [HistoryEntry] {
        let cutoff = now.addingTimeInterval(
            -TimeInterval(max(1, retentionDays)) * 86_400
        )
        var result = entries
            .filter { $0.createdAt >= cutoff }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(1, maximumItems))
            .map { $0 }
        let byteLimit = min(
            max(1_024, maximumBytes),
            Self.maximumFileBytes
        )
        while
            !result.isEmpty,
            (try? JSONEncoder.history.encode(result).count)
                .map({ $0 > byteLimit }) == true
        {
            result.removeLast()
        }
        return result
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
