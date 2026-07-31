import XCTest
@testable import AutohandVoiceCore

final class InputBindingTests: XCTestCase {
    func testAcceptsAtMostFourDistinctBindings() throws {
        let configuration = try InputConfiguration(
            bindings: [
                .init(
                    action: .startStop,
                    trigger: .keyboard(.controlOptionSpace)
                ),
                .init(action: .cancel, trigger: .pointer(button: 2)),
                .init(action: .holdToTalk, trigger: .pointer(button: 3)),
                .init(action: .commit, trigger: .pointer(button: 4)),
            ]
        )

        XCTAssertEqual(configuration.bindings.count, 4)
    }

    func testRejectsPrimarySecondaryAndExcessPointerBindings() {
        for button in [0, 1] {
            XCTAssertThrowsError(
                try InputConfiguration(
                    bindings: [
                        .init(
                            action: .startStop,
                            trigger: .pointer(button: button)
                        ),
                    ]
                )
            ) { error in
                XCTAssertEqual(
                    error as? InputConfigurationError,
                    .reservedPointerButton
                )
            }
        }

        XCTAssertThrowsError(
            try InputConfiguration(
                bindings: (2 ... 6).map {
                    .init(action: .startStop, trigger: .pointer(button: $0))
                }
            )
        ) { error in
            XCTAssertEqual(
                error as? InputConfigurationError,
                .tooManyBindings
            )
        }
    }

    func testRejectsConflictingTriggersWithoutMutatingPriorConfiguration() throws {
        let original = try InputConfiguration(
            bindings: [
                .init(
                    action: .startStop,
                    trigger: .keyboard(.controlOptionSpace)
                ),
            ]
        )
        var active = original

        XCTAssertThrowsError(
            try active.replaceBindings([
                .init(action: .startStop, trigger: .pointer(button: 3)),
                .init(action: .cancel, trigger: .pointer(button: 3)),
            ])
        ) { error in
            XCTAssertEqual(
                error as? InputConfigurationError,
                .conflictingTrigger
            )
        }
        XCTAssertEqual(active, original)
    }

    func testHoldBindingReducesButtonRacesToStartThenFinish() {
        var reducer = InputBindingReducer()
        let binding = InputBinding(
            action: .holdToTalk,
            trigger: .pointer(button: 4)
        )

        XCTAssertEqual(reducer.reduce(.pressed, binding: binding), .start)
        XCTAssertEqual(reducer.reduce(.pressed, binding: binding), .none)
        XCTAssertEqual(reducer.reduce(.released, binding: binding), .finish)
        XCTAssertEqual(reducer.reduce(.released, binding: binding), .none)
    }

    func testCancelAndCommitOnlyFireOnPress() {
        var reducer = InputBindingReducer()

        XCTAssertEqual(
            reducer.reduce(
                .pressed,
                binding: .init(
                    action: .cancel,
                    trigger: .pointer(button: 2)
                )
            ),
            .cancel
        )
        XCTAssertEqual(
            reducer.reduce(
                .released,
                binding: .init(
                    action: .commit,
                    trigger: .pointer(button: 3)
                )
            ),
            .none
        )
        XCTAssertEqual(
            reducer.reduce(
                .pressed,
                binding: .init(
                    action: .commit,
                    trigger: .pointer(button: 3)
                )
            ),
            .commit
        )
    }
}
