import XCTest
@testable import AutohandVoiceCore

final class FunctionKeyMonitoringAuthorizationTests: XCTestCase {
    func testAccessibilityTrustIsSufficientForGlobalFnEvents() {
        XCTAssertTrue(
            FunctionKeyMonitoringAuthorization.isSufficient(
                inputMonitoringGranted: false,
                accessibilityGranted: true
            )
        )
    }

    func testInputMonitoringIsSufficientWithoutAccessibility() {
        XCTAssertTrue(
            FunctionKeyMonitoringAuthorization.isSufficient(
                inputMonitoringGranted: true,
                accessibilityGranted: false
            )
        )
    }

    func testMonitoringFailsClosedWithoutEitherAuthorization() {
        XCTAssertFalse(
            FunctionKeyMonitoringAuthorization.isSufficient(
                inputMonitoringGranted: false,
                accessibilityGranted: false
            )
        )
    }
}
