import XCTest
@testable import AutohandVoiceCore

final class RecordingHUDThemeTests: XCTestCase {
    func testFlowIsTheDefaultForNewAndExistingPreferences() throws {
        XCTAssertEqual(VoicePreferences().recordingHUDTheme, .flow)

        let existing = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: existing) as? [String: Any]
        )
        object.removeValue(forKey: "recordingHUDTheme")
        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.recordingHUDTheme, .flow)
    }

    func testClassicSurvivesARoundTrip() throws {
        var preferences = VoicePreferences()
        preferences.recordingHUDTheme = .classic
        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(preferences)
        )
        XCTAssertEqual(decoded.recordingHUDTheme, .classic)
    }

    func testFlowWindowFitsThePillAndItsMessages() {
        let size = RecordingHUDPlacement.flowContentSize
        XCTAssertGreaterThanOrEqual(size.width, 300)
        XCTAssertLessThanOrEqual(size.height, 64)
    }
}

final class TalkPreferenceTests: XCTestCase {
    func testTalkIsOnByDefaultAndSurvivesARoundTrip() throws {
        XCTAssertTrue(VoicePreferences().talkEnabled)

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(VoicePreferences())
            ) as? [String: Any]
        )
        object.removeValue(forKey: "talkEnabled")
        XCTAssertTrue(
            try JSONDecoder().decode(
                VoicePreferences.self,
                from: JSONSerialization.data(withJSONObject: object)
            ).talkEnabled
        )

        var preferences = VoicePreferences()
        preferences.talkEnabled = false
        XCTAssertFalse(
            try JSONDecoder().decode(
                VoicePreferences.self,
                from: JSONEncoder().encode(preferences)
            ).talkEnabled
        )
    }
}
