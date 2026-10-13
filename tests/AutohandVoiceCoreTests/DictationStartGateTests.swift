import XCTest
@testable import AutohandVoiceCore

final class DictationStartGateTests: XCTestCase {
    func testReadySessionCanStart() {
        XCTAssertTrue(DictationStartGate().canStart)
    }

    func testFailedSessionWithoutRecoverableAudioCanStartAgain() {
        var gate = DictationStartGate()
        gate.activity = .failed

        XCTAssertTrue(
            gate.canStart,
            "A failed attempt must not block the next recording; onboarding cannot be finished otherwise."
        )
    }

    func testBusySessionCannotStart() {
        var gate = DictationStartGate()
        gate.activity = .busy

        XCTAssertFalse(gate.canStart)
    }

    func testRecoverableAudioStillBlocksANewRecording() {
        var gate = DictationStartGate()
        gate.activity = .failed
        gate.hasRecoverableAudio = true

        XCTAssertFalse(gate.canStart)
    }

    func testModelAndExclusiveActivitiesBlockStart() {
        for mutate: (inout DictationStartGate) -> Void in [
            { $0.isEnabled = false },
            { $0.modelReady = false },
            { $0.isTestingMicrophone = true },
            { $0.isCheckingPersistentRecovery = true },
            { $0.hasPendingPersistentRecovery = true },
            { $0.isFileTranscriptionActive = true },
        ] {
            var gate = DictationStartGate()
            mutate(&gate)
            XCTAssertFalse(gate.canStart)
        }
    }

    func testAudioWithNoRecognizedWordsIsNotRetained() {
        XCTAssertFalse(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: VoiceError.emptyTranscript
            ),
            "Retrying audio that produced no words yields the same empty result and blocks new recordings."
        )
        XCTAssertFalse(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: VoiceError.recordingTooShort
            )
        )
        XCTAssertFalse(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: RevisionError.emptyText
            )
        )
    }

    func testAudioIsRetainedForRecoverableFailures() {
        XCTAssertTrue(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: VoiceError.modelUnavailable("offline")
            )
        )
        XCTAssertTrue(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: VoiceError.textInsertionFailed
            )
        )
        XCTAssertTrue(
            FailedCaptureRecoveryPolicy.retainsAudio(
                after: CancellationError()
            )
        )
    }
}
