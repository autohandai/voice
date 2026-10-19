import AutohandVoiceCore
import Foundation
import XCTest
@testable import AutohandVoiceBonsaiMLX

final class BonsaiTokenizerTests: XCTestCase {
    /// A tiny byte-level BPE in the same tokenizer.json format and with the
    /// same pre-tokenizer as Qwen3.5, so BPE mechanics are always tested.
    private static let miniTokenizerJSON = #"""
    {
      "version": "1.0",
      "added_tokens": [
        {"id": 20, "content": "<|im_start|>", "special": true, "normalized": false, "lstrip": false, "rstrip": false, "single_word": false},
        {"id": 21, "content": "<|im_end|>", "special": true, "normalized": false, "lstrip": false, "rstrip": false, "single_word": false},
        {"id": 22, "content": "<think>", "special": false, "normalized": false, "lstrip": false, "rstrip": false, "single_word": false}
      ],
      "normalizer": {"type": "NFC"},
      "pre_tokenizer": {"type": "Sequence", "pretokenizers": [
        {"type": "Split", "pattern": {"Regex": "(?i:'s|'t|'re|'ve|'m|'ll|'d)|[^\\r\\n\\p{L}\\p{N}]?[\\p{L}\\p{M}]+|\\p{N}| ?[^\\s\\p{L}\\p{M}\\p{N}]+[\\r\\n]*|\\s*[\\r\\n]+|\\s+(?!\\S)|\\s+"}, "behavior": "Isolated", "invert": false},
        {"type": "ByteLevel", "add_prefix_space": false, "trim_offsets": false, "use_regex": false}
      ]},
      "decoder": {"type": "ByteLevel", "add_prefix_space": false, "trim_offsets": false, "use_regex": false},
      "model": {
        "type": "BPE",
        "vocab": {"a": 0, "b": 1, "c": 2, "Ġ": 3, "ab": 4, "abc": 5, "Ġa": 6, "Ċ": 7, "é": 8, "Ã": 9, "©": 10},
        "merges": ["a b", "ab c", "Ġ a"]
      }
    }
    """#

    private func miniTokenizer() throws -> BonsaiTokenizer {
        try BonsaiTokenizer(data: Data(Self.miniTokenizerJSON.utf8))
    }

    func testMergesApplyInRankOrderNotLeftToRight() throws {
        let tokenizer = try miniTokenizer()
        // "abc" -> a b c -> ab c -> abc. " ab" -> Ġ a b: "a b" (rank 0)
        // beats "Ġ a" (rank 2), leaving Ġ + ab.
        XCTAssertEqual(tokenizer.encode("abc ab"), [5, 3, 4])
        XCTAssertEqual(tokenizer.decode([5, 3, 4]), "abc ab")
    }

    func testSpecialTokensAreMatchedLiterallyAndNeverSplit() throws {
        let tokenizer = try miniTokenizer()
        XCTAssertEqual(tokenizer.encode("<|im_start|>ab<|im_end|>"), [20, 4, 21])
        XCTAssertEqual(tokenizer.encode("a<think>b"), [0, 22, 1])
        XCTAssertEqual(tokenizer.specialTokenID("<|im_end|>"), 21)
        XCTAssertNil(tokenizer.specialTokenID("<|nope|>"))
        XCTAssertEqual(tokenizer.decode([20, 4, 21]), "<|im_start|>ab<|im_end|>")
    }

    func testByteLevelRoundTripsMultiByteCharacters() throws {
        let tokenizer = try miniTokenizer()
        // "é" is C3 A9; with no merge for it, it encodes as its two byte
        // symbols "Ã" and "©".
        XCTAssertEqual(tokenizer.encode("é"), [9, 10])
        XCTAssertEqual(tokenizer.decode([9, 10]), "é")
        XCTAssertEqual(tokenizer.bytes(for: 9), [0xC3])
    }

    func testStreamingDetokenizerHoldsBackSplitCharacters() {
        var stream = StreamingDetokenizer()
        XCTAssertEqual(stream.append([0xC3]), "")
        XCTAssertEqual(stream.append([0xA9, 0x61]), "éa")
        XCTAssertEqual(stream.append([0xF0, 0x9F]), "")
        XCTAssertEqual(stream.append([0x99, 0x82]), "🙂")
        XCTAssertEqual(stream.finish(), "")
    }

    func testRejectsTokenizerWithUnexpectedModelType() {
        let json = Self.miniTokenizerJSON.replacingOccurrences(
            of: "\"type\": \"BPE\"",
            with: "\"type\": \"Unigram\""
        )
        XCTAssertThrowsError(try BonsaiTokenizer(data: Data(json.utf8)))
    }

    // MARK: - The real Qwen3.5 tokenizer

    /// Fixture ids come from Hugging Face `tokenizers` 0.22.2 loading the
    /// pinned `tokenizer.json`. Runs when the model is installed (or
    /// `AUTOHAND_VOICE_BONSAI_TOKENIZER` points at the file).
    func testMatchesHuggingFaceTokenizerOnFixtures() throws {
        let url = try realTokenizerURL()
        let tokenizer = try BonsaiTokenizer(contentsOf: url)
        let fixtures = try loadFixtures()
        XCTAssertEqual(tokenizer.specialTokenID("<|im_start|>"), 248_045)
        XCTAssertEqual(tokenizer.specialTokenID("<|im_end|>"), 248_046)
        XCTAssertEqual(tokenizer.specialTokenID("<|endoftext|>"), 248_044)
        XCTAssertEqual(tokenizer.specialTokenID("<think>"), 248_068)
        XCTAssertEqual(tokenizer.specialTokenID("</think>"), 248_069)
        for (name, id) in fixtures.specialTokens {
            XCTAssertEqual(tokenizer.specialTokenID(name), id, name)
        }
        for item in fixtures.cases {
            XCTAssertEqual(tokenizer.encode(item.text), item.ids, "encode: \(item.text.debugDescription)")
            XCTAssertEqual(tokenizer.decode(item.ids), item.decoded, "decode: \(item.text.debugDescription)")
        }
    }

    func testChatPromptRoundTripsThroughRealTokenizer() throws {
        let tokenizer = try BonsaiTokenizer(contentsOf: try realTokenizerURL())
        let prompt = BonsaiPrompt.text(for: [
            TalkMessage(role: .system, content: "Be brief."),
            TalkMessage(role: .user, content: "Kia ora! What's 2+2? 🙂"),
        ])
        let ids = tokenizer.encode(prompt)
        XCTAssertEqual(ids.first, 248_045)
        XCTAssertEqual(ids.filter { $0 == 248_046 }.count, 2)
        XCTAssertEqual(Array(ids.suffix(4)).first, 248_068 /* <think> */ )
        XCTAssertEqual(tokenizer.decode(ids), prompt)
    }

    private struct Fixtures: Decodable {
        struct Case: Decodable {
            let text: String
            let ids: [Int]
            let decoded: String
        }

        let cases: [Case]
        let specialTokens: [String: Int]
    }

    private func loadFixtures() throws -> Fixtures {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/qwen35-tokenizer-cases.json")
        return try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
    }

    private func realTokenizerURL() throws -> URL {
        let candidates = [
            ProcessInfo.processInfo.environment["AUTOHAND_VOICE_BONSAI_TOKENIZER"]
                .map { URL(fileURLWithPath: $0) },
            BonsaiMLXModel.defaultDirectory.appendingPathComponent("tokenizer.json"),
        ].compactMap { $0 }
        guard let url = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            throw XCTSkip("Qwen3.5 tokenizer.json is not installed")
        }
        return url
    }
}
