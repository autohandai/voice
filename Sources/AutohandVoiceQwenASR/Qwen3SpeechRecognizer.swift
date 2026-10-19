import AutohandVoiceCore
import Foundation
#if arch(arm64)
import MLX
#endif

/// Optional local dictation engine: Qwen3-ASR 0.6B (MLX 4-bit) running
/// in-process on the Apple Silicon GPU through MLX.
///
/// Mirrors `LocalSpeechRecognizer` so a session can swap engines. Audio
/// never leaves the Mac; the only network use is the one-time, pinned and
/// checksummed model download in `prepare`. On Intel (or the x86_64 slice
/// under Rosetta) every entry point fails with `VoiceError.modelUnavailable`
/// before touching MLX or the network.
public actor Qwen3SpeechRecognizer {
    public static let displayName = "Qwen3-ASR 0.6B"
    public static let sampleRate: Double = 16_000
    /// Matches the upstream feature extractor's 1200 s upper bound.
    public static let maximumAudioSeconds: Double = 1_200

    private static let currentEnvironment = Qwen3RuntimeEnvironment.current

    /// False on Intel, under Rosetta, and without an Apple GPU.
    public static var isSupportedOnThisMac: Bool {
        currentEnvironment.isSupported
    }

    /// User-facing reason Qwen3-ASR cannot run here, or nil when it can.
    public static var unsupportedReason: String? {
        currentEnvironment.unsupportedReason
    }

    public nonisolated let cacheDirectory: URL
    private let downloader: Qwen3ModelDownloader
    private let environment: Qwen3RuntimeEnvironment
    #if arch(arm64)
    private var engine: Qwen3Engine?
    #endif

    public init(
        cacheDirectory: URL? = nil,
        downloader: Qwen3ModelDownloader = Qwen3ModelDownloader(),
        environment: Qwen3RuntimeEnvironment? = nil
    ) {
        self.cacheDirectory = cacheDirectory
            ?? downloader.manifest.defaultCacheDirectory
        self.downloader = downloader
        self.environment = environment ?? Self.currentEnvironment
    }

    /// Downloads (once) and loads the model. Safe to call repeatedly.
    public func prepare(
        onProgress: (@Sendable (ModelPreparationProgress) -> Void)? = nil
    ) async throws {
        try checkRuntime()
        #if arch(arm64)
        guard engine == nil else { return }
        onProgress?(.init(fractionCompleted: 0, phase: .checking))
        do {
            try await install(onProgress: onProgress)
            try Task.checkCancellation()
            onProgress?(.init(fractionCompleted: 0.92, phase: .loading))
            let loaded = try await Qwen3Engine.load(from: cacheDirectory)
            try Task.checkCancellation()
            engine = loaded
            onProgress?(.init(fractionCompleted: 1, phase: .validating))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
        #endif
    }

    /// Hashes the cached files against the pinned manifest. Never downloads.
    public func validate() async throws -> Bool {
        try checkRuntime()
        let downloader = downloader
        let directory = cacheDirectory
        do {
            return try await Task.detached(priority: .utility) {
                try downloader.verify(in: directory)
            }.value
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    /// Re-verifies every file, downloads any that are corrupt, and reloads.
    public func repair(
        onProgress: (@Sendable (ModelPreparationProgress) -> Void)? = nil
    ) async throws {
        try checkRuntime()
        #if arch(arm64)
        engine = nil
        #endif
        do {
            try await downloader.repair(in: cacheDirectory) { progress in
                onProgress?(Self.map(progress))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
        try await prepare(onProgress: onProgress)
    }

    public func storageBytes() throws -> Int64 {
        try ModelCacheInspector.storageBytes(at: cacheDirectory)
    }

    /// Whether the pinned files are present (sizes and marker only).
    public nonisolated func isDownloaded() -> Bool {
        downloader.isInstalled(in: cacheDirectory)
    }

    /// Releases the loaded model's memory. The next transcription reloads it.
    public func unload() {
        #if arch(arm64)
        engine = nil
        Memory.clearCache()
        #endif
    }

    /// Deletes the downloaded model folder.
    public func removeCache() throws {
        #if arch(arm64)
        engine = nil
        #endif
        let target = cacheDirectory.standardizedFileURL
        guard target.lastPathComponent == downloader.manifest.directoryName else {
            throw ModelCacheError.unsafeTarget
        }
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)
    }

    /// Transcribes mono samples. Non-16 kHz input is resampled first.
    public func transcribe(
        samples: [Float],
        sampleRate: Double = Qwen3SpeechRecognizer.sampleRate,
        languageCode: String = SupportedDictationLanguage.english.code
    ) async throws -> Transcript {
        guard !samples.isEmpty, sampleRate > 0 else {
            throw VoiceError.recordingTooShort
        }
        guard Double(samples.count) / sampleRate <= Self.maximumAudioSeconds else {
            throw VoiceError.modelUnavailable(
                "the recording is longer than \(Int(Self.maximumAudioSeconds / 60)) minutes"
            )
        }
        try checkRuntime()
        let audio = sampleRate == Self.sampleRate
            ? samples
            : Qwen3AudioInput.resample(samples, from: sampleRate)
        return try await transcribe16k(audio, languageCode: languageCode)
    }

    /// Transcribes an audio file (any format AVAudioFile can read).
    public func transcribe(
        file: URL,
        languageCode: String = SupportedDictationLanguage.english.code
    ) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try checkRuntime()
        let maximum = Self.maximumAudioSeconds
        let audio = try await Task.detached(priority: .userInitiated) {
            try Qwen3AudioInput.loadFile(file, maximumSeconds: maximum)
        }.value
        guard !audio.isEmpty else { throw VoiceError.recordingTooShort }
        return try await transcribe16k(audio, languageCode: languageCode)
    }

    private func transcribe16k(
        _ audio: [Float],
        languageCode: String
    ) async throws -> Transcript {
        #if arch(arm64)
        try await prepare()
        guard let engine else {
            throw VoiceError.modelUnavailable("model initialization did not complete")
        }
        let language = Qwen3LanguageHint.name(forCode: languageCode)
        do {
            let text = try await engine.transcribe(audio, language: language)
            return Transcript(text: text, phase: .final)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VoiceError {
            throw error
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
        #else
        throw VoiceError.modelUnavailable(
            environment.unsupportedReason ?? "Qwen3-ASR is unavailable on this Mac."
        )
        #endif
    }

    private func checkRuntime() throws {
        guard environment.isSupported else {
            throw VoiceError.modelUnavailable(
                environment.unsupportedReason
                    ?? "Qwen3-ASR is unavailable on this Mac."
            )
        }
        guard environment.metalLibraryURL != nil else {
            throw VoiceError.modelUnavailable(
                "the MLX GPU kernels (mlx.metallib) are missing from this build. Reinstall Autohand Voice."
            )
        }
    }

    private func install(
        onProgress: (@Sendable (ModelPreparationProgress) -> Void)?
    ) async throws {
        try await downloader.install(into: cacheDirectory) { progress in
            onProgress?(Self.map(progress))
        }
    }

    static func map(_ progress: Qwen3DownloadProgress) -> ModelPreparationProgress {
        ModelPreparationProgress(
            fractionCompleted: progress.fractionCompleted * 0.9,
            phase: .downloading(
                completedFiles: progress.completedFiles,
                totalFiles: progress.totalFiles
            )
        )
    }
}

#if arch(arm64)
/// Owns the MLX model and runs all MLX work on one serial queue, off the
/// Swift cooperative thread pool.
final class Qwen3Engine: @unchecked Sendable {
    /// MLX's buffer cache is otherwise unbounded by default; dictation
    /// clips need far less than this between transcriptions.
    static let cacheLimitBytes = 512 * 1024 * 1024

    private let model: Qwen3ASRModel
    private let queue: DispatchQueue

    private init(model: Qwen3ASRModel, queue: DispatchQueue) {
        self.model = model
        self.queue = queue
    }

    static func load(from directory: URL) async throws -> Qwen3Engine {
        let queue = DispatchQueue(
            label: "ai.autohand.voice.qwen3-asr",
            qos: .userInitiated
        )
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    if Memory.cacheLimit > cacheLimitBytes {
                        Memory.cacheLimit = cacheLimitBytes
                    }
                    let model = try Qwen3ASRModel.load(from: directory)
                    continuation.resume(returning: Qwen3Engine(model: model, queue: queue))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func transcribe(_ audio: [Float], language: String?) async throws -> String {
        let flag = Qwen3CancellationFlag()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [model] in
                    do {
                        let options = Qwen3DecodingOptions(language: language)
                        let text = try model.transcribe(
                            audio: audio,
                            sampleRate: Int(Qwen3SpeechRecognizer.sampleRate),
                            options: options,
                            checkCancellation: {
                                if flag.isCancelled { throw CancellationError() }
                            }
                        )
                        Memory.clearCache()
                        continuation.resume(returning: text)
                    } catch {
                        Memory.clearCache()
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            flag.cancel()
        }
    }
}

final class Qwen3CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
#endif
