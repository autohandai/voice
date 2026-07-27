import XCTest
@testable import AutohandVoiceCore

final class SmartFormattingTests: XCTestCase {
    func testFormatsAtDocumentStartAndEnd() {
        let context = TextInsertionContext(
            isAtDocumentStart: true,
            isAtDocumentEnd: true
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "hello world",
                context: context,
                enabled: true,
                addsTerminalPunctuation: true
            ),
            "Hello world."
        )
    }

    func testAddsSpacesForMidWordBoundaries() {
        let context = TextInsertionContext(
            precedingCharacter: "o",
            followingCharacter: "w"
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "there",
                context: context,
                enabled: true,
                addsTerminalPunctuation: false
            ),
            " there "
        )
    }

    func testDoesNotAddSpacesAroundDelimiters() {
        let context = TextInsertionContext(
            precedingCharacter: "(",
            followingCharacter: ")",
            hasSelection: true
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "inside",
                context: context,
                enabled: true,
                addsTerminalPunctuation: false
            ),
            "inside"
        )
    }

    func testCapitalizesAfterSentenceAndParagraphBreaks() {
        let context = TextInsertionContext(
            precedingCharacter: ".",
            isAtDocumentEnd: true
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "hello.\nnext paragraph",
                context: context,
                enabled: true,
                addsTerminalPunctuation: true
            ),
            " Hello.\nNext paragraph."
        )
    }

    func testDoesNotDuplicateSpokenTerminalPunctuation() {
        let context = TextInsertionContext(
            isAtDocumentStart: true,
            isAtDocumentEnd: true
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "are you ready?",
                context: context,
                enabled: true,
                addsTerminalPunctuation: true
            ),
            "Are you ready?"
        )
    }

    func testUnknownContextDoesNotGuess() {
        XCTAssertEqual(
            SmartTextFormatter.format(
                "leave this alone",
                context: .unknown,
                enabled: true,
                addsTerminalPunctuation: true
            ),
            "leave this alone"
        )
    }

    func testDisabledFormattingIsLiteral() {
        let context = TextInsertionContext(
            isAtDocumentStart: true,
            isAtDocumentEnd: true
        )

        XCTAssertEqual(
            SmartTextFormatter.format(
                "do not change",
                context: context,
                enabled: false,
                addsTerminalPunctuation: true
            ),
            "do not change"
        )
    }
}
