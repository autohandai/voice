import Foundation
import XCTest
@testable import AutohandVoiceCore

final class DictationCommandTests: XCTestCase {
    func testExplicitCommandsInsertPunctuationAndLineBreaks() {
        let result = DictationCommandProcessor.process(
            """
            Hello command comma world command new line next command \
            question mark command new paragraph done command period
            """,
            enabled: true,
            locale: Locale(identifier: "en_NZ")
        )

        XCTAssertEqual(result.text, "Hello, world\nnext?\n\ndone.")
        XCTAssertFalse(result.shouldCancel)
        XCTAssertEqual(result.commandsApplied, 5)
    }

    func testAmbiguousPhrasesRemainLiteral() {
        let text = "This is a new line of products with a question mark logo."

        XCTAssertEqual(
            DictationCommandProcessor.process(
                text,
                enabled: true,
                locale: Locale(identifier: "en_US")
            ).text,
            text
        )
    }

    func testCommandsCanBeDisabled() {
        let text = "Hello command new line world"

        XCTAssertEqual(
            DictationCommandProcessor.process(
                text,
                enabled: false,
                locale: Locale(identifier: "en_GB")
            ).text,
            text
        )
    }

    func testLiteralModeLeavesRemainingCommandPhrasesUntouched() {
        let result = DictationCommandProcessor.process(
            "Prefix command literal mode command period and command new line",
            enabled: true,
            locale: Locale(identifier: "en_CA")
        )

        XCTAssertEqual(
            result.text,
            "Prefix command period and command new line"
        )
        XCTAssertEqual(result.commandsApplied, 1)
    }

    func testScratchThatClearsOnlyCurrentUncommittedBuffer() {
        let result = DictationCommandProcessor.process(
            "Discard these words command scratch that keep this",
            enabled: true,
            locale: Locale(identifier: "en_AU")
        )

        XCTAssertEqual(result.text, "keep this")
        XCTAssertFalse(result.shouldCancel)
    }

    func testCancelDictationProducesNoCommitText() {
        let result = DictationCommandProcessor.process(
            "Do not insert this command cancel dictation",
            enabled: true,
            locale: Locale(identifier: "en_US")
        )

        XCTAssertTrue(result.shouldCancel)
        XCTAssertEqual(result.text, "")
    }

    func testUnsupportedLocaleLeavesEnglishCommandPhraseLiteral() {
        let text = "bonjour command new line monde"

        XCTAssertEqual(
            DictationCommandProcessor.process(
                text,
                enabled: true,
                locale: Locale(identifier: "fr_FR")
            ).text,
            text
        )
    }
}
