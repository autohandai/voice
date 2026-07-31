import CryptoKit
import Foundation
import SQLite3

public struct WorkspaceLimits: Equatable, Sendable {
    public static let current = WorkspaceLimits()

    public let maximumNotes: Int
    public let maximumVersionsPerNote: Int
    public let maximumNoteCharacters: Int
    public let maximumAssetBytes: Int
    public let maximumTotalAssetBytes: Int
    public let maximumSearchResults: Int

    public init(
        maximumNotes: Int = 1_000,
        maximumVersionsPerNote: Int = 100,
        maximumNoteCharacters: Int = 250_000,
        maximumAssetBytes: Int = 10 * 1_024 * 1_024,
        maximumTotalAssetBytes: Int = 500 * 1_024 * 1_024,
        maximumSearchResults: Int = 100
    ) {
        self.maximumNotes = min(max(maximumNotes, 1), 1_000)
        self.maximumVersionsPerNote = min(
            max(maximumVersionsPerNote, 1),
            100
        )
        self.maximumNoteCharacters = min(
            max(maximumNoteCharacters, 1_000),
            250_000
        )
        self.maximumAssetBytes = min(
            max(maximumAssetBytes, 1_024),
            10 * 1_024 * 1_024
        )
        self.maximumTotalAssetBytes = min(
            max(maximumTotalAssetBytes, maximumAssetBytes),
            500 * 1_024 * 1_024
        )
        self.maximumSearchResults = min(
            max(maximumSearchResults, 1),
            100
        )
    }
}

public enum LocalWorkspaceError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case unavailable
    case corrupt
    case quotaExceeded
    case invalidMutation
    case notFound
    case assetRejected
    case migrationVerificationFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            "The local workspace is unavailable."
        case .corrupt:
            "The local workspace could not be read safely."
        case .quotaExceeded:
            "The local workspace reached its storage limit."
        case .invalidMutation:
            "That workspace change is invalid."
        case .notFound:
            "That workspace item no longer exists."
        case .assetRejected:
            "That image exceeds the local Scratchpad limit."
        case .migrationVerificationFailed:
            "Legacy data import did not pass verification."
        }
    }
}

public struct ScratchpadNote:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public var title: String
    public var plainText: String
    public var richTextRTF: Data?
    public var assetHashes: [String]
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        plainText: String = "",
        richTextRTF: Data? = nil,
        assetHashes: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = String(
            title.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(200)
        )
        self.plainText = plainText
        self.richTextRTF = richTextRTF
        var seen: Set<String> = []
        self.assetHashes = assetHashes.filter {
            seen.insert($0).inserted
        }
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ScratchpadVersion:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let noteID: UUID
    public let title: String
    public let plainText: String
    public let richTextRTF: Data?
    public let assetHashes: [String]
    public let createdAt: Date
}

public struct ScratchpadAsset:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: String { hash }
    public let hash: String
    public let mediaType: String
    public let byteCount: Int
}

public enum WorkspaceMutation: Sendable {
    case createNote(ScratchpadNote)
    case updateNote(ScratchpadNote)
    case deleteNote(UUID)
    case restoreVersion(noteID: UUID, versionID: UUID)
    case storeAsset(data: Data, mediaType: String)
}

public enum WorkspaceQuery: Sendable {
    case notes(search: String, limit: Int, offset: Int)
    case note(UUID)
    case versions(noteID: UUID, limit: Int)
    case asset(String)
}

public struct WorkspaceReceipt: Equatable, Sendable {
    public let entityID: String
    public let versionID: UUID?
    public let checksum: String?
}

public struct WorkspacePage: Equatable, Sendable {
    public let notes: [ScratchpadNote]
    public let versions: [ScratchpadVersion]
    public let asset: ScratchpadAsset?

    public init(
        notes: [ScratchpadNote] = [],
        versions: [ScratchpadVersion] = [],
        asset: ScratchpadAsset? = nil
    ) {
        self.notes = notes
        self.versions = versions
        self.asset = asset
    }
}

public enum ErasureScope: Sendable {
    case scratchpad
    case workspace
}

public struct ErasureReport: Equatable, Sendable {
    public let deletedRows: Int
    public let deletedAssets: Int
}

public struct RetentionReport: Equatable, Sendable {
    public let deletedVersions: Int
    public let deletedOrphanAssets: Int
}

public struct LegacyWorkspaceSnapshot: Sendable {
    public let history: [HistoryEntry]
    public let dictionary: [ReplacementRule]
    public let styles: [DictationStylePreset]

