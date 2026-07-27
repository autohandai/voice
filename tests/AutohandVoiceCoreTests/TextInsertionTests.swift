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

        try inserter.commit(
            Transcript(text: "native dictation", phase: .final),
            mode: .type
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

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "do not insert", phase: .final),
                mode: .type
            )
        ) { error in
            XCTAssertEqual(error as? VoiceError, .noFocusedTextField)
        }
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
    }
}

@MainActor
private final class TestTextInsertionDriver: TextInsertionDriving {
    let directResult: DirectInsertionResult
    let pasteResult: Bool
    var directInsertions: [String] = []
    var pasteInsertions: [String] = []

    init(directResult: DirectInsertionResult, pasteResult: Bool) {
        self.directResult = directResult
        self.pasteResult = pasteResult
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        true
    }

    func insertSelectedText(_ text: String) -> DirectInsertionResult {
        directInsertions.append(text)
        return directResult
    }

    func pastePreservingClipboard(_ text: String) -> Bool {
        pasteInsertions.append(text)
        return pasteResult
    }
}
