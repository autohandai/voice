import XCTest
@testable import AutohandVoiceCore

final class SpeechRefinementTests: XCTestCase {
    func testRemovesHighConfidenceFillersAndAccidentalRepetition() {
        let refined = SpeechTextRefiner.refine(
            "Um, we should, uh, ship this this week.",
            enabled: true
        )

        XCTAssertEqual(refined, "we should ship this week.")
    }

    func testCollapsesRepeatedShortPhrase() {
        let refined = SpeechTextRefiner.refine(
            "We should launch we should launch on Tuesday.",
            enabled: true
        )

        XCTAssertEqual(refined, "We should launch on Tuesday.")
    }

    func testPreservesMeaningfulEmphasisAndLiteralPhrases() {
        let text = "I really really like this, and I mean what I say."

        XCTAssertEqual(
            SpeechTextRefiner.refine(text, enabled: true),
            text
        )
    }

    func testDisabledRefinementIsLiteral() {
        let text = "Um, keep this this exactly."

        XCTAssertEqual(
            SpeechTextRefiner.refine(text, enabled: false),
            text
        )
    }

    func testVocabularyStillOwnsUncommonNameCorrections() {
        let refined = SpeechTextRefiner.refine(
            "Please ask eager costa.",
            enabled: true
        )
        let corrected = VocabularyProcessor.apply(
            to: refined,
            rules: [
                ReplacementRule(
                    source: "eager costa",
                    replacement: "Igor Costa"
                ),
            ]
        )

        XCTAssertEqual(corrected, "Please ask Igor Costa.")
    }
}
