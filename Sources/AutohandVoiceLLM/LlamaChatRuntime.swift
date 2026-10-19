import AutohandVoiceCore
import Foundation
import OSLog
import llama

/// Runs a GGUF chat model with llama.cpp on a dedicated queue, so neither the
/// main thread nor Swift's cooperative pool ever blocks on inference.
/// Metal on Apple Silicon; CPU on Intel.
public final class LlamaChatRuntime: @unchecked Sendable {
    public struct Sampling: Sendable {
        public var temperature: Float = 0.7
        public var topP: Float = 0.8
        public var topK: Int32 = 20
        public var presencePenalty: Float = 1.5
        public var contextLength: UInt32 = 4_096

        public init() {}
    }

    public enum Failure: Error, LocalizedError {
        case loadFailed
        case contextFailed
        case promptTooLong(Int)
        case decodeFailed(Int32)

        public var errorDescription: String? {
            switch self {
            case .loadFailed: "The model file couldn't be loaded."
            case .contextFailed: "There isn't enough memory to run the model."
            case let .promptTooLong(count):
                "The conversation is too long for the model (\(count) tokens)."
            case let .decodeFailed(code): "The model stopped unexpectedly (\(code))."
            }
        }
    }

    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "local-llm"
    )
    private static let backend: Void = {
        llama_log_set({ level, text, _ in
            guard level == GGML_LOG_LEVEL_ERROR, let text else { return }
            LlamaChatRuntime.logger.error("\(String(cString: text))")
        }, nil)
        llama_backend_init()
    }()

    private let queue = DispatchQueue(
        label: "ai.autohand.voice.local-llm",
        qos: .userInitiated
    )
    private let sampling: Sampling
    // Owned by `queue`.
    private var model: OpaquePointer?
    private var context: OpaquePointer?

    public init(sampling: Sampling = Sampling()) {
        self.sampling = sampling
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    public var isLoaded: Bool {
        queue.sync { model != nil && context != nil }
    }

    /// Loads the model file. Safe to call again once loaded.
    public func load(modelAt url: URL) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    try loadOnQueue(url)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Frees the model and its memory.
    public func unload() {
        queue.async { [self] in
            if let context { llama_free(context) }
            if let model { llama_model_free(model) }
            context = nil
            model = nil
        }
    }

    /// Streams the reply to a ChatML prompt, piece by piece. Cancelling the
    /// consuming task stops generation at the next token.
    public func generate(
        prompt: String,
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = CancellationFlag()
            continuation.onTermination = { _ in cancelled.set() }
            queue.async { [self] in
                do {
                    try generateOnQueue(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        isCancelled: { cancelled.isSet },
                        emit: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Queue-confined

    private func loadOnQueue(_ url: URL) throws {
        guard model == nil || context == nil else { return }
        _ = Self.backend
        var modelParameters = llama_model_default_params()
        #if arch(arm64)
        modelParameters.n_gpu_layers = 99
        #else
        modelParameters.n_gpu_layers = 0
        #endif
        guard let loaded = llama_model_load_from_file(url.path, modelParameters)
        else { throw Failure.loadFailed }
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = sampling.contextLength
        contextParameters.n_batch = 512
        let threads = Int32(max(2, ProcessInfo.processInfo.activeProcessorCount - 2))
        contextParameters.n_threads = threads
        contextParameters.n_threads_batch = threads
        guard let created = llama_init_from_model(loaded, contextParameters) else {
            llama_model_free(loaded)
            throw Failure.contextFailed
        }
        model = loaded
        context = created
    }

    private func generateOnQueue(
        prompt: String,
        maxTokens: Int,
        isCancelled: () -> Bool,
        emit: (String) -> Void
    ) throws {
        guard let model, let context else { throw Failure.loadFailed }
        let vocab = llama_model_get_vocab(model)
        llama_memory_clear(llama_get_memory(context), true)

        var tokens = tokenize(prompt, vocab: vocab)
        let contextLength = Int(llama_n_ctx(context))
        guard tokens.count + 8 < contextLength else {
            throw Failure.promptTooLong(tokens.count)
        }
        let budget = min(maxTokens, contextLength - tokens.count - 1)

        let sampler = makeSampler(vocab: vocab)
        defer { llama_sampler_free(sampler) }

        // Feed the prompt in batch-sized pieces.
        var offset = 0
        while offset < tokens.count {
            if isCancelled() { return }
            let count = min(512, tokens.count - offset)
            let status = tokens.withUnsafeMutableBufferPointer { buffer in
                llama_decode(
                    context,
                    llama_batch_get_one(buffer.baseAddress! + offset, Int32(count))
                )
            }
            guard status == 0 else { throw Failure.decodeFailed(status) }
            offset += count
        }

        var pendingBytes: [UInt8] = []
        var generated = 0
        tokens.removeAll(keepingCapacity: true)
        while generated < budget, !isCancelled() {
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            pendingBytes += piece(for: token, vocab: vocab)
            if let text = Self.takeValidUTF8(&pendingBytes), !text.isEmpty {
                emit(text)
            }
            generated += 1
            let status = llama_decode(context, llama_batch_get_one(&token, 1))
            guard status == 0 else { throw Failure.decodeFailed(status) }
        }
        if !pendingBytes.isEmpty, !isCancelled() {
            emit(String(decoding: pendingBytes, as: UTF8.self))
        }
    }

    private func makeSampler(vocab: OpaquePointer?) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(sampling.topK))
        llama_sampler_chain_add(
            chain,
            llama_sampler_init_penalties(
                llama_vocab_n_tokens(vocab),
                64,
                1.0,
                0.0,
                sampling.presencePenalty
            )
        )
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(sampling.topP, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(sampling.temperature))
        llama_sampler_chain_add(
            chain,
            llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max))
        )
        return chain
    }

    private func tokenize(_ text: String, vocab: OpaquePointer?) -> [llama_token] {
        let utf8Count = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(utf8Count) + 16)
        var count = llama_tokenize(
            vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true
        )
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(
                vocab, text, utf8Count, &tokens, Int32(tokens.count), true, true
            )
        }
        return Array(tokens.prefix(Int(max(count, 0))))
    }

    private func piece(for token: llama_token, vocab: OpaquePointer?) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 64)
        var length = llama_token_to_piece(vocab, token, &buffer, 64, 0, false)
        if length < 0 {
            buffer = [CChar](repeating: 0, count: Int(-length))
            length = llama_token_to_piece(
                vocab, token, &buffer, Int32(buffer.count), 0, false
            )
        }
        return buffer.prefix(Int(max(length, 0))).map { UInt8(bitPattern: $0) }
    }

    /// Emits the longest valid UTF-8 prefix, keeping a split character's
    /// leading bytes for the next token.
    static func takeValidUTF8(_ bytes: inout [UInt8]) -> String? {
        for cut in stride(from: bytes.count, through: max(0, bytes.count - 3), by: -1) {
            if let text = String(bytes: bytes[0..<cut], encoding: .utf8) {
                bytes.removeFirst(cut)
                return text
            }
        }
        return nil
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
