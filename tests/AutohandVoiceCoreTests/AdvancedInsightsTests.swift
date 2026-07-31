import Foundation
import XCTest
@testable import AutohandVoiceCore

final class AdvancedInsightsTests: XCTestCase {
    func testStreakUsesCalendarDaysAndAllowsYesterdayAsCurrent() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 5 * 86_400)
        let days = [2, 3, 4].map {
            UsageInsightDay(
                day: Date(timeIntervalSince1970: TimeInterval($0) * 86_400),
                dictationCount: 1
            )
        }

        let streak = UsageStreak(
            days: days,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(streak.currentDays, 3)
        XCTAssertEqual(streak.longestDays, 3)
    }

    func testVoiceProfileRequiresRetainedTextThreshold() {
        let result = LocalVoiceProfileAnalyzer.analyze([
            HistoryEntry(
                text: "too few words",
                createdAt: Date(),
                outcome: .inserted
            ),
        ])

        XCTAssertEqual(
            result,
            .insufficientWords(
                current: 3,
                required: LocalVoiceProfileAnalyzer.minimumRetainedWords
            )
        )
    }

    func testVoiceProfileIsDeterministicAndLabelsMethod() throws {
        let raw = try RawFinalTranscript(
            text: "um local words",
            languageCode: "en",
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let revision = TranscriptRevision(
            rootRawID: raw.id,
            parentID: nil,
            text: "local words",
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
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let retainedText = Array(
            repeating: "local",
            count: LocalVoiceProfileAnalyzer.minimumRetainedWords
        ).joined(separator: " ")
        let result = LocalVoiceProfileAnalyzer.analyze([
            HistoryEntry(
                text: retainedText,
                createdAt: Date(timeIntervalSince1970: 1_000),
                outcome: .inserted,
                rawFinal: raw,
                revision: revision
            ),
        ])

        guard case let .available(profile) = result else {
            return XCTFail("Expected a local profile")
        }
        XCTAssertTrue(profile.methodDescription.contains("Deterministic"))
        XCTAssertEqual(profile.mostCorrectedTerms, ["um"])
    }

    func testAppCategoryStoresNoBundleIdentifier() {
        XCTAssertEqual(
            UsageAppCategoryClassifier.classify(
                bundleIdentifier: "com.apple.Terminal"
            ),
            .terminal
        )
        XCTAssertEqual(
            UsageAppCategoryClassifier.classify(
                bundleIdentifier: "com.example.Unknown"
            ),
            .other
        )
    }
}
