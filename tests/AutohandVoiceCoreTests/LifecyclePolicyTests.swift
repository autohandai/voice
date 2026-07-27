import XCTest
@testable import AutohandVoiceCore

final class LifecyclePolicyTests: XCTestCase {
    func testSleepRetainsActiveRecordingAndReportsInterruption() {
        XCTAssertEqual(
            VoiceLifecyclePolicy.action(
                for: .sleep,
                activity: .recording
            ),
            .retainAudioAndReport
        )
    }

    func testSleepCancelsIncompleteStartupAndReportsInterruption() {
        XCTAssertEqual(
            VoiceLifecyclePolicy.action(
                for: .sleep,
                activity: .starting
            ),
            .cancelAndReport
        )
    }

    func testTerminationRequiresConfirmationOnlyForActiveCapture() {
        XCTAssertEqual(
            VoiceLifecyclePolicy.action(
                for: .termination,
                activity: .recording
            ),
            .confirmDiscard
        )
        XCTAssertEqual(
            VoiceLifecyclePolicy.action(
                for: .termination,
                activity: .ready
            ),
            .none
        )
    }

    func testWakeAlwaysRestoresRuntimeHandlers() {
        for activity in DictationActivity.allCases {
            XCTAssertEqual(
                VoiceLifecyclePolicy.action(
                    for: .wake,
                    activity: activity
                ),
                .restoreRuntimeHandlers
            )
        }
    }
}
