import Foundation
import XCTest
@testable import AutohandVoiceCore

final class AppLayerPreferencesTests: XCTestCase {
    func testDictationCommandsDefaultOffForExistingPreferences() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "dictationCommandsEnabled")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.dictationCommandsEnabled)
    }

    func testExistingPreferencesDecodeWithOnboardingIncomplete() throws {
        let json = """
        {
          "engine": "coreml",
          "outputMode": "clipboard",
          "pushToTalkKey": "control_option_space",
          "playSounds": false,
          "launchAtLogin": true,
          "modelVersion": "v3"
        }
        """

        let preferences = try JSONDecoder().decode(
            VoicePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(preferences.outputMode, .clipboard)
        XCTAssertFalse(preferences.playSounds)
        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
        XCTAssertTrue(preferences.showRecordingHUD)
        XCTAssertNil(preferences.audioInputDeviceUID)
        XCTAssertFalse(preferences.historyEnabled)
        XCTAssertEqual(preferences.historyRetentionDays, 30)
        XCTAssertEqual(preferences.historyMaximumItems, 500)
    }

    func testCompletedOnboardingRoundTrips() throws {
        var expected = VoicePreferences()
        expected.hasCompletedOnboarding = true

        let data = try JSONEncoder().encode(expected)
        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: data
        )

        XCTAssertEqual(decoded, expected)
    }

    func testRecordingHUDIsEnabledByDefaultAndRoundTrips() throws {
        var expected = VoicePreferences()
        XCTAssertTrue(expected.showRecordingHUD)
        expected.showRecordingHUD = false

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertFalse(decoded.showRecordingHUD)
    }

    func testSelectedAudioInputDeviceRoundTrips() throws {
        var expected = VoicePreferences()
        expected.audioInputDeviceUID = "BuiltInMicrophoneDevice"

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
    }
}
