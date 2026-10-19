#if arch(arm64)
import AutohandVoiceCore
import Foundation
import MLX

/// Runs the MLX model on one serial queue, so neither the main thread nor
/// Swift's cooperative pool blocks on GPU work. All MLX calls happen here.
final class BonsaiMLXRuntime: @unchecked Sendable {
    /// MLX's buffer cache is unbounded by default; generation reuses far
    /// less than this between steps.
    static let cacheLimitBytes = 256 * 1024 * 1024
    static let contextLength = 4_096
    static let prefillChunk = 512

    struct Loaded {
        let model: PrismHadamardQwen35Model
        let tokenizer: BonsaiTokenizer
        let stopTokens: Set<Int>
    }

    struct Statistics: Sendable {
        var promptTokens = 0
        var generatedTokens = 0
        var prefillSeconds: Double = 0
        var decodeSeconds: Double = 0
    }

    private let queue = DispatchQueue(
        label: "ai.autohand.voice.bonsai-mlx",
        qos: .userInitiated
    )
    // Owned by `queue`.
    private var loaded: Loaded?

    var isLoaded: Bool { queue.sync { loaded != nil } }

    func load(directory: URL) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    if loaded == nil { loaded = try Self.load(directory) }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func unload() {
        queue.async { [self] in
            loaded = nil
            Memory.clearCache()
        }
    }

    private static func load(_ directory: URL) throws -> Loaded {
        if Memory.cacheLimit > cacheLimitBytes { Memory.cacheLimit = cacheLimitBytes }
        let tokenizer = try BonsaiTokenizer(
            contentsOf: directory.appendingPathComponent("tokenizer.json")
        )
        let model = try PrismHadamardQwen35Model(directory: directory)
        guard tokenizer.vocabularySize <= model.vocabularySize else {
            throw BonsaiMLXError.invalidModel("tokenizer and model vocabularies differ")
        }
        eval(model.parameters)
        var stop = Set<Int>()
        for name in ["<|im_end|>", "<|endoftext|>"] {
            if let id = tokenizer.specialTokenID(name) { stop.insert(id) }
        }
        if let data = try? Data(
            contentsOf: directory.appendingPathComponent("generation_config.json")
        ), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ids = object["eos_token_id"] as? [Int] { stop.formUnion(ids) }
            if let id = object["eos_token_id"] as? Int { stop.insert(id) }
        }
        guard !stop.isEmpty else {
            throw BonsaiMLXError.invalidModel("no end-of-turn token")
        }
        return Loaded(model: model, tokenizer: tokenizer, stopTokens: stop)
    }

    /// Streams the reply to a ChatML prompt. Cancelling the consumer stops
    /// generation at the next token.
    func generate(
        prompt: String,
        maxTokens: Int,
        settings: BonsaiSamplingSettings,
        seed: UInt64? = nil,
        onFinish: (@Sendable (LocalTalkGenerationStatistics) -> Void)? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let cancelled = BonsaiCancellationFlag()
            continuation.onTermination = { _ in cancelled.set() }
            queue.async { [self] in
                do {
                    let statistics = try generateOnQueue(
                        prompt: prompt,
                        maxTokens: maxTokens,
                        settings: settings,
                        seed: seed,
                        isCancelled: { cancelled.isSet },
                        emit: { continuation.yield($0) }
                    )
                    Memory.clearCache()
                    onFinish?(LocalTalkGenerationStatistics(
                        promptTokens: statistics.promptTokens,
                        generatedTokens: statistics.generatedTokens,
                        prefillSeconds: statistics.prefillSeconds,
                        decodeSeconds: statistics.decodeSeconds
                    ))
                    continuation.finish()
                } catch {
                    Memory.clearCache()
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func generateOnQueue(
        prompt: String,
        maxTokens: Int,
        settings: BonsaiSamplingSettings,
        seed: UInt64?,
        isCancelled: () -> Bool,
        emit: (String) -> Void
    ) throws -> Statistics {
        guard let loaded else { throw BonsaiMLXError.notLoaded }
        let model = loaded.model
        let tokenizer = loaded.tokenizer
        var statistics = Statistics()

        let promptTokens = tokenizer.encode(prompt)
        guard !promptTokens.isEmpty, promptTokens.count + 8 < Self.contextLength else {
            throw BonsaiMLXError.promptTooLong(promptTokens.count)
        }
        statistics.promptTokens = promptTokens.count
        let budget = min(maxTokens, Self.contextLength - promptTokens.count - 1)
        let cache = model.makeCache()
        var sampler = BonsaiGPUSampler(settings: settings, seed: seed)

        // Prefill in chunks; only the last chunk's logits are needed.
        let prefillStart = Date()
        var logits: MLXArray?
        var offset = 0
        while offset < promptTokens.count {
            if isCancelled() { return statistics }
            let end = min(offset + Self.prefillChunk, promptTokens.count)
            let chunk = MLXArray(promptTokens[offset..<end].map(Int32.init)).reshaped(1, -1)
            let chunkLogits = model.lastLogits(chunk, cache: cache)
            if end < promptTokens.count {
                // Materialise the caches so the graph stays bounded.
                eval(cacheArrays(cache))
            } else {
                logits = chunkLogits
            }
            offset = end
        }
        guard let logits else { return statistics }

        // Pipelined decode: step N+1 is queued on the GPU (sampled lazily
        // from step N's still-unread token) before token N is read back,
        // so graph building overlaps GPU work. A stop token wastes at most
        // one queued step.
        var pending = sampler.sample(logits)
        asyncEval(pending)
        var detokenizer = StreamingDetokenizer()
        var decodeStart = Date()
        var firstToken = true
        while statistics.generatedTokens < budget, !isCancelled() {
            var queued: MLXArray?
            if statistics.generatedTokens + 1 < budget {
                let nextLogits = model.lastLogits(pending.reshaped(1, 1), cache: cache)
                let next = sampler.sample(nextLogits)
                asyncEval(next)
                queued = next
            }
            let token = Int(pending.item(Int32.self))
            if firstToken {
                decodeStart = Date()
                statistics.prefillSeconds = decodeStart.timeIntervalSince(prefillStart)
                firstToken = false
            }
            if loaded.stopTokens.contains(token) { break }
            statistics.generatedTokens += 1
            let text = detokenizer.append(tokenizer.bytes(for: token))
            if !text.isEmpty { emit(text) }
            guard let queued else { break }
            pending = queued
        }
        let rest = detokenizer.finish()
        if !rest.isEmpty, !isCancelled() { emit(rest) }
        statistics.decodeSeconds = Date().timeIntervalSince(decodeStart)
        return statistics
    }

    private func cacheArrays(_ cache: PrismHadamardQwen35Cache) -> [MLXArray] {
        var arrays: [MLXArray] = []
        for linear in cache.linear.compactMap({ $0 }) {
            if let conv = linear.conv { arrays.append(conv) }
            if let recurrent = linear.recurrent { arrays.append(recurrent) }
        }
        for attention in cache.attention.compactMap({ $0 }) {
            arrays += attention.state
        }
        return arrays
    }
}

final class BonsaiCancellationFlag: @unchecked Sendable {
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
#endif
