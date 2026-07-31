import Foundation
import XCTest
@testable import AutohandVoiceCore

final class HistoryStoreTests: XCTestCase {
    func testHistoryIsBoundedByAgeAndCount() throws {
        let store = try makeStore()
        let now = Date(timeIntervalSince1970: 1_000_000)
        for offset in 0..<5 {
            _ = try store.append(
                text: "Entry \(offset)",
                outcome: .inserted,
                at: now.addingTimeInterval(TimeInterval(offset - 40) * 86_400),
                retentionDays: 30,
                maximumItems: 3
            )
        }
        _ = try store.append(
            text: "Newest",
            outcome: .insertionFailed,
            at: now,
            retentionDays: 30,
            maximumItems: 3
        )

        let entries = try store.load(
            now: now,
            retentionDays: 30,
            maximumItems: 3
        )

        XCTAssertEqual(entries.map(\.text), ["Newest"])
        XCTAssertEqual(entries.first?.outcome, .insertionFailed)
    }

    func testHistorySupportsUpdateDeleteAndDeleteAll() throws {
        let store = try makeStore()
        let first = try store.append(text: "One", outcome: .insertionFailed)
        _ = try store.append(text: "Two", outcome: .inserted)

        try store.updateOutcome(id: first.id, outcome: .inserted)
        XCTAssertTrue(try store.load().allSatisfy { $0.outcome == .inserted })

        try store.delete(id: first.id)
        XCTAssertEqual(try store.load().map(\.text), ["Two"])

        try store.deleteAll()
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testHistorySearchIsCaseInsensitiveAndLocal() {
        let entry = HistoryEntry(
            text: "Autohand Voice",
            createdAt: Date(),
            outcome: .inserted
        )

        XCTAssertTrue(entry.matches("voice"))
        XCTAssertFalse(entry.matches("cloud"))
    }

    func testHistoryFileIsOwnerOnly() throws {
        let store = try makeStore()
        _ = try store.append(text: "Private", outcome: .inserted)

        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber

        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testHistoryRoundTripsRawFinalAndRevisionMetadata() throws {
        let store = try makeStore()
        let createdAt = Date(timeIntervalSince1970: 1_000_000)
        let raw = try RawFinalTranscript(
            text: "um hello",
            languageCode: "en",
            createdAt: createdAt
        )
        let revision = TranscriptRevision(
            rootRawID: raw.id,
            parentID: nil,
            text: "hello",
            kind: .lightCleanup,
            policyVersion: RevisionPolicy.currentVersion,
            changes: [
                BoundedTextChange(
                    characterOffset: 0,
                    removedText: "um ",
                    insertedText: ""
                ),
            ],
            depth: 0,
            createdAt: createdAt
        )

        _ = try store.append(
            text: revision.text,
            outcome: .insertionFailed,
            rawFinal: raw,
            revision: revision,
            duration: 2.5,
            failureCategory: .insertion(.rejected)
        )
        let entry = try XCTUnwrap(store.load().first)

        XCTAssertEqual(entry.rawFinal, raw)
        XCTAssertEqual(entry.revision, revision)
        XCTAssertEqual(entry.languageCode, "en")
        XCTAssertEqual(entry.duration, 2.5)
        XCTAssertEqual(entry.failureCategory, .insertion(.rejected))
    }

    func testHistoryByteCapKeepsNewestCompleteRows() throws {
        let store = try makeStore()
        let now = Date()
        for index in 0 ..< 6 {
            _ = try store.append(
                text: String(repeating: "\(index)", count: 800),
                outcome: .inserted,
                at: now.addingTimeInterval(TimeInterval(index)),
                maximumBytes: 3_000
            )
        }

        let entries = try store.load(
            now: now.addingTimeInterval(10),
            maximumBytes: 3_000
        )

        XCTAssertLessThan(entries.count, 6)
        XCTAssertTrue(entries.first?.text.hasPrefix("5") == true)
        XCTAssertLessThanOrEqual(
            try Data(contentsOf: store.url).count,
            3_000
        )
    }

    private func makeStore() throws -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return HistoryStore(url: directory.appendingPathComponent("history.json"))
    }
}
