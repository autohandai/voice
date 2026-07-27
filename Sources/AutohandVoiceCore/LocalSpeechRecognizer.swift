import AVFoundation
import FluidAudio
import Foundation

public actor LocalSpeechRecognizer {
    private var manager: AsrManager?
    private var loadedModels: AsrModels?
    private var previewManager: SlidingWindowAsrManager?
    private var previewUpdateTask: Task<Void, Never>?
    private let variant: SpeechModelVariant

    public init(modelVersion: String = "v3") {
        variant = SpeechModelVariant(rawValue: modelVersion) ?? .default
    }

    public func prepare(
        onProgress: (@Sendable (ModelPreparationProgress) -> Void)? = nil
    ) async throws {
        guard manager == nil else { return }
        onProgress?(.init(fractionCompleted: 0, phase: .checking))
        do {
            let models = try await AsrModels.downloadAndLoad(
                version: variant.asrVersion,
                progressHandler: { progress in
                    onProgress?(Self.map(progress))
                }
            )
            try Task.checkCancellation()
            onProgress?(.init(fractionCompleted: 0.98, phase: .loading))
            let value = AsrManager(config: .default)
            try await value.loadModels(models)
            try Task.checkCancellation()
            loadedModels = models
            manager = value
            onProgress?(.init(fractionCompleted: 1, phase: .validating))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func validate() async throws -> Bool {
        do {
            return try await AsrModels.isModelValid(
                version: variant.asrVersion
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func repair(
        onProgress: (@Sendable (ModelPreparationProgress) -> Void)? = nil
    ) async throws {
        manager = nil
        loadedModels = nil
        do {
            _ = try await AsrModels.download(
                force: true,
                version: variant.asrVersion,
                progressHandler: { progress in
                    onProgress?(Self.map(progress))
                }
            )
            try Task.checkCancellation()
            try await prepare(onProgress: onProgress)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func storageBytes() throws -> Int64 {
        try ModelCacheInspector.storageBytes(at: variant.cacheDirectory)
    }

    public func transcribe(
        samples: [Float],
        languageCode: String = SupportedDictationLanguage.english.code
    ) async throws -> Transcript {
        guard !samples.isEmpty else { throw VoiceError.recordingTooShort }
        try await prepare()
        guard let manager else {
            throw VoiceError.modelUnavailable("model initialization did not complete")
        }
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )
        do {
            let result = try await manager.transcribe(
                samples,
                decoderState: &decoderState,
                language: Language(rawValue: languageCode)
            )
            return Transcript(text: result.text, phase: .final)
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func transcribe(
        file: URL,
        languageCode: String = SupportedDictationLanguage.english.code
    ) async throws -> Transcript {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try await prepare()
        guard let manager else {
            throw VoiceError.modelUnavailable("model initialization did not complete")
        }
        var decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount
        )
        do {
            let result = try await manager.transcribe(
                file,
                decoderState: &decoderState,
                language: Language(rawValue: languageCode)
            )
            return Transcript(text: result.text, phase: .final)
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func startProvisionalPreview(
        onUpdate: @escaping @Sendable (Transcript) -> Void
    ) async throws {
        await stopProvisionalPreview()
        try await prepare()
        guard let loadedModels else {
            throw VoiceError.modelUnavailable(
                "model initialization did not complete"
            )
        }

        let value = SlidingWindowAsrManager(config: .streaming)
        do {
            try await value.loadModels(loadedModels)
            let updates = await value.transcriptionUpdates
            try await value.startStreaming(source: .microphone)
            previewManager = value
            previewUpdateTask = Task {
                for await _ in updates {
                    guard !Task.isCancelled else { return }
                    let confirmed = await value.confirmedTranscript
                    let volatile = await value.volatileTranscript
                    let text = [confirmed, volatile]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !text.isEmpty else { continue }
                    onUpdate(Transcript(text: text, phase: .provisional))
                }
            }
        } catch {
            await value.cleanup()
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func appendProvisionalSamples(
        _ samples: [Float],
        sampleRate: Double
    ) async {
        guard
            let previewManager,
            !samples.isEmpty,
            sampleRate > 0,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        await previewManager.streamAudio(buffer)
    }

    public func stopProvisionalPreview() async {
        let updateTask = previewUpdateTask
        updateTask?.cancel()
        previewUpdateTask = nil
        if let previewManager {
            self.previewManager = nil
            await previewManager.cleanup()
        }
        _ = await updateTask?.result
    }

    private static func map(
        _ progress: DownloadUtils.DownloadProgress
    ) -> ModelPreparationProgress {
        let phase: ModelPreparationPhase
        switch progress.phase {
        case .listing:
            phase = .listing
        case let .downloading(completedFiles, totalFiles):
            phase = .downloading(
                completedFiles: completedFiles,
                totalFiles: totalFiles
            )
        case let .compiling(modelName):
            phase = .compiling(modelName)
        }
        return ModelPreparationProgress(
            fractionCompleted: progress.fractionCompleted,
            phase: phase
        )
    }
}
