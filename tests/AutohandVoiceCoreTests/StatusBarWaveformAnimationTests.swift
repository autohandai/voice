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
