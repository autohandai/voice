import Foundation
import XCTest

final class AccessibilityBaselineTests: XCTestCase {
    func testEnglishStringCatalogCoversCriticalWorkflows() throws {
        let catalog = try loadCatalog()
        let strings = try XCTUnwrap(
            catalog["strings"] as? [String: Any]
        )
        let required = [
            "Allow microphone access",
            "Allow Accessibility access",
            "Prepare the local speech model",
            "Continue",
            "Shortcut",
            "Recording Mode",
            "Test Microphone",
            "Stop Test",
            "Copy",
            "Delete All",
            "Reset Statistics",
            "Copy Diagnostic Report",
        ]

        for key in required {
            let entry = try XCTUnwrap(
                strings[key] as? [String: Any],
                "Missing catalog entry: \(key)"
            )
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            let english = try XCTUnwrap(
                localizations["en"] as? [String: Any]
            )
            let unit = try XCTUnwrap(
                english["stringUnit"] as? [String: Any]
            )
            XCTAssertEqual(unit["state"] as? String, "translated")
            XCTAssertEqual(unit["value"] as? String, key)
        }
    }

    func testEveryCatalogEntryHasANonemptyEnglishValue() throws {
        let strings = try XCTUnwrap(
            try loadCatalog()["strings"] as? [String: Any]
        )

        XCTAssertGreaterThanOrEqual(strings.count, 90)
        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            let english = try XCTUnwrap(
                localizations["en"] as? [String: Any]
            )
            let unit = try XCTUnwrap(
                english["stringUnit"] as? [String: Any]
            )
            let value = try XCTUnwrap(unit["value"] as? String)
            XCTAssertFalse(value.isEmpty, "Empty English value for \(key)")
        }
    }

    func testAppBuildCompilesTheStringCatalog() throws {
        let script = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("xcstringstool compile"))
        XCTAssertTrue(script.contains("Localizable.xcstrings"))
    }

    private func loadCatalog() throws -> [String: Any] {
        let data = try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("Resources/Localizable.xcstrings")
        )
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
