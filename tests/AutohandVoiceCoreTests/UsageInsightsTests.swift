import Foundation
import XCTest
@testable import AutohandVoiceCore

final class UsageInsightsTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    func testEventsAggregateWithoutTranscriptContent() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        try store.record(
            UsageMetricEvent(
                wordCount: 12,
                recordingDuration: 4,
                processingDuration: 1,
                insertionSucceeded: true
            ),
            at: now,
            calendar: calendar
        )
        try store.record(
            UsageMetricEvent(
                wordCount: 8,
                recordingDuration: 3,
                processingDuration: 2,
                insertionSucceeded: false
            ),
            at: now.addingTimeInterval(60),
            calendar: calendar
        )

        let day = try XCTUnwrap(
            store.load(now: now, calendar: calendar).first
        )
        XCTAssertEqual(day.dictationCount, 2)
        XCTAssertEqual(day.wordCount, 20)
        XCTAssertEqual(day.recordingDuration, 7)
        XCTAssertEqual(day.processingDuration, 3)
        XCTAssertEqual(day.insertionSuccessCount, 1)
        XCTAssertEqual(day.insertionFailureCount, 1)

        let encoded = try String(
            contentsOf: store.url,
            encoding: .utf8
        )
        XCTAssertFalse(encoded.contains("secret transcript"))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testStoreBoundsDaysAndUntrustedCounters() throws {
        let store = makeStore()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for offset in 0...UsageInsightsStore.maximumDays {
            try store.record(
                UsageMetricEvent(
                    wordCount: Int.max,
                    recordingDuration: .infinity,
                    processingDuration: -50,
                    insertionSucceeded: true
                ),
                at: now.addingTimeInterval(
                    -Double(offset) * 86_400
                ),
                calendar: calendar
            )
        }

        let days = try store.load(now: now, calendar: calendar)
        XCTAssertEqual(days.count, UsageInsightsStore.maximumDays)
        XCTAssertLessThanOrEqual(
            days.first?.wordCount ?? 0,
            UsageInsightsStore.maximumWordsPerEvent
        )
        XCTAssertLessThanOrEqual(
            days.first?.recordingDuration ?? 0,
            UsageInsightsStore.maximumDurationPerEvent
        )
        XCTAssertGreaterThanOrEqual(
            days.first?.processingDuration ?? -1,
            0
        )
    }

    func testSummaryUsesDocumentedTypingEstimate() {
        let summary = UsageInsightsSummary(
            days: [
                UsageInsightDay(
                    day: Date(timeIntervalSince1970: 1_800_000_000),
                    dictationCount: 2,
                    wordCount: 80,
                    recordingDuration: 30,
                    processingDuration: 10,
                    insertionSuccessCount: 2,
                    insertionFailureCount: 0
                ),
            ]
        )

        XCTAssertEqual(summary.averageProcessingLatency, 5)
        XCTAssertEqual(summary.estimatedTypingTimeSaved, 80)
        XCTAssertEqual(summary.insertionSuccessRate, 1)
    }

    func testRecoveredInsertionMovesFailureToSuccess() throws {
        let store = makeStore()
        let now = Date()
        let day = try store.record(
            UsageMetricEvent(
                wordCount: 4,
                recordingDuration: 2,
                processingDuration: 1,
                insertionSucceeded: false
            ),
            at: now,
            calendar: calendar
        )

        try store.markInsertionSucceeded(on: day)

        let value = try XCTUnwrap(
            store.load(now: now, calendar: calendar).first
        )
        XCTAssertEqual(value.insertionFailureCount, 0)
        XCTAssertEqual(value.insertionSuccessCount, 1)
    }

    func testResetRemovesAggregateFile() throws {
        let store = makeStore()
        try store.record(
            UsageMetricEvent(
                wordCount: 1,
                recordingDuration: 1,
                processingDuration: 1,
                insertionSucceeded: true
            )
        )

        try store.reset()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: store.url.path)
        )
    }

    private func makeStore() -> UsageInsightsStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return UsageInsightsStore(
            url: directory.appendingPathComponent("usage-insights.json")
        )
    }
}