    public init(
        history: [HistoryEntry],
        dictionary: [ReplacementRule],
        styles: [DictationStylePreset]
    ) {
        self.history = history
        self.dictionary = dictionary
        self.styles = styles
    }
}

public struct WorkspaceMigrationReport: Equatable, Sendable {
    public let importedHistory: Int
    public let importedDictionary: Int
    public let importedStyles: Int
    public let checksum: String
}

public struct LegacyWorkspaceSourceURLs: Sendable {
    public let history: URL
    public let dictionary: URL
    public let styles: URL

    public init(
        history: URL = Brand.historyURL,
        dictionary: URL = Brand.vocabularyURL,
        styles: URL = Brand.dictationStylesURL
    ) {
        self.history = history
        self.dictionary = dictionary
        self.styles = styles
    }
}

public enum LegacyWorkspaceLoadError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case sourceTooLarge(String)
    case sourceInvalid(String)

    public var errorDescription: String? {
        switch self {
        case let .sourceTooLarge(source):
            "Legacy \(source) exceeds its migration limit."
        case let .sourceInvalid(source):
            "Legacy \(source) could not be validated for migration."
        }
    }
}

public struct ValidatedLegacyWorkspace: Sendable {
    public let snapshot: LegacyWorkspaceSnapshot
    public let sourceChecksum: String
}

public enum LegacyWorkspaceLoader {
    public static func load(
        _ urls: LegacyWorkspaceSourceURLs
    ) throws -> ValidatedLegacyWorkspace {
        let historyData = try read(
            urls.history,
            name: "history",
            maximumBytes: HistoryStore.maximumFileBytes
        )
        let dictionaryData = try read(
            urls.dictionary,
            name: "dictionary",
            maximumBytes: VocabularyLimits.maximumFileBytes
        )
        let stylesData = try read(
            urls.styles,
            name: "styles",
            maximumBytes: DictationStyleStore.maximumFileBytes
        )
        let history: [HistoryEntry] = try decode(
            historyData,
            name: "history",
            configure: {
                $0.dateDecodingStrategy = .iso8601
            }
        )
        let dictionary: [ReplacementRule] = try decode(
            dictionaryData,
            name: "dictionary"
        )
        let styles: [DictationStylePreset] = try decode(
            stylesData,
            name: "styles"
        )
        do {
            try DictationStyleStore.validate(styles)
            guard dictionary.count <= VocabularyLimits.maximumRules else {
                throw LegacyWorkspaceLoadError.sourceInvalid("dictionary")
            }
        } catch let error as LegacyWorkspaceLoadError {
            throw error
        } catch {
            throw LegacyWorkspaceLoadError.sourceInvalid("styles")
        }
        let snapshot = LegacyWorkspaceSnapshot(
            history: history,
            dictionary: dictionary,
            styles: styles
        )
        let aggregate = historyData + dictionaryData + stylesData
        return ValidatedLegacyWorkspace(
            snapshot: snapshot,
            sourceChecksum: SHA256.hash(data: aggregate).map {
                String(format: "%02x", $0)
            }.joined()
        )
    }

    private static func read(
        _ url: URL,
        name: String,
        maximumBytes: Int
    ) throws -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Data("[]".utf8)
        }
        let size = (
            try? FileManager.default.attributesOfItem(
                atPath: url.path
            )[.size] as? NSNumber
        )?.intValue ?? maximumBytes + 1
        guard size <= maximumBytes else {
            throw LegacyWorkspaceLoadError.sourceTooLarge(name)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw LegacyWorkspaceLoadError.sourceInvalid(name)
        }
    }

    private static func decode<T: Decodable>(
        _ data: Data,
        name: String,
        configure: (JSONDecoder) -> Void = { _ in }
    ) throws -> T {
        let decoder = JSONDecoder()
        configure(decoder)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw LegacyWorkspaceLoadError.sourceInvalid(name)
        }
    }
}

