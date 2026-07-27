import Foundation
import XCTest
@testable import AutohandVoiceCore

final class OperationalIssueTests: XCTestCase {
    func testIssuesAggregateWithoutArbitraryMessagesAndUseOwnerOnlyFile()
        throws
    {
        let url = temporaryURL()
        let store = OperationalIssueStore(url: url)
        let now = Date(timeIntervalSince1970: 10_000)

        try store.record(.microphone, at: now)
        try store.record(.microphone, at: now.addingTimeInterval(2))
        try store.record(.insertion, at: now.addingTimeInterval(3))

        let issues = try store.load(now: now.addingTimeInterval(3))
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(
            issues.first { $0.kind == .microphone }?.count,
            2
        )
        let data = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("text"))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testIssuesAreBoundedByAgeCountAndClockChanges() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(
            -OperationalIssueStore.maximumAge - 1
        )
        let future = now.addingTimeInterval(10_000)
        let data = try JSONEncoder.operationalIssues.encode([
            OperationalIssue(
                kind: .storage,
                firstSeenAt: old,
                lastSeenAt: old,
                count: 20_000
            ),
            OperationalIssue(
                kind: .model,
                firstSeenAt: future,
                lastSeenAt: future,
                count: 20_000
            ),
        ])
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)

        let issues = try OperationalIssueStore(url: url).load(now: now)

        XCTAssertEqual(issues.map(\.kind), [.model])
        XCTAssertEqual(issues[0].lastSeenAt, now)
        XCTAssertEqual(
            issues[0].count,
            OperationalIssueStore.maximumCount
        )
    }

    func testCorruptStoreLoadsEmptyAndNextRecordRepairsIt() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: url)
        let store = OperationalIssueStore(url: url)

        XCTAssertEqual(try store.load(), [])
        let repaired = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            ) as? [Any]
        )
        XCTAssertTrue(repaired.isEmpty)
        try store.record(.runtime)

        XCTAssertEqual(try store.load().map(\.kind), [.runtime])
    }

    func testResetRemovesIssueFile() throws {
        let url = temporaryURL()
        let store = OperationalIssueStore(url: url)
        try store.record(.settings)

        try store.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOversizedStoreIsReplacedWithoutDecodingIt() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            repeating: 0x41,
            count: Int(OperationalIssueStore.maximumFileBytes + 1)
        ).write(to: url)

        XCTAssertEqual(try OperationalIssueStore(url: url).load(), [])
        XCTAssertLessThan(
            try Data(contentsOf: url).count,
            Int(OperationalIssueStore.maximumFileBytes)
        )
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("operational-issues.json")
    }
}

private extension JSONEncoder {
    static var operationalIssues: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
