import Foundation
import XCTest
@testable import AutohandVoiceCore

final class LocalDataResetTests: XCTestCase {
    func testResetEnumeratesDeletesAndVerifiesEveryLocation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("preferences.json")
        let directory = root.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
        let nested = directory.appendingPathComponent("artifact.avr")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("settings".utf8).write(to: file)
        try Data("encrypted".utf8).write(to: nested)
        let keys = ResetKeyProvider()
        let resetter = try LocalDataResetter(
            urls: [file, directory, file],
            keyProvider: keys
        )

        let report = resetter.reset()

        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.removedLocationCount, 2)
        XCTAssertTrue(report.entries.allSatisfy(\.verifiedAbsent))
        XCTAssertTrue(keys.wasDeleted)
    }

    func testMissingLocationsStillVerifyAndDeleteRecoveryKey() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let keys = ResetKeyProvider()
        let resetter = try LocalDataResetter(
            urls: [root.appendingPathComponent("missing.json")],
            keyProvider: keys
        )

        let report = resetter.reset()

        XCTAssertTrue(report.succeeded)
        XCTAssertEqual(report.removedLocationCount, 0)
        XCTAssertFalse(report.entries[0].existedBeforeReset)
        XCTAssertTrue(report.entries[0].verifiedAbsent)
    }

    func testUnsafeBroadLocationsAreRejected() {
        XCTAssertThrowsError(
            try LocalDataResetter(
                urls: [URL(fileURLWithPath: "/")],
                keyProvider: ResetKeyProvider()
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalDataResetError,
                .unsafeLocation("/")
            )
        }
    }

    func testProductionLedgerContainsEveryCurrentStoreAndSidecar() {
        let names = Set(Brand.ownerOnlyDataURLs.map(\.lastPathComponent))
        XCTAssertTrue(names.contains("preferences.json"))
        XCTAssertTrue(names.contains("history.json"))
        XCTAssertTrue(names.contains("vocabulary.json"))
        XCTAssertTrue(names.contains("vocabulary-suggestions.json"))
        XCTAssertTrue(names.contains("app-profiles.json"))
        XCTAssertTrue(names.contains("dictation-styles.json"))
        XCTAssertTrue(names.contains("usage-insights.json"))
        XCTAssertTrue(names.contains("operational-issues.json"))
        XCTAssertTrue(names.contains("reliability-ledger.json"))
        XCTAssertTrue(names.contains("Recovery"))
        XCTAssertTrue(names.contains("workspace-v2.sqlite"))
        XCTAssertTrue(names.contains("workspace-v2.sqlite-wal"))
        XCTAssertTrue(names.contains("workspace-v2.sqlite-shm"))
        XCTAssertTrue(names.contains("Scratchpad Assets"))
        XCTAssertTrue(names.contains("transform-templates.json"))
    }
}

private final class ResetKeyProvider:
    RecoveryKeyProviding,
    @unchecked Sendable
{
    private(set) var wasDeleted = false

    func keyData(createIfMissing: Bool) throws -> Data? {
        createIfMissing ? Data(repeating: 1, count: 32) : nil
    }

    func deleteKey() throws {
        wasDeleted = true
    }
}
