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
