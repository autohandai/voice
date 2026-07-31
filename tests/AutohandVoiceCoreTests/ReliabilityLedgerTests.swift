import Foundation
import XCTest
@testable import AutohandVoiceCore

final class ReliabilityLedgerTests: XCTestCase {
    func testRecordsFiniteCountersAndLatencyBuckets() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = ReliabilityLedger(
            url: fixture.url,
            appVersion: "1.2.3"
        )
        let now = Date(timeIntervalSince1970: 1_787_875_200)

        try await ledger.record(
            ReliabilityEvent(
                category: .recordingStart,
                outcome: .success,
                latency: .init(metric: .recordingStart, seconds: 0.08),
                modelVersion: .v3,
                supported: true
            ),
            at: now
        )
        try await ledger.record(
            ReliabilityEvent(
                category: .transcription,
                outcome: .failure,
                latency: .init(metric: .stopToFinal, seconds: 1.4),
                modelVersion: .v3,
                supported: true
            ),
            at: now.addingTimeInterval(10)
        )

        let snapshot = try await ledger.snapshot(
            DateInterval(
                start: now.addingTimeInterval(-60),
                end: now.addingTimeInterval(60)
            ),
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(
            snapshot.count(category: .recordingStart, outcome: .success),
            1
        )
        XCTAssertEqual(
            snapshot.count(category: .transcription, outcome: .failure),
            1
        )
        XCTAssertEqual(
            snapshot.latencyCount(metric: .recordingStart, bucket: .under100ms),
            1
        )
        XCTAssertEqual(
            snapshot.latencyCount(metric: .stopToFinal, bucket: .under2s),
            1
        )
        XCTAssertEqual(snapshot.rows.count, 1)
    }

    func testSnapshotDropsExpiredRowsAndClampsFutureDates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = ReliabilityLedger(url: fixture.url)
        let now = Date(timeIntervalSince1970: 1_787_875_200)

        try await ledger.record(
            ReliabilityEvent(
                category: .recordingStart,
                outcome: .failure,
                supported: true
            ),
            at: now.addingTimeInterval(-ReliabilityLedger.maximumAge - 86_400)
        )
        try await ledger.record(
            ReliabilityEvent(
                category: .recordingStart,
                outcome: .success,
                supported: true
            ),
            at: now.addingTimeInterval(86_400 * 5)
        )

        let snapshot = try await ledger.snapshot(
            DateInterval(
                start: now.addingTimeInterval(-ReliabilityLedger.maximumAge),
                end: now.addingTimeInterval(60)
            ),
            now: now
        )

        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(
            snapshot.count(category: .recordingStart, outcome: .failure),
            0
        )
        XCTAssertEqual(
            snapshot.count(category: .recordingStart, outcome: .success),
            1
        )
        XCTAssertLessThanOrEqual(snapshot.rows[0].day, now)
    }

    func testExportContainsOnlyAllowlistedFieldsAndFiniteValues() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = ReliabilityLedger(url: fixture.url)
        let now = Date(timeIntervalSince1970: 1_787_875_200)

        try await ledger.record(
            ReliabilityEvent(
                category: .insertion,
                outcome: .failure,
                latency: .init(metric: .insertion, seconds: 0.4),
                modelVersion: .v2,
                supported: true
            ),
            at: now
        )

        let data = try await ledger.exportRedacted(now: now)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let keys = recursivelyCollectedKeys(from: object)
        let allowlist: Set<String> = [
            "schemaVersion",
            "generatedAt",
            "intervalStart",
            "intervalEnd",
            "rows",
            "day",
            "appVersion",
            "modelVersion",
            "policySchemaVersion",
            "platform",
            "supported",
            "counters",
            "category",
            "outcome",
            "count",
            "latencyBuckets",
            "metric",
            "bucket",
        ]

        XCTAssertTrue(keys.isSubset(of: allowlist), "Unexpected keys: \(keys.subtracting(allowlist))")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret transcript"))
    }

    func testCorruptAndOversizedFilesResetSafely() async throws {
        let corruptFixture = try Fixture()
        defer { corruptFixture.remove() }
        try Data("not json".utf8).write(to: corruptFixture.url)
        let corruptLedger = ReliabilityLedger(url: corruptFixture.url)
        let now = Date(timeIntervalSince1970: 1_787_875_200)

        let corruptSnapshot = try await corruptLedger.snapshot(
            DateInterval(
                start: now.addingTimeInterval(-60),
                end: now.addingTimeInterval(60)
            ),
            now: now
        )
        XCTAssertTrue(corruptSnapshot.rows.isEmpty)

        let oversizedFixture = try Fixture()
        defer { oversizedFixture.remove() }
        try Data(
            repeating: 0x41,
            count: Int(ReliabilityLedger.maximumFileBytes + 1)
        ).write(to: oversizedFixture.url)
        let oversizedLedger = ReliabilityLedger(url: oversizedFixture.url)

        let oversizedSnapshot = try await oversizedLedger.snapshot(
            DateInterval(
                start: now.addingTimeInterval(-60),
                end: now.addingTimeInterval(60)
            ),
            now: now
        )
        XCTAssertTrue(oversizedSnapshot.rows.isEmpty)
        XCTAssertLessThanOrEqual(
            try Data(contentsOf: oversizedFixture.url).count,
            Int(ReliabilityLedger.maximumFileBytes)
        )
    }

    func testStoreIsOwnerOnlyAndResetIsIdempotent() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ledger = ReliabilityLedger(url: fixture.url)

        try await ledger.record(
            ReliabilityEvent(
                category: .modelValidation,
                outcome: .success,
                modelVersion: .v3,
                supported: true
            )
        )

        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(
                atPath: fixture.url.path
            )[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)

        try await ledger.reset()
        try await ledger.reset()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.url.path))
    }

    private func recursivelyCollectedKeys(from value: Any) -> Set<String> {
        if let object = value as? [String: Any] {
            return object.reduce(into: Set(object.keys)) { result, pair in
                result.formUnion(recursivelyCollectedKeys(from: pair.value))
            }
        }
        if let array = value as? [Any] {
            return array.reduce(into: Set<String>()) { result, item in
                result.formUnion(recursivelyCollectedKeys(from: item))
            }
        }
        return []
    }
}

private struct Fixture {
    let directory: URL
    let url: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("reliability-ledger.json")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
