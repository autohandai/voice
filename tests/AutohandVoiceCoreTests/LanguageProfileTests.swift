import Foundation
import XCTest
@testable import AutohandVoiceCore

final class LanguageProfileTests: XCTestCase {
    func testPinnedModelsExposeOnlyDocumentedLanguages() {
        XCTAssertEqual(SpeechModelVariant.v2.supportedLanguages.map(\.code), [
            "en",
        ])
        XCTAssertEqual(SpeechModelVariant.v3.supportedLanguages.count, 25)
        XCTAssertEqual(
            Set(SpeechModelVariant.v3.supportedLanguages.map(\.code)).count,
            25
        )
        XCTAssertTrue(
            SpeechModelVariant.v3.supportedLanguages.contains {
                $0.code == "pt"
            }
        )
    }

    func testEveryLanguageHasGuidanceAndATestPhrase() {
        for language in SupportedDictationLanguage.allCases {
            XCTAssertFalse(language.displayName.isEmpty)
            XCTAssertFalse(language.testPhrase.isEmpty)
        }
    }

    func testExistingPreferencesDefaultToEnglish() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "dictationLanguageCode")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.dictationLanguageCode, "en")
    }

    func testProfileLanguageUsesGlobalFallback() {
        let preferences = VoicePreferences(dictationLanguageCode: "fr")
        let global = AppProfileResolver.resolve(
            preferences: preferences,
            profiles: [],
            bundleIdentifier: nil
        )
        let profile = AppProfile(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            dictationLanguageCode: "de"
        )
        let overridden = AppProfileResolver.resolve(
            preferences: preferences,
            profiles: [profile],
            bundleIdentifier: profile.bundleIdentifier
        )

        XCTAssertEqual(global.dictationLanguageCode, "fr")
        XCTAssertEqual(overridden.dictationLanguageCode, "de")
    }

    func testPreferencesNeverPairV2WithNonEnglishLanguage() {
        let preferences = VoicePreferences(
            modelVersion: "v2",
            dictationLanguageCode: "fr"
        )

        XCTAssertEqual(preferences.modelVersion, "v3")
        XCTAssertEqual(preferences.dictationLanguageCode, "fr")
    }

    func testEnglishOnlyModelRejectsNonEnglishProfile() {
        let profile = AppProfile(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            modelVersion: "v2",
            dictationLanguageCode: "fr"
        )

        XCTAssertThrowsError(try AppProfileStore.validate([profile])) {
            XCTAssertEqual($0 as? AppProfileError, .invalidProfile)
        }
    }

    func testCacheRemovalDeletesOnlyAnExplicitAllowedDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let allowed = root.appendingPathComponent("v2", isDirectory: true)
        let unrelated = root.appendingPathComponent("unrelated", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: allowed,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: unrelated,
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(
            try ModelCacheManager.removeCache(
                at: unrelated,
                allowedDirectories: [allowed]
            )
        )
        try ModelCacheManager.removeCache(
            at: allowed,
            allowedDirectories: [allowed]
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: allowed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
