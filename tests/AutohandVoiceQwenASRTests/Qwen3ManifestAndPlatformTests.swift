import AutohandVoiceCore
import Foundation
import XCTest
@testable import AutohandVoiceQwenASR

final class Qwen3ModelManifestTests: XCTestCase {
    func testDefaultManifestPinsTheExactRepositoryRevisionAndHashes() {
        let manifest = Qwen3ModelManifest.default
        XCTAssertEqual(manifest.repository, "aufklarer/Qwen3-ASR-0.6B-MLX-4bit")
        XCTAssertEqual(manifest.revision, "bc441bd1e4295c1f42d9879f056049a925b6e013")
        XCTAssertTrue(manifest.isPinned)
        XCTAssertEqual(
            manifest.files.map(\.name),
            ["model.safetensors", "vocab.json", "merges.txt", "tokenizer_config.json"]
        )
        XCTAssertEqual(
            manifest.files.first?.sha256,
            "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf"
        )
        XCTAssertEqual(manifest.totalBytes, 712_698_118)
    }

    func testRemoteURLsUseHTTPSAndTheCommitNotABranch() {
        let manifest = Qwen3ModelManifest.default
        for file in manifest.files {
            let url = manifest.remoteURL(for: file)
            XCTAssertEqual(url.scheme, "https")
            XCTAssertEqual(url.host, "huggingface.co")
            XCTAssertEqual(
                url.absoluteString,
                "https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit/resolve/bc441bd1e4295c1f42d9879f056049a925b6e013/\(file.name)"
            )
            XCTAssertFalse(url.absoluteString.contains("/main/"))
        }
    }

    func testCacheDirectoryIsASiblingOfTheParakeetModels() {
        let directory = Qwen3ModelManifest.default.defaultCacheDirectory
        XCTAssertEqual(directory.lastPathComponent, "qwen3-asr-0.6b-mlx-4bit")
        XCTAssertEqual(
            directory.deletingLastPathComponent().standardizedFileURL,
            SpeechModelVariant.v3.cacheDirectory.deletingLastPathComponent().standardizedFileURL
        )
    }

    func testUnpinnedOrUnsafeManifestsAreRejected() {
        let file = Qwen3ModelFile(name: "model.safetensors", sha256: String(repeating: "0", count: 64), size: 1)
        func manifest(revision: String = String(repeating: "b", count: 40), files: [Qwen3ModelFile]) -> Qwen3ModelManifest {
            Qwen3ModelManifest(repository: "a/b", revision: revision, files: files, directoryName: "x")
        }
        XCTAssertTrue(manifest(files: [file]).isPinned)
        XCTAssertFalse(manifest(revision: "main", files: [file]).isPinned)
        XCTAssertFalse(manifest(files: []).isPinned)
        XCTAssertFalse(manifest(files: [
            Qwen3ModelFile(name: "../escape", sha256: file.sha256, size: 1),
        ]).isPinned)
        XCTAssertFalse(manifest(files: [
            Qwen3ModelFile(name: "model.safetensors", sha256: "abc", size: 1),
        ]).isPinned)
        XCTAssertFalse(manifest(files: [file, file]).isPinned)
    }

