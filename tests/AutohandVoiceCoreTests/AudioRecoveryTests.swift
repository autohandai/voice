import XCTest
@testable import AutohandVoiceCore

final class AudioRecoveryTests: XCTestCase {
    func testRecoveryBufferCapsSamples() {
        var buffer = InMemoryAudioRecovery(
            maximumSamples: 4,
            expiresAfter: 60
        )

        buffer.store([1, 2, 3, 4, 5, 6], at: 10)

        XCTAssertEqual(buffer.samples(at: 11), [1, 2, 3, 4])
        XCTAssertEqual(buffer.sampleCount, 4)
    }

    func testRecoveryBufferExpires() {
        var buffer = InMemoryAudioRecovery(expiresAfter: 30)
        buffer.store([1, 2, 3], at: 10)

        XCTAssertEqual(buffer.samples(at: 39), [1, 2, 3])
        XCTAssertNil(buffer.samples(at: 40))
        XCTAssertEqual(buffer.sampleCount, 0)
    }

    func testRecoveryBufferDiscardErasesSamples() {
        var buffer = InMemoryAudioRecovery()
        buffer.store([1, 2, 3], at: 10)

        buffer.discard()

        XCTAssertNil(buffer.samples(at: 11))
        XCTAssertEqual(buffer.sampleCount, 0)
    }

    func testRecoveryBufferReportsDurationAtTargetSampleRate() {
        var buffer = InMemoryAudioRecovery(
            maximumSamples: 32_000,
            sampleRate: 16_000
        )
        buffer.store(Array(repeating: 0, count: 24_000), at: 10)

        XCTAssertEqual(buffer.duration, 1.5, accuracy: 0.001)
    }
}