public actor LocalWorkspace {
    private static let transient = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    private let databaseURL: URL
    private let assetsDirectory: URL
    private let limits: WorkspaceLimits
    private var database: OpaquePointer?

    public init(
        databaseURL: URL = Brand.workspaceURL,
        assetsDirectory: URL = Brand.scratchpadAssetsDirectory,
        limits: WorkspaceLimits = .current
    ) throws {
        self.databaseURL = databaseURL
        self.assetsDirectory = assetsDirectory
        self.limits = limits
        try Self.prepareParent(for: databaseURL)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &handle,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE
                | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw LocalWorkspaceError.unavailable
        }
        database = handle
        do {
            try Self.execute(handle, sql: "PRAGMA foreign_keys = ON")
            try Self.execute(handle, sql: "PRAGMA journal_mode = WAL")
            try Self.execute(handle, sql: "PRAGMA synchronous = FULL")
            try Self.createSchema(handle)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: databaseURL.path
            )
        } catch {
            sqlite3_close(handle)
            database = nil
            throw error
        }
    }

    deinit {
        sqlite3_close(database)
    }

    public func close() {
        guard let database else { return }
        sqlite3_wal_checkpoint_v2(
            database,
            nil,
            SQLITE_CHECKPOINT_TRUNCATE,
            nil,
            nil
        )
        sqlite3_close_v2(database)
        self.database = nil
    }

    public func apply(
        _ mutation: WorkspaceMutation
    ) throws -> WorkspaceReceipt {
        switch mutation {
        case let .createNote(note):
            try validate(note)
            guard try scalarInt("SELECT COUNT(*) FROM scratchpad_note")
                < limits.maximumNotes else {
                throw LocalWorkspaceError.quotaExceeded
            }
            return try transaction {
                try insertNote(note)
                try upsertSearchIndex(note)
                return WorkspaceReceipt(
                    entityID: note.id.uuidString,
                    versionID: nil,
                    checksum: checksum(note)
                )
            }
        case let .updateNote(note):
            try validate(note)
            return try transaction {
                let current = try requiredNote(note.id)
                let version = try insertVersion(for: current)
                try updateNote(note)
                try upsertSearchIndex(note)
                try trimVersions(noteID: note.id)
                return WorkspaceReceipt(
                    entityID: note.id.uuidString,
                    versionID: version.id,
                    checksum: checksum(note)
                )
            }
        case let .deleteNote(id):
            return try transaction {
                guard try fetchNote(id) != nil else {
                    throw LocalWorkspaceError.notFound
                }
                let statement = try prepare(
                    "DELETE FROM scratchpad_note WHERE id = ?"
                )
                defer { sqlite3_finalize(statement) }
                bind(id.uuidString, at: 1, in: statement)
                try stepDone(statement)
                try deleteSearchIndex(id)
                return WorkspaceReceipt(
                    entityID: id.uuidString,
                    versionID: nil,
                    checksum: nil
                )
            }
        case let .restoreVersion(noteID, versionID):
            return try transaction {
                let current = try requiredNote(noteID)
                _ = try insertVersion(for: current)
                let version = try requiredVersion(
                    noteID: noteID,
                    versionID: versionID
                )
                let restored = ScratchpadNote(
                    id: current.id,
                    title: version.title,
                    plainText: version.plainText,
                    richTextRTF: version.richTextRTF,
                    assetHashes: version.assetHashes,
                    createdAt: current.createdAt,
                    updatedAt: Date()
                )
                try updateNote(restored)
                try upsertSearchIndex(restored)
                try trimVersions(noteID: noteID)
                return WorkspaceReceipt(
                    entityID: noteID.uuidString,
                    versionID: versionID,
                    checksum: checksum(restored)
                )
            }
        case let .storeAsset(data, mediaType):
            return try storeAsset(data: data, mediaType: mediaType)
        }
    }

    public func query(_ query: WorkspaceQuery) throws -> WorkspacePage {
        switch query {
        case let .notes(search, limit, offset):
            return WorkspacePage(
                notes: try fetchNotes(
                    search: search,
                    limit: limit,
                    offset: offset
                )
            )
        case let .note(id):
            return WorkspacePage(notes: try fetchNote(id).map { [$0] } ?? [])
        case let .versions(noteID, limit):
            return WorkspacePage(
                versions: try fetchVersions(
                    noteID: noteID,
                    limit: limit
                )
            )
        case let .asset(hash):
            return WorkspacePage(asset: try fetchAsset(hash))
        }
    }

    public func enforceRetention(
        now _: Date = Date()
    ) throws -> RetentionReport {
        let versionsBefore = try scalarInt(
            "SELECT COUNT(*) FROM scratchpad_version"
        )
        for note in try fetchNotes(
            search: "",
            limit: limits.maximumNotes,
            offset: 0
        ) {
            try trimVersions(noteID: note.id)
        }
        let versionsAfter = try scalarInt(
            "SELECT COUNT(*) FROM scratchpad_version"
        )
        let deletedAssets = try deleteOrphanAssets()
        return RetentionReport(
            deletedVersions: max(0, versionsBefore - versionsAfter),
            deletedOrphanAssets: deletedAssets
        )
    }

    public func erase(_ scope: ErasureScope) throws -> ErasureReport {
        let deletedRows: Int
        switch scope {
        case .scratchpad:
            deletedRows = try scalarInt(
                "SELECT COUNT(*) FROM scratchpad_note"
            ) + scalarInt(
                "SELECT COUNT(*) FROM scratchpad_version"
            )
            try transaction {
                try execute("DELETE FROM scratchpad_note")
                try execute("DELETE FROM scratchpad_note_fts")
            }
        case .workspace:
            deletedRows = try scalarInt(
                "SELECT COUNT(*) FROM scratchpad_note"
            ) + scalarInt(
                "SELECT COUNT(*) FROM scratchpad_version"
            ) + scalarInt(
                "SELECT COUNT(*) FROM history_item"
            ) + scalarInt(
                "SELECT COUNT(*) FROM dictionary_entry"
            ) + scalarInt(
                "SELECT COUNT(*) FROM style"
            )
            try transaction {
                try execute("DELETE FROM scratchpad_note")
                try execute("DELETE FROM scratchpad_note_fts")
                try execute("DELETE FROM history_item")
                try execute("DELETE FROM dictionary_entry")
                try execute("DELETE FROM style")
                try execute("DELETE FROM migration_ledger")
            }
        }
        let deletedAssets = try deleteAllAssets()
        return ErasureReport(
            deletedRows: deletedRows,
            deletedAssets: deletedAssets
        )
    }

    public func importLegacy(
        _ snapshot: LegacyWorkspaceSnapshot,
        sourceName: String
    ) throws -> WorkspaceMigrationReport {
        let encoded = try JSONEncoder.workspace.encode(
            LegacyChecksumPayload(snapshot: snapshot)
        )
        let expectedChecksum = Self.sha256(encoded)
        let source = String(sourceName.prefix(100))
        guard !source.isEmpty else {
            throw LocalWorkspaceError.invalidMutation
        }
        try transaction {
            try execute("DELETE FROM history_item")
            try execute("DELETE FROM dictionary_entry")
            try execute("DELETE FROM style")
            for entry in snapshot.history {
                try insertLegacy(
                    table: "history_item",
                    id: entry.id.uuidString,
                    payload: try JSONEncoder.workspace.encode(entry)
                )
            }
            for rule in snapshot.dictionary {
                try insertLegacy(
                    table: "dictionary_entry",
                    id: rule.id.uuidString,
                    payload: try JSONEncoder.workspace.encode(rule)
                )
            }
            for style in snapshot.styles {
                try insertLegacy(
                    table: "style",
                    id: style.id.uuidString,
                    payload: try JSONEncoder.workspace.encode(style)
                )
            }
            guard
                try scalarInt("SELECT COUNT(*) FROM history_item")
                    == snapshot.history.count,
                try scalarInt("SELECT COUNT(*) FROM dictionary_entry")
                    == snapshot.dictionary.count,
                try scalarInt("SELECT COUNT(*) FROM style")
                    == snapshot.styles.count
            else {
                throw LocalWorkspaceError.migrationVerificationFailed
            }
            let statement = try prepare(
                """
                INSERT OR REPLACE INTO migration_ledger
                    (source, checksum, imported_at)
                VALUES (?, ?, ?)
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(source, at: 1, in: statement)
            bind(expectedChecksum, at: 2, in: statement)
            sqlite3_bind_double(statement, 3, Date().timeIntervalSince1970)
            try stepDone(statement)
        }
        return WorkspaceMigrationReport(
            importedHistory: snapshot.history.count,
            importedDictionary: snapshot.dictionary.count,
            importedStyles: snapshot.styles.count,
            checksum: expectedChecksum
        )
    }

    public func assetData(_ hash: String) throws -> Data {
        guard try fetchAsset(hash) != nil else {
            throw LocalWorkspaceError.notFound
        }
        let url = assetURL(hash)
        guard
            let data = try? Data(contentsOf: url),
            data.count <= limits.maximumAssetBytes,
            Self.sha256(data) == hash
        else {
            throw LocalWorkspaceError.corrupt
        }
        return data
    }

    private func validate(_ note: ScratchpadNote) throws {
        guard
            !note.title.isEmpty,
            note.title.count <= 200,
            note.plainText.count <= limits.maximumNoteCharacters,
            (note.richTextRTF?.count ?? 0)
                <= limits.maximumNoteCharacters * 8,
            note.assetHashes.count <= 100
        else {
            throw LocalWorkspaceError.invalidMutation
        }
        for hash in note.assetHashes {
            guard try fetchAsset(hash) != nil else {
                throw LocalWorkspaceError.invalidMutation
            }
        }
    }

    private func insertNote(_ note: ScratchpadNote) throws {
        let statement = try prepare(
            """
            INSERT INTO scratchpad_note
                (id, title, plain_text, rich_text, asset_hashes,
                 created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        try bind(note, in: statement)
        try stepDone(statement)
    }

    private func updateNote(_ note: ScratchpadNote) throws {
        let statement = try prepare(
            """
            UPDATE scratchpad_note
               SET title = ?, plain_text = ?, rich_text = ?,
                   asset_hashes = ?, updated_at = ?
             WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(note.title, at: 1, in: statement)
        bind(note.plainText, at: 2, in: statement)
        bind(note.richTextRTF, at: 3, in: statement)
        bind(try encode(note.assetHashes), at: 4, in: statement)
        sqlite3_bind_double(
            statement,
            5,
            note.updatedAt.timeIntervalSince1970
        )
        bind(note.id.uuidString, at: 6, in: statement)
        try stepDone(statement)
        guard sqlite3_changes(database) == 1 else {
            throw LocalWorkspaceError.notFound
        }
    }

    private func bind(
        _ note: ScratchpadNote,
        in statement: OpaquePointer?
    ) throws {
        bind(note.id.uuidString, at: 1, in: statement)
        bind(note.title, at: 2, in: statement)
        bind(note.plainText, at: 3, in: statement)
        bind(note.richTextRTF, at: 4, in: statement)
        bind(try encode(note.assetHashes), at: 5, in: statement)
        sqlite3_bind_double(
            statement,
            6,
            note.createdAt.timeIntervalSince1970
        )
        sqlite3_bind_double(
            statement,
            7,
            note.updatedAt.timeIntervalSince1970
        )
    }

    private func insertVersion(
        for note: ScratchpadNote
    ) throws -> ScratchpadVersion {
        let version = ScratchpadVersion(
            id: UUID(),
            noteID: note.id,
            title: note.title,
            plainText: note.plainText,
            richTextRTF: note.richTextRTF,
            assetHashes: note.assetHashes,
            createdAt: Date()
        )
        let statement = try prepare(
            """
            INSERT INTO scratchpad_version
                (id, note_id, title, plain_text, rich_text,
                 asset_hashes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(version.id.uuidString, at: 1, in: statement)
        bind(version.noteID.uuidString, at: 2, in: statement)
        bind(version.title, at: 3, in: statement)
        bind(version.plainText, at: 4, in: statement)
        bind(version.richTextRTF, at: 5, in: statement)
        bind(try encode(version.assetHashes), at: 6, in: statement)
        sqlite3_bind_double(
            statement,
            7,
            version.createdAt.timeIntervalSince1970
        )
        try stepDone(statement)
        return version
    }

    private func trimVersions(noteID: UUID) throws {
        let statement = try prepare(
            """
            DELETE FROM scratchpad_version
             WHERE note_id = ?
               AND id NOT IN (
                   SELECT id FROM scratchpad_version
                    WHERE note_id = ?
                    ORDER BY created_at DESC
                    LIMIT ?
               )
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(noteID.uuidString, at: 1, in: statement)
        bind(noteID.uuidString, at: 2, in: statement)
        sqlite3_bind_int64(
            statement,
            3,
            sqlite3_int64(limits.maximumVersionsPerNote)
        )
        try stepDone(statement)
    }

    private func fetchNotes(
        search: String,
        limit: Int,
        offset: Int
    ) throws -> [ScratchpadNote] {
        let boundedLimit = min(
            max(limit, 1),
            limits.maximumSearchResults
        )
        let statement: OpaquePointer?
        if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            statement = try prepare(
                """
                SELECT id, title, plain_text, rich_text, asset_hashes,
                       created_at, updated_at
                  FROM scratchpad_note
                 ORDER BY updated_at DESC
                 LIMIT ? OFFSET ?
                """
            )
            sqlite3_bind_int64(
                statement,
                1,
                sqlite3_int64(boundedLimit)
            )
            sqlite3_bind_int64(
                statement,
                2,
                sqlite3_int64(max(offset, 0))
            )
        } else {
            statement = try prepare(
                """
                SELECT n.id, n.title, n.plain_text, n.rich_text,
                       n.asset_hashes, n.created_at, n.updated_at
                  FROM scratchpad_note n
                  JOIN scratchpad_note_fts f ON f.note_id = n.id
                 WHERE scratchpad_note_fts MATCH ?
                 ORDER BY rank
                 LIMIT ? OFFSET ?
                """
            )
            let escaped = search.replacingOccurrences(of: "\"", with: "\"\"")
            bind("\"\(escaped)\"", at: 1, in: statement)
            sqlite3_bind_int64(
                statement,
                2,
                sqlite3_int64(boundedLimit)
            )
            sqlite3_bind_int64(
                statement,
                3,
                sqlite3_int64(max(offset, 0))
            )
        }
        defer { sqlite3_finalize(statement) }
        var notes: [ScratchpadNote] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            notes.append(try decodeNote(statement))
        }
        return notes
    }

    private func fetchNote(_ id: UUID) throws -> ScratchpadNote? {
        let statement = try prepare(
            """
            SELECT id, title, plain_text, rich_text, asset_hashes,
                   created_at, updated_at
              FROM scratchpad_note
             WHERE id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return try decodeNote(statement)
        case SQLITE_DONE:
            return nil
        default:
            throw LocalWorkspaceError.corrupt
        }
    }

    private func requiredNote(_ id: UUID) throws -> ScratchpadNote {
        guard let note = try fetchNote(id) else {
            throw LocalWorkspaceError.notFound
        }
        return note
    }

    private func decodeNote(
        _ statement: OpaquePointer?
    ) throws -> ScratchpadNote {
        guard
            let id = UUID(uuidString: text(at: 0, in: statement))
        else {
            throw LocalWorkspaceError.corrupt
        }
        return ScratchpadNote(
            id: id,
            title: text(at: 1, in: statement),
            plainText: text(at: 2, in: statement),
            richTextRTF: blob(at: 3, in: statement),
            assetHashes: try decode(
                [String].self,
                from: blob(at: 4, in: statement) ?? Data("[]".utf8)
            ),
            createdAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 5)
            ),
            updatedAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 6)
            )
        )
    }

    private func fetchVersions(
        noteID: UUID,
        limit: Int
    ) throws -> [ScratchpadVersion] {
        let statement = try prepare(
            """
            SELECT id, note_id, title, plain_text, rich_text,
                   asset_hashes, created_at
              FROM scratchpad_version
             WHERE note_id = ?
             ORDER BY created_at DESC
             LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(noteID.uuidString, at: 1, in: statement)
        sqlite3_bind_int64(
            statement,
            2,
            sqlite3_int64(
                min(max(limit, 1), limits.maximumVersionsPerNote)
            )
        )
        var versions: [ScratchpadVersion] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            versions.append(try decodeVersion(statement))
        }
        return versions
    }

    private func requiredVersion(
        noteID: UUID,
        versionID: UUID
    ) throws -> ScratchpadVersion {
        let statement = try prepare(
            """
            SELECT id, note_id, title, plain_text, rich_text,
                   asset_hashes, created_at
              FROM scratchpad_version
             WHERE note_id = ? AND id = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(noteID.uuidString, at: 1, in: statement)
        bind(versionID.uuidString, at: 2, in: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalWorkspaceError.notFound
        }
        return try decodeVersion(statement)
    }

    private func decodeVersion(
        _ statement: OpaquePointer?
    ) throws -> ScratchpadVersion {
        guard
            let id = UUID(uuidString: text(at: 0, in: statement)),
            let noteID = UUID(uuidString: text(at: 1, in: statement))
        else {
            throw LocalWorkspaceError.corrupt
        }
        return ScratchpadVersion(
            id: id,
            noteID: noteID,
            title: text(at: 2, in: statement),
            plainText: text(at: 3, in: statement),
            richTextRTF: blob(at: 4, in: statement),
            assetHashes: try decode(
                [String].self,
                from: blob(at: 5, in: statement) ?? Data("[]".utf8)
            ),
            createdAt: Date(
                timeIntervalSince1970: sqlite3_column_double(statement, 6)
            )
        )
    }

    private func upsertSearchIndex(_ note: ScratchpadNote) throws {
        try deleteSearchIndex(note.id)
        let statement = try prepare(
            """
            INSERT INTO scratchpad_note_fts(note_id, title, body)
            VALUES (?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(note.id.uuidString, at: 1, in: statement)
        bind(note.title, at: 2, in: statement)
        bind(note.plainText, at: 3, in: statement)
        try stepDone(statement)
    }

    private func deleteSearchIndex(_ id: UUID) throws {
        let statement = try prepare(
            "DELETE FROM scratchpad_note_fts WHERE note_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, in: statement)
        try stepDone(statement)
    }

    private func storeAsset(
        data: Data,
        mediaType: String
    ) throws -> WorkspaceReceipt {
        guard
            !data.isEmpty,
            data.count <= limits.maximumAssetBytes,
            mediaType.hasPrefix("image/"),
            mediaType.count <= 100
        else {
            throw LocalWorkspaceError.assetRejected
        }
        let hash = Self.sha256(data)
        if try fetchAsset(hash) != nil {
            return WorkspaceReceipt(
                entityID: hash,
                versionID: nil,
                checksum: hash
            )
        }
        let total = try scalarInt(
            "SELECT COALESCE(SUM(byte_count), 0) FROM scratchpad_asset"
        )
        guard total + data.count <= limits.maximumTotalAssetBytes else {
            throw LocalWorkspaceError.quotaExceeded
        }
        try FileManager.default.createDirectory(
            at: assetsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = assetURL(hash)
        try data.write(to: destination, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
        do {
            let statement = try prepare(
                """
                INSERT INTO scratchpad_asset(hash, media_type, byte_count)
                VALUES (?, ?, ?)
                """
            )
            defer { sqlite3_finalize(statement) }
            bind(hash, at: 1, in: statement)
            bind(String(mediaType.prefix(100)), at: 2, in: statement)
            sqlite3_bind_int64(
                statement,
                3,
                sqlite3_int64(data.count)
            )
            try stepDone(statement)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        return WorkspaceReceipt(
            entityID: hash,
            versionID: nil,
            checksum: hash
        )
    }

    private func fetchAsset(_ hash: String) throws -> ScratchpadAsset? {
        guard
            hash.count == 64,
            hash.allSatisfy({ $0.isHexDigit })
        else { return nil }
        let statement = try prepare(
            """
            SELECT hash, media_type, byte_count
              FROM scratchpad_asset
             WHERE hash = ?
            """
        )
        defer { sqlite3_finalize(statement) }
        bind(hash, at: 1, in: statement)
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return ScratchpadAsset(
                hash: text(at: 0, in: statement),
                mediaType: text(at: 1, in: statement),
                byteCount: Int(sqlite3_column_int64(statement, 2))
            )
        case SQLITE_DONE:
            return nil
        default:
            throw LocalWorkspaceError.corrupt
        }
    }

    private func deleteOrphanAssets() throws -> Int {
        let notes = try fetchNotes(
            search: "",
            limit: limits.maximumNotes,
            offset: 0
        )
        let versionsStatement = try prepare(
            "SELECT asset_hashes FROM scratchpad_version"
        )
        defer { sqlite3_finalize(versionsStatement) }
        var referenced = Set(notes.flatMap(\.assetHashes))
        while sqlite3_step(versionsStatement) == SQLITE_ROW {
            let hashes = try decode(
                [String].self,
                from: blob(at: 0, in: versionsStatement)
                    ?? Data("[]".utf8)
            )
            referenced.formUnion(hashes)
        }
        let statement = try prepare("SELECT hash FROM scratchpad_asset")
        defer { sqlite3_finalize(statement) }
        var removed = 0
        while sqlite3_step(statement) == SQLITE_ROW {
            let hash = text(at: 0, in: statement)
            guard !referenced.contains(hash) else { continue }
            try? FileManager.default.removeItem(at: assetURL(hash))
            let deletion = try prepare(
                "DELETE FROM scratchpad_asset WHERE hash = ?"
            )
            bind(hash, at: 1, in: deletion)
            try stepDone(deletion)
            sqlite3_finalize(deletion)
            removed += 1
        }
        return removed
    }

    private func deleteAllAssets() throws -> Int {
        let count = try scalarInt("SELECT COUNT(*) FROM scratchpad_asset")
        try execute("DELETE FROM scratchpad_asset")
        if FileManager.default.fileExists(atPath: assetsDirectory.path) {
            try FileManager.default.removeItem(at: assetsDirectory)
        }
        return count
    }

    private func insertLegacy(
        table: String,
        id: String,
        payload: Data
    ) throws {
        guard ["history_item", "dictionary_entry", "style"].contains(table)
        else {
            throw LocalWorkspaceError.invalidMutation
        }
        let statement = try prepare(
            "INSERT INTO \(table)(id, payload) VALUES (?, ?)"
        )
        defer { sqlite3_finalize(statement) }
        bind(id, at: 1, in: statement)
        bind(payload, at: 2, in: statement)
        try stepDone(statement)
    }

    private func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else {
            throw LocalWorkspaceError.unavailable
        }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            sql,
            -1,
            &statement,
            nil
        ) == SQLITE_OK else {
            throw LocalWorkspaceError.corrupt
        }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard let database else {
            throw LocalWorkspaceError.unavailable
        }
        try Self.execute(database, sql: sql)
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw LocalWorkspaceError.corrupt
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw LocalWorkspaceError.corrupt
        }
    }

    private func bind(
        _ value: String,
        at index: Int32,
        in statement: OpaquePointer?
    ) {
        _ = value.withCString {
            sqlite3_bind_text(
                statement,
                index,
                $0,
                -1,
                Self.transient
            )
        }
    }

    private func bind(
        _ value: Data?,
        at index: Int32,
        in statement: OpaquePointer?
    ) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        _ = value.withUnsafeBytes {
            sqlite3_bind_blob(
                statement,
                index,
                $0.baseAddress,
                Int32(value.count),
                Self.transient
            )
        }
    }

    private func text(
        at index: Int32,
        in statement: OpaquePointer?
    ) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func blob(
        at index: Int32,
        in statement: OpaquePointer?
    ) -> Data? {
        guard let bytes = sqlite3_column_blob(statement, index) else {
            return nil
        }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: bytes, count: count)
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        try JSONEncoder.workspace.encode(value)
    }

    private func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data
    ) throws -> T {
        do {
            return try JSONDecoder.workspace.decode(type, from: data)
        } catch {
            throw LocalWorkspaceError.corrupt
        }
    }

    private func checksum(_ note: ScratchpadNote) -> String? {
        guard let encoded = try? JSONEncoder.workspace.encode(note) else {
            return nil
        }
        return Self.sha256(encoded)
    }

    private func assetURL(_ hash: String) -> URL {
        assetsDirectory.appendingPathComponent(hash, isDirectory: false)
    }

    private static func prepareParent(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
    }

    private static func execute(
        _ database: OpaquePointer,
        sql: String
    ) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw LocalWorkspaceError.corrupt
        }
    }

    private static func createSchema(
        _ database: OpaquePointer
    ) throws {
        try execute(
            database,
            sql:
                """
                CREATE TABLE IF NOT EXISTS scratchpad_note (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    plain_text TEXT NOT NULL,
                    rich_text BLOB,
                    asset_hashes BLOB NOT NULL,
                    created_at REAL NOT NULL,
                    updated_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS scratchpad_version (
                    id TEXT PRIMARY KEY,
                    note_id TEXT NOT NULL REFERENCES scratchpad_note(id)
                        ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    plain_text TEXT NOT NULL,
                    rich_text BLOB,
                    asset_hashes BLOB NOT NULL,
                    created_at REAL NOT NULL
                );
                CREATE TABLE IF NOT EXISTS scratchpad_asset (
                    hash TEXT PRIMARY KEY,
                    media_type TEXT NOT NULL,
                    byte_count INTEGER NOT NULL
                );
                CREATE VIRTUAL TABLE IF NOT EXISTS scratchpad_note_fts
                    USING fts5(note_id UNINDEXED, title, body);
                CREATE TABLE IF NOT EXISTS history_item (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS transcript_revision (
                    id TEXT PRIMARY KEY,
                    history_id TEXT,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS dictionary_entry (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS dictionary_usage (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS style (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS transform_template (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS daily_metric (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS operational_issue (
                    id TEXT PRIMARY KEY,
                    payload BLOB NOT NULL
                );
                CREATE TABLE IF NOT EXISTS migration_ledger (
                    source TEXT PRIMARY KEY,
                    checksum TEXT NOT NULL,
                    imported_at REAL NOT NULL
                );
                """
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()
    }
}

private struct LegacyChecksumPayload: Encodable {
    let history: [HistoryEntry]
    let dictionary: [ReplacementRule]
    let styles: [DictationStylePreset]

    init(snapshot: LegacyWorkspaceSnapshot) {
        history = snapshot.history
        dictionary = snapshot.dictionary
        styles = snapshot.styles
    }
}

private extension JSONEncoder {
    static var workspace: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var workspace: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
