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

    private func makeStore() throws -> HistoryStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return HistoryStore(url: directory.appendingPathComponent("history.json"))
    }
}
