import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation

/// Talk's on-device model on MLX: Ternary Bonsai 2 (2B) from its 2-bit
/// Hadamard pack, on the Apple Silicon GPU. Same contract as the llama.cpp
/// `LocalTalkEngine`: downloads and verifies once, loads, and streams
/// replies with any reasoning removed. Nothing leaves the Mac after the
/// one-time download. On Intel and under Rosetta every entry point fails
/// with `BonsaiMLXError.unavailable` before touching MLX or the network.
public final class BonsaiMLXEngine: OnDeviceTalkEngine, @unchecked Sendable {
    public let directory: URL
    public let environment: BonsaiMLXEnvironment
    public let sampling: BonsaiSamplingSettings
    private let downloader: Qwen3ModelDownloader
    private let lock = NSLock()
    private var loadTask: Task<Void, Error>?
    #if arch(arm64)
    private let mlx = BonsaiMLXRuntime()
    #endif

    public init(
        directory: URL = BonsaiMLXModel.defaultDirectory,
        environment: BonsaiMLXEnvironment = .current,
        sampling: BonsaiSamplingSettings = BonsaiSamplingSettings(),
        downloader: Qwen3ModelDownloader = Qwen3ModelDownloader(manifest: BonsaiMLXModel.manifest)
    ) {
        self.directory = directory
        self.environment = environment
        self.sampling = sampling
        self.downloader = downloader
    }

    public var runtime: LocalTalkRuntime { .mlx }
    public var displayName: String { BonsaiMLXModel.displayName }
    public var downloadSize: Int64 { downloader.manifest.totalBytes }
    public var unavailableReason: String? { environment.unavailableReason }

    public var isInstalled: Bool { downloader.isInstalled(in: directory) }

    public var isLoaded: Bool {
        #if arch(arm64)
        environment.isSupported && mlx.isLoaded
        #else
        false
        #endif
    }

    /// Downloads (first use only) and loads the model. Concurrent callers
    /// share one load.
    public func prepare(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try checkEnvironment()
        #if arch(arm64)
        if mlx.isLoaded {
            onProgress(1)
            return
        }
        let task: Task<Void, Error> = lock.withLock {
            if let loadTask { return loadTask }
            let downloader = downloader
            let directory = directory
            let mlx = mlx
            let created = Task {
                try await downloader.install(into: directory) { progress in
                    // Leave the last step for loading.
                    onProgress(min(0.95, progress.fractionCompleted * 0.95))
                }
                try Task.checkCancellation()
                try await mlx.load(directory: directory)
                onProgress(1)
            }
            loadTask = created
            return created
        }
        do {
            try await task.value
            lock.withLock { loadTask = nil }
        } catch {
            lock.withLock { loadTask = nil }
            throw error
        }
        #endif
    }

    /// Streams the reply text for a conversation (system prompt first).
    public func reply(
        to messages: [TalkMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        reply(to: messages, maxTokens: maxTokens, seed: nil, onFinish: nil)
    }

    /// `reply` with a fixed sampling seed and generation statistics, for the
    /// CLI and tests.
    public func reply(
        to messages: [TalkMessage],
        maxTokens: Int,
        seed: UInt64?,
        onFinish: (@Sendable (LocalTalkGenerationStatistics) -> Void)?
    ) -> AsyncThrowingStream<String, Error> {
        do {
            try checkEnvironment()
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
        #if arch(arm64)
        let pieces = mlx.generate(
            prompt: BonsaiPrompt.text(for: messages),
            maxTokens: maxTokens,
            settings: sampling,
            seed: seed,
            onFinish: onFinish
        )
        return AsyncThrowingStream { continuation in
            let task = Task {
                var filter = ThinkingFilter()
                do {
                    for try await piece in pieces {
                        let text = filter.append(piece)
                        if !text.isEmpty { continuation.yield(text) }
                    }
                    let rest = filter.finish()
                    if !rest.isEmpty { continuation.yield(rest) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: BonsaiMLXError.unavailable(
            self.environment.unavailableReason ?? "MLX is unavailable on this Mac."
        )) }
        #endif
    }

    /// Frees the model's memory; it reloads on the next question.
    public func unload() {
        #if arch(arm64)
        if environment.isSupported { mlx.unload() }
        #endif
    }

    /// Deletes the downloaded MLX model folder (never the GGUF one).
    public func removeDownloadedModel() throws {
        unload()
        let target = directory.standardizedFileURL
        guard target.lastPathComponent == downloader.manifest.directoryName else {
            throw BonsaiMLXError.invalidModel("refusing to delete \(target.path)")
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    private func checkEnvironment() throws {
        guard environment.isSupported else {
            throw BonsaiMLXError.unavailable(
                environment.unavailableReason ?? "MLX is unavailable on this Mac."
            )
        }
    }
}
