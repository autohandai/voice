import Foundation
import XCTest
@testable import AutohandVoiceCore

final class DiagnosticReportTests: XCTestCase {
    func testReportContainsOnlyExplicitRedactedFields() throws {
        let check = SystemCheck()
        let preferences = VoicePreferences()
        let report = DiagnosticReport(
            check: check,
            preferences: preferences
        )

        let data = try JSONEncoder().encode(report)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            [
                "accessibilityPermission",
                "architecture",
                "macOSVersion",
                "microphonePermission",
                "modelVersion",
                "product",
                "remoteFallbackEnabled",
                "shortcut",
                "speechEngine",
                "supported",
                "version",
            ]
        )
        XCTAssertEqual(object["product"] as? String, Brand.productName)
        XCTAssertEqual(object["remoteFallbackEnabled"] as? Bool, false)
    }
}
