import Foundation
import XCTest
@testable import AutohandVoiceCore

final class PreferencesTests: XCTestCase {
    func testPointerMonitoringDefaultsOffWithKeyboardBindingIntact() {
        let preferences = VoicePreferences()

        XCTAssertFalse(preferences.pointerMonitoringEnabled)
        XCTAssertTrue(
            preferences.functionKeyLongPressEnabled,
            "Long-press Fn should be the canonical default activation"
        )
        XCTAssertEqual(
            preferences.inputBindings,
            [
                InputBinding(
                    action: .startStop,
                    trigger: .keyboard(.controlOptionSpace)
                ),
            ]
        )
        XCTAssertEqual(
            preferences.primaryActivationMethod,
            .functionKeyLongPress
        )
    }

    func testDefaultsArePrivateAndLocal() {
        let preferences = VoicePreferences()

        XCTAssertEqual(preferences.engine, .coreML)
        XCTAssertEqual(preferences.outputMode, .type)
        XCTAssertEqual(preferences.pushToTalkKey, .controlOptionSpace)
        XCTAssertEqual(preferences.shortcut, .controlOptionSpace)
        XCTAssertEqual(preferences.recordingMode, .pressAndHold)
        XCTAssertFalse(preferences.allowsRemoteServices)
    }

    func testLegacyModifierOnlyShortcutMigratesToRegisteredHotKey() throws {
        let json = """
        {
          "engine": "coreml",
          "outputMode": "type",
          "pushToTalkKey": "right_option",
          "playSounds": true,
          "launchAtLogin": false,
          "modelVersion": "v3"
        }
        """

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.pushToTalkKey, .controlOptionSpace)
        XCTAssertEqual(decoded.shortcut, .controlOptionSpace)
        XCTAssertEqual(decoded.recordingMode, .pressAndHold)
        XCTAssertTrue(decoded.functionKeyLongPressEnabled)
    }

    func testExistingPreferencesGainShortcutAndRecordingModeDefaults() throws {
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

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.shortcut, .controlOptionSpace)
        XCTAssertEqual(decoded.recordingMode, .pressAndHold)
    }

    func testRegisteredShortcutRequiresAModifierAndKnownKey() {
        XCTAssertThrowsError(
            try RegisteredShortcut(validatingKeyCode: 49, modifiers: [])
        )
        XCTAssertThrowsError(
            try RegisteredShortcut(
                validatingKeyCode: UInt32.max,
                modifiers: [.control]
            )
        )
        XCTAssertNoThrow(
            try RegisteredShortcut(
                validatingKeyCode: 49,
                modifiers: [.control, .option]
            )
        )
    }

    func testRegisteredShortcutDisplayNameUsesMacModifierOrder() {
        let shortcut = RegisteredShortcut(
            keyCode: 0,
            modifiers: [.command, .shift]
        )

        XCTAssertEqual(shortcut.displayName, "⇧⌘A")
        XCTAssertEqual(shortcut.accessibilityName, "Shift + Command + A")
    }

    func testShortcutAndRecordingModeRoundTrip() throws {
        var expected = VoicePreferences()
        expected.shortcut = RegisteredShortcut(
            keyCode: 1,
            modifiers: [.control, .shift]
        )
        expected.recordingMode = .handsFree
        expected.functionKeyLongPressEnabled = true

        let decoded = try JSONDecoder().decode(
            VoicePreferences.self,
            from: JSONEncoder().encode(expected)
        )

        XCTAssertEqual(decoded, expected)
    }

    func testPressAndHoldUsesReleaseToFinish() {
        XCTAssertEqual(
            RecordingMode.pressAndHold.action(
                for: .pressed,
                isRecording: false
            ),
            .start
        )
        XCTAssertEqual(
            RecordingMode.pressAndHold.action(
                for: .released,
                isRecording: true
            ),
            .finish
        )
    }

    func testToggleIgnoresReleaseAndSecondPressFinishes() {
        XCTAssertEqual(
            RecordingMode.toggle.action(for: .released, isRecording: true),
            .none
        )
        XCTAssertEqual(
            RecordingMode.toggle.action(for: .pressed, isRecording: true),
            .finish
        )
    }

    func testHandsFreeSupportsExplicitCancellation() {
        XCTAssertEqual(
            RecordingMode.handsFree.action(for: .cancel, isRecording: true),
            .cancel
        )
        XCTAssertEqual(
            RecordingMode.handsFree.action(for: .cancel, isRecording: false),
            .none
        )
    }

    func testInvalidPreferencesFallBackWithoutThrowing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        try Data("{not-json".utf8).write(to: url)

        XCTAssertEqual(PreferencesStore(url: url).load(), VoicePreferences())
    }

    func testPreferencesRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let store = PreferencesStore(url: url)
        var expected = VoicePreferences()
        expected.playSounds = false
        expected.outputMode = .clipboard

        try store.save(expected)

        XCTAssertEqual(store.load(), expected)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
}
