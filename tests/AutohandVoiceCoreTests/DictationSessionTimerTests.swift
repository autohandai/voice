import XCTest
@testable import AutohandVoiceCore

final class DictationSessionTimerTests: XCTestCase {
    func testLegacyPolicyKeepsFiveMinuteHardStop() {
        let policy = DictationDurationPolicy(
            flags: FeatureFlags(environment: [:])
        )
        var timer = DictationSessionTimer(
            policy: policy,
            startedAt: 100
        )

        XCTAssertEqual(policy.maximumDuration, 300)
        XCTAssertFalse(timer.observe(at: 399.9).shouldFinalize)
        XCTAssertTrue(timer.observe(at: 400).shouldFinalize)
        XCTAssertFalse(timer.observe(at: 401).shouldFinalize)
    }

    func testOptInPolicyWarnsAtFifteenAndNineteenMinutesThenStopsOnce() {
        let policy = DictationDurationPolicy(
            flags: FeatureFlags(
                environment: [
                    FeatureFlag.longDictation20.environmentKey: "true",
                ]
            )
        )
        var timer = DictationSessionTimer(
            policy: policy,
            startedAt: 1_000
        )

        XCTAssertEqual(policy.maximumDuration, 1_200)
        XCTAssertEqual(timer.observe(at: 1_899).newWarnings, [])
        XCTAssertEqual(timer.observe(at: 1_900).newWarnings, [.fifteenMinutes])
        XCTAssertEqual(timer.observe(at: 2_140).newWarnings, [.nineteenMinutes])
        XCTAssertTrue(timer.observe(at: 2_200).shouldFinalize)
        XCTAssertFalse(timer.observe(at: 2_201).shouldFinalize)
    }

    func testSkippedObservationEmitsEachCrossedWarningOnce() {
        var timer = DictationSessionTimer(
            policy: .twentyMinutes,
            startedAt: 10
        )

        let lateObservation = timer.observe(at: 10 + 1_150)
        let repeatObservation = timer.observe(at: 10 + 1_151)

        XCTAssertEqual(
            lateObservation.newWarnings,
            [.fifteenMinutes, .nineteenMinutes]
        )
        XCTAssertTrue(repeatObservation.newWarnings.isEmpty)
    }

    func testCancelAtLimitPreventsAutomaticFinalization() {
        var timer = DictationSessionTimer(
            policy: .twentyMinutes,
            startedAt: 0
        )

        timer.cancel()
        let observation = timer.observe(at: 1_200)

        XCTAssertFalse(observation.shouldFinalize)
        XCTAssertTrue(observation.isCancelled)
    }

    func testElapsedTimeUsesMonotonicValuesAndNeverMovesBackward() {
        var timer = DictationSessionTimer(
            policy: .twentyMinutes,
            startedAt: 500
        )

        XCTAssertEqual(timer.observe(at: 620).elapsed, 120)
        XCTAssertEqual(timer.observe(at: 610).elapsed, 120)
    }
}
