import XCTest
@testable import AutohandVoiceCore

final class AboutMetadataTests: XCTestCase {
    func testPublicIdentityAndLegalAttributionAreComplete() {
        let metadata = AboutMetadata.current

        XCTAssertEqual(metadata.productName, "Autohand Voice")
        XCTAssertEqual(metadata.companyName, "Autohand AI")
        XCTAssertFalse(metadata.version.isEmpty)
        XCTAssertTrue(metadata.upstreamAttribution.contains("Dictate"))
        XCTAssertEqual(
            metadata.noticesResourceName,
            "THIRD-PARTY-NOTICES"
        )
        XCTAssertEqual(metadata.noticesResourceExtension, "txt")
        XCTAssertEqual(
            Set(metadata.licensedComponents),
            [
                "Autohand Voice",
                "Dictate",
                "FluidAudio",
                "NVIDIA Parakeet TDT 0.6B v3",
            ]
        )
        XCTAssertEqual(
            Brand.repositoryURL.absoluteString,
            "https://github.com/autohandai/voice"
        )
    }

    func testExecutableChecksumProducesStableSHA256() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let fixture = directory.appendingPathComponent("fixture")
        try Data("abc".utf8).write(to: fixture)

        XCTAssertEqual(
            try ExecutableChecksum.sha256Hex(of: fixture),
            "ba7816bf8f01cfea414140de5dae2223"
                + "b00361a396177a9cb410ff61f20015ad"
        )
    }
}
