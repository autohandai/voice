import Foundation
import XCTest
@testable import AutohandVoiceCore

final class VocabularyTests: XCTestCase {
    func testLongestReplacementWinsWithoutCascading() {
        let rules = [
            ReplacementRule(source: "hand", replacement: "palm"),
            ReplacementRule(source: "auto hand", replacement: "Autohand"),
            ReplacementRule(source: "Autohand", replacement: "changed again"),
        ]

        XCTAssertEqual(
            VocabularyProcessor.apply(
                to: "I use auto hand every day",
                rules: rules
            ),
            "I use Autohand every day"
        )
    }

    func testReplacementUsesWordBoundariesAndPreservesCase() {
        let rule = ReplacementRule(source: "api", replacement: "endpoint")

        XCTAssertEqual(
            VocabularyProcessor.apply(
                to: "API api Api rapid",
                rules: [rule]
            ),
            "ENDPOINT endpoint Endpoint rapid"
        )
    }

    func testCSVImportReportsRowsAndKeepsValidRules() {
        let result = VocabularyImporter.csv(
            """
            source,replacement
            auto hand,Autohand
            missing-only
            g p t,GPT
            """
        )

        XCTAssertEqual(result.rules.count, 2)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.row, 3)
    }

    func testVocabularyStoreIsOwnerOnlyAndRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyStore(
            url: directory.appendingPathComponent("vocabulary.json")
        )
        let expected = [
            ReplacementRule(source: "auto hand", replacement: "Autohand")
        ]

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        let directoryPermissions = try FileManager.default.attributesOfItem(
            atPath: directory.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
    }

    func testCSVExportEscapesValuesAndRoundTrips() {
        let rules = [
            ReplacementRule(
                source: "voice, app",
                replacement: "Autohand \"Voice\"\nlocally"
            ),
        ]

        let exported = VocabularyExporter.csv(rules)
        let imported = VocabularyImporter.csv(exported)

        XCTAssertEqual(imported.rules.map(\.source), rules.map(\.source))
        XCTAssertEqual(
            imported.rules.map(\.replacement),
            rules.map(\.replacement)
        )
        XCTAssertTrue(imported.errors.isEmpty)
    }

    func testCSVImportReportsUnterminatedQuotedRow() {
        let result = VocabularyImporter.csv(
            "source,replacement\nvalid,value\n\"unfinished,value"
        )

        XCTAssertEqual(result.rules.count, 1)
        XCTAssertEqual(result.errors, [
            VocabularyImportError(
                row: 3,
                message: "Unterminated quoted field"
            ),
        ])
    }

    func testVocabularyStoreRejectsUnboundedRuleCount() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = VocabularyStore(
            url: directory.appendingPathComponent("vocabulary.json")
        )
        let rules = (0...VocabularyLimits.maximumRules).map {
            ReplacementRule(source: "source \($0)", replacement: "value")
        }

        XCTAssertThrowsError(try store.save(rules)) {
            XCTAssertEqual($0 as? VocabularyError, .tooManyRules)
        }
    }
}
