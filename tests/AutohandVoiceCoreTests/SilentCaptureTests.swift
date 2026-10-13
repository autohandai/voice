import XCTest
@testable import AutohandVoiceCore

final class SilentCaptureTests: XCTestCase {
    func testZeroFilledCaptureIsSilent() {
        XCTAssertTrue(
            CapturedAudioLevel.isSilent([Float](repeating: 0, count: 32_000))
        )
    }

    func testQuietSpeechIsNotSilent() {
        // The CoreML model still transcribes speech peaking near 0.0025.
        var samples = [Float](repeating: 0, count: 32_000)
        samples[8_000] = 0.0025
        XCTAssertFalse(CapturedAudioLevel.isSilent(samples))
    }

    func testRoomNoiseIsNotSilent() {
        let samples = (0..<32_000).map { index in
            Float(index % 2 == 0 ? 0.004 : -0.004)
        }
        XCTAssertFalse(CapturedAudioLevel.isSilent(samples))
    }

    func testSilentRecordingNamesTheMicrophoneAndIsNotRetained() {
        let error = VoiceError.silentRecording("Zoom Audio")

        XCTAssertTrue(
            error.localizedDescription.contains("Zoom Audio")
        )
        XCTAssertEqual(error.failureCategory, .microphone(.noSignal))
        XCTAssertFalse(
            FailedCaptureRecoveryPolicy.retainsAudio(after: error)
        )
    }
}
