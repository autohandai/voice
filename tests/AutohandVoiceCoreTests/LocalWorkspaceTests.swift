import Foundation
import XCTest
@testable import AutohandVoiceCore

final class LocalWorkspaceTests: XCTestCase {
    func testScratchpadCreateSearchVersionAndAtomicRestore() async throws {
        let fixture = try makeFixture()
        let workspace = try LocalWorkspace(
            databaseURL: fixture.database,
            assetsDirectory: fixture.assets
        )
        let original = ScratchpadNote(
            title: "Launch notes",
            plainText: "Private local draft",
            createdAt: Date(timeIntervalSince1970: 1_000),
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        _ = try await workspace.apply(.createNote(original))

        var updated = original
        updated.plainText = "Private local draft, revised"
        updated.updatedAt = Date(timeIntervalSince1970: 2_000)
        let receipt = try await workspace.apply(.updateNote(updated))
        XCTAssertNotNil(receipt.versionID)

        let search = try await workspace.query(
            .notes(search: "revised", limit: 20, offset: 0)
        )
        XCTAssertEqual(search.notes, [updated])

        let versions = try await workspace.query(
            .versions(noteID: original.id, limit: 20)
        )
        let version = try XCTUnwrap(versions.versions.first)
        XCTAssertEqual(version.plainText, original.plainText)

        _ = try await workspace.apply(
            .restoreVersion(noteID: original.id, versionID: version.id)
        )
        let restored = try await workspace.query(.note(original.id))
        XCTAssertEqual(restored.notes.first?.plainText, original.plainText)
    }

    func testWorkspaceRejectsOversizedNotesAndAssetsBeforePersistence()
        async throws
    {
        let fixture = try makeFixture()
        let limits = WorkspaceLimits(
            maximumNotes: 1,
            maximumVersionsPerNote: 2,
            maximumNoteCharacters: 1_000,
            maximumAssetBytes: 1_024,
            maximumTotalAssetBytes: 2_048,
            maximumSearchResults: 10
        )
        let workspace = try LocalWorkspace(
            databaseURL: fixture.database,
            assetsDirectory: fixture.assets,
            limits: limits
        )

        await XCTAssertThrowsErrorAsync(
            try await workspace.apply(
                .createNote(
                    ScratchpadNote(
                        title: "Too large",
                        plainText: String(repeating: "x", count: 1_001)
                    )
                )
            )
        ) {
            XCTAssertEqual(
                $0 as? LocalWorkspaceError,
                .invalidMutation
            )
        }

        await XCTAssertThrowsErrorAsync(
            try await workspace.apply(
                .storeAsset(
                    data: Data(repeating: 1, count: 1_025),
                    mediaType: "image/png"
                )
            )
        ) {
            XCTAssertEqual($0 as? LocalWorkspaceError, .assetRejected)
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: fixture.assets.path)
        )
    }

    func testContentAddressedAssetIsOwnerOnlyAndOrphanIsPurged()
        async throws
    {
        let fixture = try makeFixture()
        let workspace = try LocalWorkspace(
            databaseURL: fixture.database,
            assetsDirectory: fixture.assets
        )
        let data = Data("not-real-image-bytes".utf8)
        let first = try await workspace.apply(
            .storeAsset(data: data, mediaType: "image/png")
        )
        let second = try await workspace.apply(
            .storeAsset(data: data, mediaType: "image/png")
        )
        XCTAssertEqual(first.entityID, second.entityID)
        let loadedAsset = try await workspace.assetData(first.entityID)
        XCTAssertEqual(loadedAsset, data)

        let assetURL = fixture.assets.appendingPathComponent(first.entityID)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: assetURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        let report = try await workspace.enforceRetention()
        XCTAssertEqual(report.deletedOrphanAssets, 1)
        await XCTAssertThrowsErrorAsync(
            try await workspace.assetData(first.entityID)
        ) {
            XCTAssertEqual($0 as? LocalWorkspaceError, .notFound)
        }
    }

