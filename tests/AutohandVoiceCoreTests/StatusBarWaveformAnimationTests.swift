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
    func testSilenceDrawsAFlatLowLine() {
        let heights = StatusBarWaveformAnimation.liveBarHeights(level: 0, frame: 3)
        XCTAssertEqual(heights.count, StatusBarWaveformAnimation.barCount)
        XCTAssertEqual(Set(heights).count, 1)
        XCTAssertLessThan(heights[0], 0.2)
    }

    func testLouderInputDrawsTallerBoundedBars() {
        let quiet = StatusBarWaveformAnimation.liveBarHeights(level: 0.2, frame: 0)
        let loud = StatusBarWaveformAnimation.liveBarHeights(level: 1, frame: 0)
        XCTAssertGreaterThan(loud.reduce(0, +), quiet.reduce(0, +))
        XCTAssertEqual(loud.max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertTrue((quiet + loud).allSatisfy { (0...1).contains($0) })
        XCTAssertTrue(StatusBarWaveformAnimation.liveBarHeights(level: 7, frame: 0).allSatisfy { $0 <= 1 })
    }

    func testSpeechMovesBetweenFrames() {
        XCTAssertNotEqual(
            StatusBarWaveformAnimation.liveBarHeights(level: 0.8, frame: 0),
            StatusBarWaveformAnimation.liveBarHeights(level: 0.8, frame: 1)
        )
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

    func testMeterRisesWithLevel() {
        let levels: [Float] = [0.001, 0.003, 0.01, 0.03, 0.1]
        let meter = levels.map { StatusBarWaveformAnimation.meterLevel(rms: $0) }
        XCTAssertEqual(meter, meter.sorted())
        XCTAssertEqual(Set(meter).count, meter.count)
    }
}
