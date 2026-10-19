import AutohandVoiceCore
import AutohandVoiceLLM
import Foundation

/// Talk's on-device model (Ternary Bonsai 2 via llama.cpp). Loads when a
/// question starts and frees its memory after a while without questions.
@MainActor
final class BonsaiTalkModel: LocalTalkModel {
    static let idleUnloadDelay: Duration = .seconds(600)

    private let engine = LocalTalkEngine()
    private var idleTask: Task<Void, Never>?
    private(set) var downloadProgress: Double?

    var isReady: Bool { engine.isLoaded }
    var isInstalled: Bool { engine.isInstalled }
    var displayName: String { engine.manifest.displayName }
    var downloadSize: Int64 { engine.manifest.file.size }
    var unavailableReason: String? { nil }

    func prepare(
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        idleTask?.cancel()
        try await engine.prepare(onProgress: onProgress)
        scheduleIdleUnload()
    }

    /// Starts loading while the person is still speaking.
    func prepareInBackground() {
        guard !engine.isLoaded else { return }
        Task { [weak self] in
            try? await self?.prepare { _ in }
        }
    }

    func reply(
        to messages: [TalkMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        idleTask?.cancel()
        let stream = engine.reply(to: messages, maxTokens: maxTokens)
        scheduleIdleUnload()
        return stream
    }

    func removeDownloadedModel() throws {
        idleTask?.cancel()
        try engine.removeDownloadedModel()
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleUnloadDelay)
            guard !Task.isCancelled else { return }
            self?.engine.unload()
        }
    }
}
