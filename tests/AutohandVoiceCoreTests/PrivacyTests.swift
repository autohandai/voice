import XCTest
@testable import AutohandVoiceCore

final class PrivacyTests: XCTestCase {
    func testRemoteEnginesAreNotPartOfNativeContract() {
        XCTAssertEqual(SpeechEngine.allCases, [.coreML])
    }

    func testEnvironmentUsesCanonicalPrefix() {
        XCTAssertEqual(Brand.environmentPrefix, "AUTOHAND_VOICE_")
        XCTAssertEqual(Brand.bundleIdentifier, "ai.autohand.voice")
    }

    func testSystemCheckNeverEnablesRemoteFallback() {
        XCTAssertFalse(SystemCheck().remoteFallbackEnabled)
    }
}
