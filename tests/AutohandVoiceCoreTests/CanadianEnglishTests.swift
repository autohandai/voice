import Foundation
import XCTest
@testable import AutohandVoiceCore

final class CanadianEnglishTests: XCTestCase {
    func testRecommendationAppearsOnceOnlyForSupportedCanadianEnglish() {
        XCTAssertTrue(
            CanadianEnglishRecommendation.shouldPresent(
                locale: Locale(identifier: "en_CA"),
                dictationLanguageCode: "en",
                modelSupportsEnglish: true,
                response: .notPresented
            )
        )
        XCTAssertFalse(
            CanadianEnglishRecommendation.shouldPresent(
                locale: Locale(identifier: "en_US"),
                dictationLanguageCode: "en",
                modelSupportsEnglish: true,
                response: .notPresented
            )
        )
        XCTAssertFalse(
            CanadianEnglishRecommendation.shouldPresent(
                locale: Locale(identifier: "en_CA"),
                dictationLanguageCode: "en",
                modelSupportsEnglish: true,
                response: .dismissed
            )
        )
    }

    func testCanadianFormatterIsBoundedToEnglishWholeWordsAndCase() {
        XCTAssertEqual(
            CanadianEnglishFormatter.apply(
                to: "Color centers honor colorful neighbors.",
                policy: .canadian,
                languageCode: "en"
            ),
            "Colour centres honour colorful neighbours."
        )
        XCTAssertEqual(
            CanadianEnglishFormatter.apply(
                to: "color center",
                policy: .canadian,
                languageCode: "fr"
            ),
            "color center"
        )
        XCTAssertEqual(
            CanadianEnglishFormatter.apply(
                to: "color center",
                policy: .automatic,
                languageCode: "en"
            ),
            "color center"
        )
    }

    func testLiteralNeverRewritesCanadianSpelling() async throws {
        let raw = try RawFinalTranscript(
            text: "My favorite color",
            languageCode: "en"
        )
        let result = await Revision().propose(
            raw: raw,
            policy: RevisionPolicy(
                level: .literal,
                englishSpellingPolicy: .canadian
            )
        )

        XCTAssertEqual(result.revision.text, raw.text)
    }

    func testExplicitVocabularyHasPriorityOverCanadianPolicy()
        async throws
    {
        let raw = try RawFinalTranscript(
            text: "My favorite color",
            languageCode: "en"
        )
        let result = await Revision().propose(
            raw: raw,
            policy: RevisionPolicy(
                level: .light,
                vocabularyRules: [
                    ReplacementRule(
                        source: "colour",
                        replacement: "COLOR"
                    ),
                ],
                englishSpellingPolicy: .canadian
            )
        )

        XCTAssertEqual(result.revision.text, "My favourite COLOR")
    }

    func testExistingPreferencesGainNonMutatingSpellingDefaults()
        throws
    {
        let json = """
        {
          "engine": "coreml",
          "outputMode": "type",
          "pushToTalkKey": "control_option_space",
          "playSounds": true,
          "launchAtLogin": false,
          "modelVersion": "v3"
        }
        """

        let preferences = try JSONDecoder().decode(
            VoicePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(preferences.englishSpellingPolicy, .automatic)
        XCTAssertEqual(
            preferences.canadianEnglishRecommendation,
            .notPresented
        )
    }
}
