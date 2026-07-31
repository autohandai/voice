import Foundation
import XCTest
@testable import AutohandVoiceCore

final class DictationStyleTests: XCTestCase {
    func testTemporaryStyleWinsOverExactAppAndDefaultStyle() {
        let global = DictationStylePreset(
            name: "Global",
            cleanupLevel: .literal,
            automaticTerminalPunctuation: false
        )
        let app = DictationStylePreset(
            name: "App",
            cleanupLevel: .light,
            automaticTerminalPunctuation: false
        )
        let temporary = DictationStylePreset(
            name: "Temporary",
            cleanupLevel: .medium,
            automaticTerminalPunctuation: true,
            vocabularyEnabled: false
        )
        let profile = AppProfile(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            styleID: app.id
        )

        let resolved = AppProfileResolver.resolve(
            preferences: VoicePreferences(defaultStyleID: global.id),
            profiles: [profile],
            bundleIdentifier: profile.bundleIdentifier,
            styles: [global, app, temporary],
            temporaryStyleID: temporary.id
        )

        XCTAssertEqual(resolved.styleID, temporary.id)
        XCTAssertEqual(resolved.styleSource, .temporary)
        XCTAssertEqual(resolved.cleanupLevel, .medium)
        XCTAssertTrue(resolved.automaticTerminalPunctuation)
        XCTAssertFalse(resolved.vocabularyEnabled)
    }

    func testAppStyleWinsOverDefaultWithoutTemporaryOverride() {
        let global = DictationStylePreset(
            name: "Global",
            cleanupLevel: .literal,
            automaticTerminalPunctuation: false
        )
        let app = DictationStylePreset(
            name: "App",
            cleanupLevel: .light,
            automaticTerminalPunctuation: false
        )
        let profile = AppProfile(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            styleID: app.id
        )

        let resolved = AppProfileResolver.resolve(
            preferences: VoicePreferences(defaultStyleID: global.id),
            profiles: [profile],
            bundleIdentifier: profile.bundleIdentifier,
            styles: [global, app]
        )

        XCTAssertEqual(resolved.styleID, app.id)
        XCTAssertEqual(resolved.styleSource, .appProfile)
    }

    func testTemporaryStyleExpirationUsesMonotonicTime() {
        XCTAssertTrue(
            TemporaryStylePolicy.isActive(
                expiresAtUptime: 1_000,
                nowUptime: 999
            )
        )
        XCTAssertFalse(
            TemporaryStylePolicy.isActive(
                expiresAtUptime: 1_000,
                nowUptime: 1_000
            )
        )
    }

    func testCustomStyleStoreIsOwnerOnlyAndBounded() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = DictationStyleStore(
            url: directory.appendingPathComponent("styles.json")
        )
        let styles = [
            DictationStylePreset(
                name: "Email",
                cleanupLevel: .medium,
                automaticTerminalPunctuation: true
            ),
        ]

        try store.save(styles)

        XCTAssertEqual(try store.load(), styles)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }
}