    func testLegacyImportVerifiesCountsAndRollsBackOnDuplicate()
        async throws
    {
        let fixture = try makeFixture()
        let workspace = try LocalWorkspace(
            databaseURL: fixture.database,
            assetsDirectory: fixture.assets
        )
        let entry = HistoryEntry(
            text: "Original",
            createdAt: Date(timeIntervalSince1970: 1_000),
            outcome: .inserted
        )
        let valid = LegacyWorkspaceSnapshot(
            history: [entry],
            dictionary: [
                ReplacementRule(source: "auto hand", replacement: "Autohand"),
            ],
            styles: []
        )
        let report = try await workspace.importLegacy(
            valid,
            sourceName: "legacy-json-v1"
        )
        XCTAssertEqual(report.importedHistory, 1)
        XCTAssertEqual(report.importedDictionary, 1)
        XCTAssertEqual(report.checksum.count, 64)

        let duplicate = LegacyWorkspaceSnapshot(
            history: [entry, entry],
            dictionary: [],
            styles: []
        )
        await XCTAssertThrowsErrorAsync(
            try await workspace.importLegacy(
                duplicate,
                sourceName: "bad-duplicate"
            )
        )

        let reimport = try await workspace.importLegacy(
            valid,
            sourceName: "legacy-json-v1"
        )
        XCTAssertEqual(reimport.importedHistory, 1)
    }

    func testDatabaseAndDirectoryAreOwnerOnly() async throws {
        let fixture = try makeFixture()
        _ = try LocalWorkspace(
            databaseURL: fixture.database,
            assetsDirectory: fixture.assets
        )
        let filePermissions = try FileManager.default.attributesOfItem(
            atPath: fixture.database.path
        )[.posixPermissions] as? NSNumber
        let directoryPermissions = try FileManager.default.attributesOfItem(
            atPath: fixture.root.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(filePermissions?.intValue, 0o600)
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
    }

    func testLegacyLoaderValidatesAllSourcesBeforeMigration() throws {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        let urls = LegacyWorkspaceSourceURLs(
            history: fixture.root.appendingPathComponent("history.json"),
            dictionary: fixture.root.appendingPathComponent("vocabulary.json"),
            styles: fixture.root.appendingPathComponent("styles.json")
        )
        let history = [
            HistoryEntry(
                text: "Local",
                createdAt: Date(timeIntervalSince1970: 1_000),
                outcome: .inserted
            ),
        ]
        let historyEncoder = JSONEncoder()
        historyEncoder.dateEncodingStrategy = .iso8601
        try historyEncoder.encode(history).write(to: urls.history)
        try JSONEncoder().encode([
            ReplacementRule(source: "flow", replacement: "Flow"),
        ]).write(to: urls.dictionary)
        try Data("[]".utf8).write(to: urls.styles)

        let validated = try LegacyWorkspaceLoader.load(urls)

        XCTAssertEqual(validated.snapshot.history, history)
        XCTAssertEqual(validated.snapshot.dictionary.count, 1)
        XCTAssertEqual(validated.sourceChecksum.count, 64)
    }

    func testLegacyLoaderRejectsCorruptMixedAndOversizedInputs()
        throws
    {
        let fixture = try makeFixture()
        try FileManager.default.createDirectory(
            at: fixture.root,
            withIntermediateDirectories: true
        )
        let urls = LegacyWorkspaceSourceURLs(
            history: fixture.root.appendingPathComponent("history.json"),
            dictionary: fixture.root.appendingPathComponent("vocabulary.json"),
            styles: fixture.root.appendingPathComponent("styles.json")
        )
        try Data("[]".utf8).write(to: urls.history)
        try Data("{bad".utf8).write(to: urls.dictionary)
        try Data("[]".utf8).write(to: urls.styles)

        XCTAssertThrowsError(try LegacyWorkspaceLoader.load(urls)) {
            XCTAssertEqual(
                $0 as? LegacyWorkspaceLoadError,
                .sourceInvalid("dictionary")
            )
        }

        try Data(repeating: 0, count: HistoryStore.maximumFileBytes + 1)
            .write(to: urls.history)
        try Data("[]".utf8).write(to: urls.dictionary)
        XCTAssertThrowsError(try LegacyWorkspaceLoader.load(urls)) {
            XCTAssertEqual(
                $0 as? LegacyWorkspaceLoadError,
                .sourceTooLarge("history")
            )
        }
    }

    private func makeFixture() throws -> (
        root: URL,
        database: URL,
        assets: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }
        return (
            root,
            root.appendingPathComponent("workspace.sqlite"),
            root.appendingPathComponent("assets", isDirectory: true)
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
