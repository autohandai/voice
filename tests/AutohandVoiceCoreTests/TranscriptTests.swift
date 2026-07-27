import XCTest
@testable import AutohandVoiceCore

final class TranscriptTests: XCTestCase {
    func testOnlyFinalTranscriptCanBeCommitted() throws {
        let provisional = Transcript(text: "hello wor", phase: .provisional)
        XCTAssertThrowsError(try provisional.finalText())

        let final = Transcript(text: "  hello world  ", phase: .final)
        XCTAssertEqual(try final.finalText(), "hello world")
    }

    func testRepeatedAdjacentPhrasesAreCollapsed() {
        XCTAssertEqual(
            TranscriptNormalizer.normalize("Hello world. Hello world."),
            "Hello world."
        )
    }

    func testAggregatorIsBounded() {
        var aggregator = TranscriptAggregator(maximumCharacters: 12)
        aggregator.append("first")
        aggregator.append("second")
        aggregator.append("third")

        XCTAssertEqual(aggregator.text, "second third")
    }
}
