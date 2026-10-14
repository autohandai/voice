import CryptoKit
import Foundation
import XCTest
@testable import AutohandVoiceCore

final class LocalTransformTests: XCTestCase {
    func testMissingModelReturnsInputUntouched() async {
        let engine = LocalTransformEngine()
        let request = LocalTransformRequest(
            input: "keep this exact text",
            languageCode: "en",
            preset: .polish
        )

        let proposal = await engine.propose(request)

        XCTAssertEqual(proposal.output, request.input)
        XCTAssertEqual(proposal.failure, .modelUnavailable)
        XCTAssertTrue(proposal.changes.isEmpty)
    }

    func testSecureAndUnsupportedLanguageReturnInputUntouched() async {
        let runner = StubTransformRunner(
            supportedLanguageCodes: ["en"],
            output: "changed"
        )
        let engine = LocalTransformEngine(runner: runner)

        let secure = await engine.propose(
            LocalTransformRequest(
                input: "secret",
                languageCode: "en",
                preset: .polish,
                isSecureTarget: true
            )
        )
        let unsupported = await engine.propose(
            LocalTransformRequest(
                input: "bonjour",
                languageCode: "fr",
                preset: .polish
            )
        )

        XCTAssertEqual(secure.output, "secret")
        XCTAssertEqual(secure.failure, .secureTarget)
        XCTAssertEqual(unsupported.output, "bonjour")
        XCTAssertEqual(unsupported.failure, .unsupportedLanguage)
    }

    func testValidLocalRunnerProducesBoundedChangeSummary() async {
        let runner = StubTransformRunner(
            supportedLanguageCodes: ["en"],
            output: "Clearer local text."
        )
        let engine = LocalTransformEngine(runner: runner)

        let proposal = await engine.propose(
            LocalTransformRequest(
                input: "local text",
                languageCode: "en",
                preset: .polish
            )
        )

        XCTAssertEqual(proposal.output, "Clearer local text.")
        XCTAssertEqual(proposal.modelVersion, "test-local-v1")
        XCTAssertNil(proposal.failure)
        XCTAssertEqual(proposal.changes.count, 1)
    }

    func testSignedManifestBindsExactLocalModel() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let modelURL = directory.appendingPathComponent("Transform.mlmodelc")
        try FileManager.default.createDirectory(
            at: modelURL,
            withIntermediateDirectories: true
        )
        try Data("compiled-coreml-fixture".utf8).write(
            to: modelURL.appendingPathComponent("model.mil")
        )
        try Data("weights".utf8).write(
            to: modelURL.appendingPathComponent("weights.bin")
        )
        let digest = try LocalTransformArtifactValidator.artifactDigest(
            at: modelURL
        )
        let privateKey = Curve25519.Signing.PrivateKey()
        let unsigned = LocalTransformModelManifest(
            modelVersion: "test-local-v1",
            modelSHA256: digest.sha256,
            signature: Data(),
            licenseIdentifier: "fixture-only",
            modelByteCount: digest.byteCount,
            supportedLanguageCodes: ["en"]
        )
        let payload = try XCTUnwrap(unsigned.signedPayload)
        let signature = try privateKey.signature(for: payload)
        let signed = LocalTransformModelManifest(
            modelVersion: "test-local-v1",
            modelSHA256: digest.sha256,
            signature: signature,
            licenseIdentifier: "fixture-only",
            modelByteCount: digest.byteCount,
            supportedLanguageCodes: ["en"]
        )
        let manifestData = try JSONEncoder().encode(signed)

        #if arch(arm64)
        let artifact = try LocalTransformArtifactValidator.validate(
            manifestData: manifestData,
            modelURL: modelURL,
            signerPublicKey: privateKey.publicKey.rawRepresentation,
            languageCode: "en"
        )

        XCTAssertEqual(artifact.manifest, signed)
        XCTAssertEqual(artifact.modelURL, modelURL)
        #else
        // Local Transforms need the Neural Engine, so Intel rejects them.
        XCTAssertThrowsError(
            try LocalTransformArtifactValidator.validate(
                manifestData: manifestData,
                modelURL: modelURL,
                signerPublicKey: privateKey.publicKey.rawRepresentation,
                languageCode: "en"
            )
        ) { error in
            XCTAssertEqual(
                error as? LocalTransformArtifactError,
                .unsupportedPlatform
            )
        }
        #endif
    }

    func testTemplateStoreRejectsUnboundedTemplatesAndIsOwnerOnly()
        throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = TransformTemplateStore(
            url: directory.appendingPathComponent("templates.json")
        )
        let template = TransformTemplate(
            name: "Ticket",
            instruction: "Turn this into a concise support ticket."
        )
        try store.save([template])

        XCTAssertEqual(try store.load(), [template])
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)

        XCTAssertThrowsError(
            try TransformTemplateStore.validate(
                (0...LocalTransformLimits.maximumTemplates).map {
                    TransformTemplate(
                        name: "Template \($0)",
                        instruction: "Local only"
                    )
                }
            )
        ) {
            XCTAssertEqual(
                $0 as? TransformTemplateStoreError,
                .tooManyTemplates
            )
        }
    }
}

private struct StubTransformRunner: LocalTransformRunning {
    let modelVersion = "test-local-v1"
    let supportedLanguageCodes: Set<String>
    let output: String

    init(
        supportedLanguageCodes: Set<String>,
        output: String
    ) {
        self.supportedLanguageCodes = supportedLanguageCodes
        self.output = output
    }

    func run(
        input _: String,
        instruction _: String
    ) async throws -> String {
        output
    }
}
