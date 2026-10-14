import XCTest
@testable import AutohandVoiceCore

final class VoiceLevelHistoryTests: XCTestCase {
    func testSilenceDrawsAFlatLine() {
        var history = VoiceLevelHistory(barCount: 9)
        for _ in 0..<20 { history.push(0) }
        XCTAssertEqual(history.barLevels, Array(repeating: 0, count: 9))
    }

    func testNewestLevelSitsInTheMiddleAndMovesOutward() {
        var history = VoiceLevelHistory(barCount: 5)
        history.push(1)
        XCTAssertEqual(history.barLevels, [0, 0, 1, 0, 0])

        history.push(0)
        XCTAssertEqual(history.barLevels[2], 0)
        XCTAssertEqual(history.barLevels[1], 1)
        XCTAssertEqual(history.barLevels[3], 1)

        history.push(0)
        XCTAssertEqual(history.barLevels, [1, 0, 0, 0, 1])

        history.push(0)
        XCTAssertEqual(history.barLevels, [0, 0, 0, 0, 0])
    }

    func testBarsFollowTheRealShapeOfTheVoice() {
        var history = VoiceLevelHistory(barCount: 7)
        for level in [0.2, 0.9, 0.5, 0.7] { history.push(level) }
        XCTAssertEqual(history.barLevels, [0.2, 0.9, 0.5, 0.7, 0.5, 0.9, 0.2])
    }

    func testLevelsAreClampedAndTheHistoryStaysBounded() {
        var history = VoiceLevelHistory(barCount: 4)
        for _ in 0..<1_000 { history.push(7) }
        history.push(-3)
        XCTAssertEqual(history.barLevels.count, 4)
        XCTAssertTrue(history.barLevels.allSatisfy { (0...1).contains($0) })
        XCTAssertEqual(history.storedLevelCount, 2)
    }

    func testResetClearsTheShape() {
        var history = VoiceLevelHistory(barCount: 3)
        history.push(1)
        history.reset()
        XCTAssertEqual(history.barLevels, [0, 0, 0])
    }
}
