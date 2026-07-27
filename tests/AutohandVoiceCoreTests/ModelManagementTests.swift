import Foundation
import XCTest
@testable import AutohandVoiceCore

final class ModelManagementTests: XCTestCase {
    func testSupportedModelVariantsHaveExplicitLanguageCoverage() {
        XCTAssertEqual(SpeechModelVariant.v2.languageCoverage, "English")
        XCTAssertEqual(
            SpeechModelVariant.v3.languageCoverage,
            "Multilingual (25 European languages)"
        )
        XCTAssertEqual(SpeechModelVariant.default, .v3)
    }

    func testCacheInspectorCountsOnlyRegularFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("nested"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data(repeating: 1, count: 7).write(
            to: directory.appendingPathComponent("model.bin")
        )
        try Data(repeating: 2, count: 5).write(
            to: directory.appendingPathComponent("nested/vocab.json")
        )

        XCTAssertEqual(
            try ModelCacheInspector.storageBytes(at: directory),
            12
        )
    }

    func testModelFailureClassificationIsActionable() {
        XCTAssertEqual(
            ModelFailureKind.classify("The Internet connection appears offline"),
            .download
        )
        XCTAssertEqual(
            ModelFailureKind.classify("Missing coremldata.bin"),
            .storage
        )
        XCTAssertEqual(
            ModelFailureKind.classify("Failed to compile model"),
            .compilation
        )
        XCTAssertEqual(
            ModelFailureKind.classify("Could not load CoreML model"),
            .loading
        )
    }
}
