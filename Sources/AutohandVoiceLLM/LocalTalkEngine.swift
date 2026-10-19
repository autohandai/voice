import AutohandVoiceCore
import Foundation

/// The on-device Talk model: downloads and verifies it once, loads it into
/// llama.cpp, and streams replies with any reasoning removed. Nothing leaves
/// the Mac after the one-time download.
public final class LocalTalkEngine: @unchecked Sendable {
    public let manifest: LocalModelManifest
    private let runtime = LlamaChatRuntime()
    private let lock = NSLock()
    private var loadTask: Task<Void, Error>?

    public init(manifest: LocalModelManifest = .bonsai2B) {
        self.manifest = manifest
    }

    public var isInstalled: Bool {
        VerifiedModelDownload.isInstalled(manifest.file, in: manifest.directory)
    }

    public var isLoaded: Bool { runtime.isLoaded }

    /// Downloads (first use only) and loads the model. Concurrent callers
    /// share one load.
    public func prepare(
        onProgress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        if runtime.isLoaded {
            onProgress(1)
            return
        }
        let task: Task<Void, Error> = lock.withLock {
            if let loadTask { return loadTask }
            let manifest = manifest
            let runtime = runtime
            let created = Task {
                let url = try await VerifiedModelDownload.ensure(
                    manifest.file,
                    in: manifest.directory,
                    onProgress: onProgress
                )
                try await runtime.load(modelAt: url)
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
    }

    /// Streams the reply text for a conversation (system prompt first).
    public func reply(
        to messages: [TalkMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        let pieces = runtime.generate(
            prompt: BonsaiPrompt.text(for: messages),
            maxTokens: maxTokens
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
    }

    /// Frees the model's memory; it reloads on the next question.
    public func unload() {
        runtime.unload()
    }

    public func removeDownloadedModel() throws {
        runtime.unload()
        try VerifiedModelDownload.remove(manifest.file, in: manifest.directory)
    }
}
