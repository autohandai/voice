import Foundation
import XCTest
@testable import AutohandVoiceCore

final class AppProfileTests: XCTestCase {
    func testExactBundleIdentifierOverridesGlobalPreferences() {
        let profile = AppProfile(
            name: "Terminal",
            bundleIdentifier: "com.apple.Terminal",
            outputMode: .clipboard,
            recordingMode: .toggle,
            dictationCommandsEnabled: false,
            smartFormattingEnabled: false,
            automaticTerminalPunctuation: false,
            showRecordingHUD: false,
            playSounds: false
        )

        let resolved = AppProfileResolver.resolve(
            preferences: VoicePreferences(
                outputMode: .type,
                playSounds: true,
                showRecordingHUD: true,
                recordingMode: .pressAndHold,
                dictationCommandsEnabled: true,
                smartFormattingEnabled: true
            ),
            profiles: [profile],
            bundleIdentifier: "com.apple.Terminal"
        )

        XCTAssertEqual(resolved.profileID, profile.id)
        XCTAssertEqual(resolved.outputMode, .clipboard)
        XCTAssertEqual(resolved.recordingMode, .toggle)
        XCTAssertFalse(resolved.smartFormattingEnabled)
        XCTAssertFalse(resolved.automaticTerminalPunctuation)
        XCTAssertFalse(resolved.showRecordingHUD)
    }

    func testUnknownAndLocalizedNamesUseGlobalFallback() {
        let preferences = VoicePreferences(
            outputMode: .clipboard,
            recordingMode: .handsFree
        )
        let profiles = [
            AppProfile(
                name: "Notes",
                bundleIdentifier: "com.apple.Notes"
            ),
        ]

        XCTAssertNil(
            AppProfileResolver.resolve(
                preferences: preferences,
                profiles: profiles,
                bundleIdentifier: "Notes"
            ).profileID
        )
        XCTAssertEqual(
            AppProfileResolver.resolve(
                preferences: preferences,
                profiles: profiles,
                bundleIdentifier: nil
            ).recordingMode,
            .handsFree
        )
    }

    func testProfileStoreIsOwnerOnlyAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppProfileStore(
            url: directory.appendingPathComponent("profiles.json")
        )
        let profiles = [
            AppProfile(name: "Editor", bundleIdentifier: "com.example.Editor"),
        ]

        try store.save(profiles)

        XCTAssertEqual(try store.load(), profiles)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testDuplicateBundleIdentifiersAreRejected() {
        let profiles = [
            AppProfile(name: "One", bundleIdentifier: "com.example.App"),
            AppProfile(name: "Two", bundleIdentifier: "com.example.App"),
        ]

        XCTAssertThrowsError(
            try AppProfileStore.validate(profiles)
        ) {
            XCTAssertEqual($0 as? AppProfileError, .duplicateBundleIdentifier)
        }
    }

    func testUnknownModelVariantIsRejected() {
        let profiles = [
            AppProfile(
                name: "Editor",
                bundleIdentifier: "com.example.Editor",
                modelVersion: "remote-model"
            ),
        ]

        XCTAssertThrowsError(try AppProfileStore.validate(profiles)) {
            XCTAssertEqual($0 as? AppProfileError, .invalidProfile)
        }
    }
}
