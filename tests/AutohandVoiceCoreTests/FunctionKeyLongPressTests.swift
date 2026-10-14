import XCTest
@testable import AutohandVoiceCore

final class FunctionKeyLongPressTests: XCTestCase {
    func testCaptureStartsOnPressAndReleaseAfterHoldFinishes() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .start)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .confirmHold)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .none)
        XCTAssertEqual(reducer.reduce(.released), .finish)
        XCTAssertEqual(reducer.reduce(.released), .none)
    }

    func testShortPressDiscardsTheProvisionalCapture() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .start)
        XCTAssertEqual(reducer.reduce(.released), .discard)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .none)
    }

    func testCancellationDuringHoldCancelsAndBeforeHoldDiscards() {
        var holding = FunctionKeyLongPressReducer()
        _ = holding.reduce(.pressed)
        _ = holding.reduce(.thresholdReached)
        XCTAssertEqual(holding.reduce(.cancelled), .cancel)
        XCTAssertEqual(holding.reduce(.released), .none)

        var pending = FunctionKeyLongPressReducer()
        _ = pending.reduce(.pressed)
        XCTAssertEqual(pending.reduce(.cancelled), .discard)
    }

    func testRepeatedPressWhileDownIsIgnored() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .start)
        XCTAssertEqual(reducer.reduce(.pressed), .none)
    }
}

final class MacOSDictationConflictTests: XCTestCase {
    func testWarnsOnlyWhenFnAndMacOSDictationAreBothOn() {
        XCTAssertTrue(MacOSDictationConflict.isLikely(functionKeyEnabled: true, macOSDictationEnabled: true))
        XCTAssertFalse(MacOSDictationConflict.isLikely(functionKeyEnabled: false, macOSDictationEnabled: true))
        XCTAssertFalse(MacOSDictationConflict.isLikely(functionKeyEnabled: true, macOSDictationEnabled: false))
    }

    func testReadsDictationEnabledFromAssistantPreferences() {
        let enabled = MacOSDictationConflict.macOSDictationEnabled { key, domain in
            XCTAssertEqual(key, "Dictation Enabled")
            XCTAssertEqual(domain, "com.apple.assistant.support")
            return true
        }
        XCTAssertTrue(enabled)
        XCTAssertFalse(MacOSDictationConflict.macOSDictationEnabled { _, _ in nil })
        XCTAssertFalse(MacOSDictationConflict.macOSDictationEnabled { _, _ in false })
    }
}
