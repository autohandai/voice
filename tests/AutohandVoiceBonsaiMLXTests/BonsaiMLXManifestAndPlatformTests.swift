import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation
import XCTest
@testable import AutohandVoiceBonsaiMLX

final class BonsaiMLXManifestTests: XCTestCase {
    func testManifestPinsTheExactRevisionFilesAndHashes() {
        let manifest = BonsaiMLXModel.manifest
        XCTAssertEqual(manifest.repository, "prism-ml/Ternary-Bonsai-2-2B-mlx-2bit")
        XCTAssertEqual(manifest.revision, "1c6cbae21f8c38830ce337972b46fdae7b18eaaa")
        XCTAssertTrue(manifest.isPinned)
        XCTAssertEqual(manifest.directoryName, "ternary-bonsai-2-2b-mlx")
        let byName = Dictionary(uniqueKeysWithValues: manifest.files.map { ($0.name, $0) })
        XCTAssertEqual(
            byName["model.safetensors"]?.sha256,
            "da5095b9f34d7f0d5094090afeeadf124eef821c75136dc28957ce586ae7ac0c"
        )
        XCTAssertEqual(byName["model.safetensors"]?.size, 1_200_284_784)
        XCTAssertEqual(
            byName["tokenizer.json"]?.sha256,
            "5f9e4d4901a92b997e463c1f46055088b6cca5ca61a6522d1b9f64c4bb81cb42"
        )
        XCTAssertEqual(
            byName["config.json"]?.sha256,
            "f8d80cb7fd148b8841e63051c337d2758b4bc16243c577d35eaab6779534b591"
        )
    }

    func testDownloadsOnlyWhatTheSwiftRuntimeNeeds() {
        let names = Set(BonsaiMLXModel.manifest.files.map(\.name))
        XCTAssertEqual(names, [
            "model.safetensors",
            "config.json",
            "tokenizer.json",
            "generation_config.json",
            "LICENSE",
            "NOTICE.txt",
        ])
        XCTAssertFalse(names.contains { $0.hasPrefix("runtime") || $0.hasSuffix(".py") })
        XCTAssertFalse(names.contains { $0.contains("mmproj") })
    }

    func testRemoteURLsUseTheCommitOverHTTPS() {
        let manifest = BonsaiMLXModel.manifest
        for file in manifest.files {
            let url = manifest.remoteURL(for: file)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(
                url.absoluteString,
                "https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-mlx-2bit/resolve/1c6cbae21f8c38830ce337972b46fdae7b18eaaa/\(file.name)"
            )
        }
    }

    func testInstallsNextToTheGGUFModelNotInsideIt() {
        let directory = BonsaiMLXModel.defaultDirectory
        XCTAssertEqual(directory.lastPathComponent, "ternary-bonsai-2-2b-mlx")
        XCTAssertEqual(
            directory.deletingLastPathComponent().standardizedFileURL,
            LocalModelManifest.bonsai2B.directory.deletingLastPathComponent().standardizedFileURL
        )
    }
}

final class BonsaiMLXPlatformTests: XCTestCase {
    func testIntelAndRosettaAreNeverSupported() {
        XCTAssertFalse(BonsaiMLXEnvironment.isSupported(architecture: .x86_64, hasAppleGPU: true))
        XCTAssertFalse(BonsaiMLXEnvironment.isSupported(architecture: .arm64, hasAppleGPU: false))
        XCTAssertTrue(BonsaiMLXEnvironment.isSupported(architecture: .arm64, hasAppleGPU: true))
    }

    func testIntelReasonPointsToTheLlamaCppRuntime() {
        let environment = BonsaiMLXEnvironment.make(
            architecture: .x86_64,
            hasAppleGPU: false,
            metalLibraryURL: nil
        )
        XCTAssertFalse(environment.isSupported)
        XCTAssertEqual(
            environment.unavailableReason,
            "The MLX runtime needs a Mac with Apple Silicon. Talk uses llama.cpp on this Mac."
        )
    }

    func testMissingMetalLibraryIsReportedNotCrashed() {
        let environment = BonsaiMLXEnvironment.make(
            architecture: .arm64,
            hasAppleGPU: true,
            metalLibraryURL: nil
        )
        XCTAssertFalse(environment.isSupported)
        XCTAssertNotNil(environment.unavailableReason)
        XCTAssertTrue(environment.unavailableReason!.contains("mlx.metallib"))
    }

    func testCurrentEnvironmentMatchesTheCompiledSlice() {
        #if arch(x86_64)
        XCTAssertFalse(BonsaiMLXEnvironment.current.isSupported)
        #endif
        XCTAssertEqual(
            BonsaiMLXEnvironment.current.architecture,
            Qwen3Platform.currentArchitecture
        )
    }

    func testUnsupportedEngineFailsBeforeDownloadingOrTouchingMLX() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bonsai-mlx-\(UUID().uuidString)")
        let engine = BonsaiMLXEngine(
            directory: directory,
            environment: .make(architecture: .x86_64, hasAppleGPU: false, metalLibraryURL: nil)
        )
        XCTAssertEqual(engine.runtime, .mlx)
        XCTAssertNotNil(engine.unavailableReason)
        do {
            try await engine.prepare { _ in }
            XCTFail("prepare should fail on an unsupported Mac")
        } catch let error as BonsaiMLXError {
            guard case .unavailable = error else {
                return XCTFail("unexpected \(error)")
            }
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        var failed = false
        do {
            for try await _ in engine.reply(to: [TalkMessage(role: .user, content: "hi")], maxTokens: 4) {}
        } catch {
            failed = true
        }
        XCTAssertTrue(failed)
    }
}
