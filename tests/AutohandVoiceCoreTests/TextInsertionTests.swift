import XCTest
@testable import AutohandVoiceCore

@MainActor
final class TextInsertionTests: XCTestCase {
    func testFallsBackToPasteWhenFocusedControlRejectsSelectedText() throws {
        let driver = TestTextInsertionDriver(
            directResult: .unsupported,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commit(
            Transcript(text: "native dictation", phase: .final),
            mode: .type,
            target: target
        )

        XCTAssertEqual(driver.directInsertions, ["native dictation"])
        XCTAssertEqual(driver.pasteInsertions, ["native dictation"])
    }

    func testDoesNotPasteWithoutAFocusedControl() {
        let driver = TestTextInsertionDriver(
            directResult: .noFocusedElement,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        driver.targetAvailable = false

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "do not insert", phase: .final),
                mode: .type,
                target: nil
            )
        ) { error in
            XCTAssertEqual(error as? VoiceError, .noFocusedTextField)
        }
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
    }

    func testFocusChangeNeverFallsBackToPaste() throws {
        let driver = TestTextInsertionDriver(
            directResult: .focusMoved,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "keep recoverable", phase: .final),
                mode: .type,
                target: target
            )
        ) { error in
            XCTAssertEqual(error as? VoiceError, .insertionTargetChanged)
        }
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
    }

    func testPasteFallbackRevalidatesCapturedTarget() throws {
        let driver = TestTextInsertionDriver(
            directResult: .unsupported,
            pasteResult: false
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "do not misdirect", phase: .final),
                mode: .type,
                target: target
            )
        )
        XCTAssertEqual(driver.pasteInsertions, ["do not misdirect"])
    }

    func testVerifiedFinalTextPreservesCommandLineBreaks() throws {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commitVerifiedFinalText(
            "first\nsecond\n",
            mode: .type,
            target: target
        )

        XCTAssertEqual(driver.directInsertions, ["first\nsecond\n"])
    }
}

@MainActor
private final class TestTextInsertionDriver: TextInsertionDriving {
    let directResult: DirectInsertionResult
    let pasteResult: PasteInsertionResult
    var targetAvailable = true
    var directInsertions: [String] = []
    var pasteInsertions: [String] = []

    init(directResult: DirectInsertionResult, pasteResult: Bool) {
        self.directResult = directResult
        self.pasteResult = pasteResult ? .inserted : .failed
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        true
    }

    func captureTarget() -> TextInsertionTarget? {
        targetAvailable ? TextInsertionTarget(storage: NSObject()) : nil
    }

    func insertSelectedText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        directInsertions.append(text)
        return directResult
    }

    func pastePreservingClipboard(
        _ text: String,
        target: TextInsertionTarget
    ) -> PasteInsertionResult {
        pasteInsertions.append(text)
        return pasteResult
    }
}