    func testDownloaderRefusesAnUnpinnedManifest() async {
        let downloader = Qwen3ModelDownloader(
            manifest: Qwen3ModelManifest(repository: "a/b", revision: "main", files: [], directoryName: "x")
        )
        do {
            try await downloader.install(
                into: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
                onProgress: nil
            )
            XCTFail("expected failure")
        } catch let error as Qwen3ModelDownloadError {
            XCTAssertEqual(error, .unpinnedManifest)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

final class Qwen3PlatformTests: XCTestCase {
    func testSupportRequiresAppleSiliconAndMetal() {
        XCTAssertTrue(Qwen3Platform.isSupported(architecture: .arm64, hasMetalDevice: true))
        XCTAssertFalse(Qwen3Platform.isSupported(architecture: .arm64, hasMetalDevice: false))
        XCTAssertFalse(Qwen3Platform.isSupported(architecture: .x86_64, hasMetalDevice: true))
        XCTAssertFalse(Qwen3Platform.isSupported(architecture: .x86_64, hasMetalDevice: false))
    }

    func testCurrentSliceGating() {
        #if arch(arm64)
        XCTAssertEqual(Qwen3Platform.currentArchitecture, .arm64)
        #else
        XCTAssertEqual(Qwen3Platform.currentArchitecture, .x86_64)
        XCTAssertFalse(Qwen3SpeechRecognizer.isSupportedOnThisMac)
        XCTAssertNotNil(Qwen3SpeechRecognizer.unsupportedReason)
        #endif
        XCTAssertEqual(
            Qwen3SpeechRecognizer.isSupportedOnThisMac,
            Qwen3SpeechRecognizer.unsupportedReason == nil
        )
    }

    func testMetalLibraryLookupMirrorsMLXSearchOrder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen3-metallib-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let macOS = root.appendingPathComponent("Contents/MacOS", isDirectory: true)
        let resources = root.appendingPathComponent("Contents/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let executable = macOS.appendingPathComponent("autohand-voice-stt")

        XCTAssertNil(Qwen3Platform.locateMetalLibrary(executableURL: executable, resourceURL: resources, bundleURL: nil))

        let bundled = resources.appendingPathComponent(
            "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        )
        try FileManager.default.createDirectory(
            at: bundled.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([1]).write(to: bundled)
        XCTAssertEqual(
            Qwen3Platform.locateMetalLibrary(executableURL: executable, resourceURL: resources, bundleURL: nil)?.standardizedFileURL,
            bundled.standardizedFileURL
        )

        let colocated = macOS.appendingPathComponent("mlx.metallib")
        try Data([1]).write(to: colocated)
        XCTAssertEqual(
            Qwen3Platform.locateMetalLibrary(executableURL: executable, resourceURL: resources, bundleURL: nil)?.standardizedFileURL,
            colocated.standardizedFileURL
        )
    }

    func testLanguageHintsUseQwenLanguageNames() {
        XCTAssertEqual(Qwen3LanguageHint.name(forCode: "en"), "English")
        XCTAssertEqual(Qwen3LanguageHint.name(forCode: "fr"), "French")
        XCTAssertEqual(Qwen3LanguageHint.name(forCode: "de"), "German")
        XCTAssertEqual(Qwen3LanguageHint.name(forCode: "pt-BR"), "Portuguese")
        XCTAssertNil(Qwen3LanguageHint.name(forCode: "mt"), "unsupported languages auto-detect")
        XCTAssertNil(Qwen3LanguageHint.name(forCode: ""))
    }
}

final class Qwen3SpeechRecognizerGatingTests: XCTestCase {
    func testUnsupportedMacFailsBeforeAnyDownload() async throws {
        StubHubProtocol.reset([:])
        let configuration = Qwen3ModelDownloader.makeSessionConfiguration()
        configuration.protocolClasses = [StubHubProtocol.self]
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen3-gate-\(UUID().uuidString)", isDirectory: true)
        let recognizer = Qwen3SpeechRecognizer(
            cacheDirectory: directory,
            downloader: Qwen3ModelDownloader(sessionConfiguration: configuration),
            environment: Qwen3RuntimeEnvironment(
                isSupported: false,
                unsupportedReason: "Qwen3-ASR requires a Mac with Apple Silicon.",
                metalLibraryURL: nil
            )
        )

        do {
            try await recognizer.prepare()
            XCTFail("expected unsupported failure")
        } catch let error as VoiceError {
            guard case let .modelUnavailable(reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("Apple Silicon"))
        }
        do {
            _ = try await recognizer.transcribe(samples: [0, 0.1, 0.2], sampleRate: 16_000)
            XCTFail("expected unsupported failure")
        } catch is VoiceError {}
        XCTAssertEqual(StubHubProtocol.requestedPaths, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testMissingMetalLibraryFailsBeforeAnyDownload() async throws {
        StubHubProtocol.reset([:])
        let configuration = Qwen3ModelDownloader.makeSessionConfiguration()
        configuration.protocolClasses = [StubHubProtocol.self]
        let recognizer = Qwen3SpeechRecognizer(
            cacheDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen3-gate-\(UUID().uuidString)", isDirectory: true),
            downloader: Qwen3ModelDownloader(sessionConfiguration: configuration),
            environment: Qwen3RuntimeEnvironment(
                isSupported: true,
                unsupportedReason: nil,
                metalLibraryURL: nil
            )
        )

        do {
            try await recognizer.prepare()
            XCTFail("expected missing metallib failure")
        } catch let error as VoiceError {
            guard case let .modelUnavailable(reason) = error else {
                return XCTFail("unexpected \(error)")
            }
            XCTAssertTrue(reason.contains("mlx.metallib"))
        }
        XCTAssertEqual(StubHubProtocol.requestedPaths, [])
    }

    func testEmptyRecordingIsRejected() async {
        let recognizer = Qwen3SpeechRecognizer()
        do {
            _ = try await recognizer.transcribe(samples: [], sampleRate: 16_000)
            XCTFail("expected failure")
        } catch let error as VoiceError {
            XCTAssertEqual(error, .recordingTooShort)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}
