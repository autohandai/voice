import XCTest
@testable import AutohandVoiceCore

final class EngineChoiceTests: XCTestCase {
    private func decodedWithout(_ key: String) throws -> VoicePreferences {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(VoicePreferences())
            ) as? [String: Any]
        )
        object.removeValue(forKey: key)
        return try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    func testExistingSettingsKeepFantailAndParakeet() throws {
        XCTAssertEqual(VoicePreferences().talkEngine, .fantail)
        XCTAssertEqual(VoicePreferences().dictationModel, .parakeet)
        XCTAssertEqual(try decodedWithout("talkEngine").talkEngine, .fantail)
        XCTAssertEqual(try decodedWithout("dictationModel").dictationModel, .parakeet)
    }

    func testLocalChoicesSurviveARoundTrip() throws {
        var preferences = VoicePreferences()
        preferences.talkEngine = .local
        preferences.dictationModel = .qwen3
        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(preferences)
        )
        XCTAssertEqual(decoded.talkEngine, .local)
        XCTAssertEqual(decoded.dictationModel, .qwen3)
    }

    func testAnUnknownEngineFallsBackToTheDefault() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(VoicePreferences())
            ) as? [String: Any]
        )
        object["talkEngine"] = "something-new"
        object["dictationModel"] = "something-new"
        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.talkEngine, .fantail)
        XCTAssertEqual(decoded.dictationModel, .parakeet)
    }

    func testOnlyFantailNeedsTheNetworkOrASignIn() {
        XCTAssertTrue(TalkEngine.fantail.usesNetwork)
        XCTAssertFalse(TalkEngine.local.usesNetwork)
        XCTAssertFalse(DictationModel.parakeet.usesNetwork)
        XCTAssertFalse(DictationModel.qwen3.usesNetwork)
    }

    func testALocalModelFailureSaysSoAndCanBeRetried() {
        let failure = TalkFailure.localModelUnavailable("Not enough memory")
        XCTAssertTrue(failure.message.contains("Not enough memory"))
        XCTAssertTrue(failure.isRetryable)
        XCTAssertNil(failure.upgradeURL)
    }
}
