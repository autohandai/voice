import Foundation
import XCTest
@testable import AutohandVoiceCore

final class PreferencesTests: XCTestCase {
    func testDefaultsArePrivateAndLocal() {
        let preferences = VoicePreferences()

        XCTAssertEqual(preferences.engine, .coreML)
        XCTAssertEqual(preferences.outputMode, .type)
        XCTAssertEqual(preferences.pushToTalkKey, .rightOption)
        XCTAssertFalse(preferences.allowsRemoteServices)
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
