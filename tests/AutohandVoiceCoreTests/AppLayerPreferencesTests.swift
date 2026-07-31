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

    func testLivePreviewDefaultsOffForExistingPreferences() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "livePreviewEnabled")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.livePreviewEnabled)
    }

    func testUsageInsightsDefaultOffForExistingPreferences() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "usageInsightsEnabled")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.usageInsightsEnabled)
    }

    func testMinimalContextDefaultsOffAndLocalDenylistIsBounded() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "minimalContextEnabled")
        object.removeValue(forKey: "sensitiveAppDenylist")

        let migrated = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(migrated.minimalContextEnabled)
        XCTAssertTrue(migrated.sensitiveAppDenylist.isEmpty)

        let bounded = VoicePreferences(
            minimalContextEnabled: true,
            sensitiveAppDenylist: (0 ... 150).map {
                "com.example.App\($0)"
            }
        )
        XCTAssertTrue(bounded.minimalContextEnabled)
        XCTAssertEqual(bounded.sensitiveAppDenylist.count, 128)
    }

    func testSmartFormattingDefaultsOffForExistingPreferences() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "smartFormattingEnabled")
        object.removeValue(forKey: "automaticTerminalPunctuation")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(decoded.smartFormattingEnabled)
        XCTAssertEqual(decoded.cleanupLevel, .literal)
        XCTAssertTrue(decoded.automaticTerminalPunctuation)
    }

    func testLegacySmartFormattingMigratesToEquivalentCleanupLevel() throws {
        let data = try JSONEncoder().encode(
            VoicePreferences(smartFormattingEnabled: true)
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "cleanupLevel")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.cleanupLevel, .medium)
        XCTAssertTrue(decoded.smartFormattingEnabled)
    }

    func testCleanupLevelRoundTripsAndMaintainsLegacyCompatibilityBit() throws {
        let expected = VoicePreferences(cleanupLevel: .light)

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded.cleanupLevel, .light)
        XCTAssertTrue(decoded.smartFormattingEnabled)
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
        expected.audioInputDevicePriority = [
            "StudioUSB",
            "BuiltInMicrophoneDevice",
        ]
        expected.automaticAudioHandoffEnabled = true

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
    }

    func testExistingSingleMicrophoneMigratesIntoRankedPolicy() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["audioInputDeviceUID"] = "ExistingMicrophone"
        object.removeValue(forKey: "audioInputDevicePriority")
        object.removeValue(forKey: "automaticAudioHandoffEnabled")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(
            decoded.audioInputDevicePriority,
            ["ExistingMicrophone"]
        )
        XCTAssertFalse(decoded.automaticAudioHandoffEnabled)
    }

    func testExistingPreferencesGainSafeHUDPresentationDefaults() throws {
        let data = try JSONEncoder().encode(VoicePreferences())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object.removeValue(forKey: "recordingHUDMode")
        object.removeValue(forKey: "recordingHUDOpacity")
        object.removeValue(forKey: "recordingHUDPlacements")

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.recordingHUDMode, .automatic)
        XCTAssertEqual(decoded.recordingHUDOpacity, 0.8)
        XCTAssertTrue(decoded.recordingHUDPlacements.isEmpty)
    }
}
