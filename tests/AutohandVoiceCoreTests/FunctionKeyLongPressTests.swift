import XCTest
@testable import AutohandVoiceCore

final class FunctionKeyLongPressTests: XCTestCase {
    func testLongPressStartsOnceAndReleaseFinishes() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .none)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .start)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .none)
        XCTAssertEqual(reducer.reduce(.released), .finish)
        XCTAssertEqual(reducer.reduce(.released), .none)
    }

    func testShortPressLeavesFnBehaviorUntouched() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .none)
        XCTAssertEqual(reducer.reduce(.released), .none)
    }

    func testCancellationAfterActivationCancelsDictation() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed), .none)
        XCTAssertEqual(reducer.reduce(.thresholdReached), .start)
        XCTAssertEqual(reducer.reduce(.cancelled), .cancel)
        XCTAssertEqual(reducer.reduce(.released), .none)
    }
}

final class FunctionKeyRecordingModeTests: XCTestCase {
    func testToggleKeepsRecordingAfterReleaseAndNextPressFinishes() {
        for mode in [RecordingMode.toggle, .handsFree] {
            var reducer = FunctionKeyLongPressReducer()

            XCTAssertEqual(reducer.reduce(.pressed, mode: mode, isRecording: false), .none)
            XCTAssertEqual(reducer.reduce(.thresholdReached, mode: mode, isRecording: false), .start)
            XCTAssertEqual(reducer.reduce(.released, mode: mode, isRecording: true), .none)
            XCTAssertEqual(reducer.reduce(.pressed, mode: mode, isRecording: true), .finish)
            XCTAssertEqual(reducer.reduce(.thresholdReached, mode: mode, isRecording: false), .none)
            XCTAssertEqual(reducer.reduce(.released, mode: mode, isRecording: false), .none)
        }
    }

    func testToggleShortPressWhileIdleKeepsFnBehavior() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed, mode: .toggle, isRecording: false), .none)
        XCTAssertEqual(reducer.reduce(.released, mode: .toggle, isRecording: false), .none)
    }

    func testToggleStartsAgainAfterRecordingEndedElsewhere() {
        var reducer = FunctionKeyLongPressReducer()

        _ = reducer.reduce(.pressed, mode: .handsFree, isRecording: false)
        _ = reducer.reduce(.thresholdReached, mode: .handsFree, isRecording: false)
        _ = reducer.reduce(.released, mode: .handsFree, isRecording: true)
        // Escape or the HUD ended the recording; the next hold starts anew.
        XCTAssertEqual(reducer.reduce(.pressed, mode: .handsFree, isRecording: false), .none)
        XCTAssertEqual(reducer.reduce(.thresholdReached, mode: .handsFree, isRecording: false), .start)
    }

    func testFnFinishesARecordingStartedByTheShortcutInToggleMode() {
        var reducer = FunctionKeyLongPressReducer()

        XCTAssertEqual(reducer.reduce(.pressed, mode: .toggle, isRecording: true), .finish)
        XCTAssertEqual(reducer.reduce(.released, mode: .toggle, isRecording: false), .none)
    }

    func testPressAndHoldStillFinishesOnRelease() {
        var reducer = FunctionKeyLongPressReducer()

        _ = reducer.reduce(.pressed, mode: .pressAndHold, isRecording: false)
        XCTAssertEqual(reducer.reduce(.thresholdReached, mode: .pressAndHold, isRecording: false), .start)
        XCTAssertEqual(reducer.reduce(.released, mode: .pressAndHold, isRecording: true), .finish)
    }

    func testDisablingFnWhileToggleRecordingStartsCancelsIt() {
        var reducer = FunctionKeyLongPressReducer()

        _ = reducer.reduce(.pressed, mode: .toggle, isRecording: false)
        _ = reducer.reduce(.thresholdReached, mode: .toggle, isRecording: false)
        XCTAssertEqual(reducer.reduce(.cancelled, mode: .toggle, isRecording: true), .cancel)
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
