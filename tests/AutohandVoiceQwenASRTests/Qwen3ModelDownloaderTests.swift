import CryptoKit
import Foundation
import XCTest
@testable import AutohandVoiceQwenASR

/// Serves canned responses for the Hugging Face host so downloader tests
/// never touch the network.
final class StubHubProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var body: Data
        /// Bytes per `didLoad` call, to exercise incremental hashing.
        var chunkSize: Int = 7
        /// When true the response never completes (for cancellation).
        var hang: Bool = false
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: Response] = [:]
    nonisolated(unsafe) private static var requested: [String] = []

    static func reset(_ values: [String: Response]) {
        lock.lock()
        responses = values
        requested = []
        lock.unlock()
    }

    static var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return requested
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "huggingface.co"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self.requested.append(url.path)
        let response = Self.responses[url.lastPathComponent]
        Self.lock.unlock()

        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": "\(response.body.count)"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if response.hang { return }
        var offset = 0
        while offset < response.body.count {
            let end = min(offset + response.chunkSize, response.body.count)
            client?.urlProtocol(self, didLoad: response.body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class Qwen3ModelDownloaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen3-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        StubHubProtocol.reset([:])
    }

    private let weights = Data((0..<1_000).map { UInt8($0 % 251) })
    private let vocab = Data(#"{"a":1}"#.utf8)

    private func sha(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func manifest() -> Qwen3ModelManifest {
        Qwen3ModelManifest(
            repository: "example/test-model",
            revision: String(repeating: "a", count: 40),
            files: [
                Qwen3ModelFile(name: "model.safetensors", sha256: sha(weights), size: Int64(weights.count)),
                Qwen3ModelFile(name: "vocab.json", sha256: sha(vocab), size: Int64(vocab.count)),
            ],
            directoryName: "test-model"
        )
    }

    private func downloader() -> Qwen3ModelDownloader {
        let configuration = Qwen3ModelDownloader.makeSessionConfiguration()
        configuration.protocolClasses = [StubHubProtocol.self]
        return Qwen3ModelDownloader(manifest: manifest(), sessionConfiguration: configuration)
    }

    private func leftovers() -> [String] {
        let staging = directory.appendingPathComponent(Qwen3ModelDownloader.stagingDirectoryName)
        return (try? FileManager.default.contentsOfDirectory(atPath: staging.path)) ?? []
    }

    func testInstallDownloadsPinnedRevisionVerifiesAndReportsProgress() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(body: weights),
            "vocab.json": .init(body: vocab),
        ])
        let recorder = ProgressRecorder()

        try await downloader().install(into: directory) { recorder.append($0) }

        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")), weights)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("vocab.json")), vocab)
        XCTAssertEqual(
            StubHubProtocol.requestedPaths.sorted(),
            [
                "/example/test-model/resolve/\(String(repeating: "a", count: 40))/model.safetensors",
                "/example/test-model/resolve/\(String(repeating: "a", count: 40))/vocab.json",
            ]
        )
        XCTAssertTrue(downloader().isInstalled(in: directory))
        XCTAssertTrue(try downloader().verify(in: directory))
        XCTAssertEqual(leftovers(), [])

        let values = recorder.values
        XCTAssertFalse(values.isEmpty)
        XCTAssertEqual(values.last?.completedBytes, Int64(weights.count + vocab.count))
        XCTAssertEqual(values.last?.completedFiles, 2)
        XCTAssertEqual(values.last?.totalFiles, 2)
        XCTAssertEqual(values.last?.fractionCompleted, 1)
        XCTAssertEqual(
            values.map(\.completedBytes),
            values.map(\.completedBytes).sorted(),
            "progress must be monotonic"
        )
    }

    func testChecksumMismatchIsRejectedAndNothingIsInstalled() async throws {
        var tampered = weights
        tampered[10] ^= 0xFF
        StubHubProtocol.reset([
            "model.safetensors": .init(body: tampered),
            "vocab.json": .init(body: vocab),
        ])

        do {
            try await downloader().install(into: directory, onProgress: nil)
            XCTFail("expected checksum failure")
        } catch let error as Qwen3ModelDownloadError {
            XCTAssertEqual(error, .checksumMismatch(file: "model.safetensors"))
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("model.safetensors").path
        ))
        XCTAssertFalse(downloader().isInstalled(in: directory))
        XCTAssertEqual(leftovers(), [])
    }

    func testOversizedResponseIsAbortedAtTheBound() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(body: weights + Data(repeating: 0, count: 64)),
            "vocab.json": .init(body: vocab),
        ])

        do {
            try await downloader().install(into: directory, onProgress: nil)
            XCTFail("expected size failure")
        } catch let error as Qwen3ModelDownloadError {
            XCTAssertEqual(error, .sizeMismatch(file: "model.safetensors"))
        }
        XCTAssertEqual(leftovers(), [])
    }

    func testHTTPErrorIsSurfaced() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(status: 404, body: Data("missing".utf8)),
            "vocab.json": .init(body: vocab),
        ])

        do {
            try await downloader().install(into: directory, onProgress: nil)
            XCTFail("expected HTTP failure")
        } catch let error as Qwen3ModelDownloadError {
            XCTAssertEqual(error, .httpStatus(file: "model.safetensors", status: 404))
        }
    }

    func testFailedDownloadLeavesExistingFileUntouched() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let existing = directory.appendingPathComponent("model.safetensors")
        let previous = Data(repeating: 9, count: weights.count)
        try previous.write(to: existing)
        var tampered = weights
        tampered[0] ^= 0x01
        StubHubProtocol.reset([
            "model.safetensors": .init(body: tampered),
            "vocab.json": .init(body: vocab),
        ])

        do {
            try await downloader().install(into: directory, onProgress: nil)
            XCTFail("expected checksum failure")
        } catch is Qwen3ModelDownloadError {}

        XCTAssertEqual(try Data(contentsOf: existing), previous)
    }

    func testCorruptCachedFileIsReplacedAtomically() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(body: weights),
            "vocab.json": .init(body: vocab),
        ])
        try await downloader().install(into: directory, onProgress: nil)
        // Same size, different bytes: only a hash check can catch this.
        try Data(repeating: 3, count: weights.count)
            .write(to: directory.appendingPathComponent("model.safetensors"))
        XCTAssertFalse(try downloader().verify(in: directory))

        try await downloader().repair(in: directory, onProgress: nil)

        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("model.safetensors")), weights)
        XCTAssertTrue(try downloader().verify(in: directory))
    }

    func testInstalledModelIsNotDownloadedAgain() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(body: weights),
            "vocab.json": .init(body: vocab),
        ])
        try await downloader().install(into: directory, onProgress: nil)
        StubHubProtocol.reset([:])
        let recorder = ProgressRecorder()

        try await downloader().install(into: directory) { recorder.append($0) }

        XCTAssertEqual(StubHubProtocol.requestedPaths, [])
        XCTAssertEqual(recorder.values, [], "no download progress for an installed model")
    }

    func testCancellationStopsDownloadAndCleansStaging() async throws {
        StubHubProtocol.reset([
            "model.safetensors": .init(body: weights, hang: true),
            "vocab.json": .init(body: vocab),
        ])
        let downloader = downloader()
        let directory = directory!
        let task = Task {
            try await downloader.install(into: directory, onProgress: nil)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()

        do {
            try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {}
        XCTAssertEqual(leftovers(), [])
        XCTAssertFalse(downloader.isInstalled(in: directory))
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Qwen3DownloadProgress] = []

    func append(_ value: Qwen3DownloadProgress) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [Qwen3DownloadProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
