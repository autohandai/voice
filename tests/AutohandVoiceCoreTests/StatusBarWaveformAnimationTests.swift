import XCTest
@testable import AutohandVoiceCore

final class StatusBarWaveformAnimationTests: XCTestCase {
    func testFramesAreCompactBoundedAndAnimated() {
        XCTAssertGreaterThan(StatusBarWaveformAnimation.frameCount, 2)

        let frames = (0..<StatusBarWaveformAnimation.frameCount).map {
            StatusBarWaveformAnimation.barHeights(for: $0)
        }

        XCTAssertTrue(
            frames.allSatisfy {
                $0.count == StatusBarWaveformAnimation.barCount
            }
        )
        XCTAssertTrue(
            frames.flatMap { $0 }.allSatisfy { (0.2...1).contains($0) }
        )
        XCTAssertNotEqual(frames[0], frames[1])
    }

    func testAnimationLoopsWithoutAnExtraTerminalFrame() {
        XCTAssertEqual(
            StatusBarWaveformAnimation.barHeights(for: 0),
            StatusBarWaveformAnimation.barHeights(
                for: StatusBarWaveformAnimation.frameCount
            )
        )
    }

    func testStartupAnimationUsesACalmCadenceAndMinimumVisibility() {
        XCTAssertEqual(
            StatusBarWaveformAnimation.frameInterval,
            .milliseconds(220)
        )
        XCTAssertGreaterThanOrEqual(
            StatusBarWaveformAnimation.minimumVisibleDuration,
            1.5
        )
        XCTAssertTrue(
            StatusBarWaveformAnimation.shouldRemainVisible(
                isPreparing: false,
                startedAtUptime: 10,
                nowUptime: 11
            )
        )
        XCTAssertFalse(
            StatusBarWaveformAnimation.shouldRemainVisible(
                isPreparing: false,
                startedAtUptime: 10,
                nowUptime: 12
            )
        )
    }
}

final class StatusBarLiveWaveformTests: XCTestCase {
    func testSilenceDrawsAFlatLowLineAndSpeechRaisesTheBars() {
        let silent = StatusBarWaveformAnimation.liveBarHeights(
            levels: [0, 0, 0, 0, 0]
        )
        XCTAssertEqual(Set(silent).count, 1)
        XCTAssertLessThan(silent[0], 0.2)

        let speaking = StatusBarWaveformAnimation.liveBarHeights(
            levels: [0.3, 1, 7, -1, 0.5]
        )
        XCTAssertEqual(speaking.count, 5)
        XCTAssertEqual(speaking[1], 1, accuracy: 0.0001)
        XCTAssertEqual(speaking[2], 1, accuracy: 0.0001)
        XCTAssertEqual(speaking[3], silent[0], accuracy: 0.0001)
        XCTAssertGreaterThan(speaking[4], speaking[0])
    }
}

final class StatusBarMeterLevelTests: XCTestCase {
    func testRoomNoiseStaysFlatAndSpeechRegisters() {
        XCTAssertEqual(StatusBarWaveformAnimation.meterLevel(rms: 0), 0)
        XCTAssertEqual(StatusBarWaveformAnimation.meterLevel(rms: 0.000_5), 0)
        // Quiet speech a little way from the mic (about -40 dBFS).
        XCTAssertGreaterThan(StatusBarWaveformAnimation.meterLevel(rms: 0.01), 0.3)
        XCTAssertEqual(StatusBarWaveformAnimation.meterLevel(rms: 0.3), 1)
    }

    func testNormalSpeechLeavesHeadroomAndRoomToneStaysLow() {
        // Conversational speech near a laptop mic (about -20 dBFS) must not
        // pin the bars, or louder and softer words look the same.
        XCTAssertLessThan(StatusBarWaveformAnimation.meterLevel(rms: 0.1), 0.9)
        // Typical room tone on a MacBook mic (about -43 dBFS).
        XCTAssertLessThan(StatusBarWaveformAnimation.meterLevel(rms: 0.007), 0.32)
    }

    func testMeterRisesWithLevel() {
        let levels: [Float] = [0.001, 0.003, 0.01, 0.03, 0.1]
        let meter = levels.map { StatusBarWaveformAnimation.meterLevel(rms: $0) }
        XCTAssertEqual(meter, meter.sorted())
        XCTAssertEqual(Set(meter).count, meter.count)
    }
}
