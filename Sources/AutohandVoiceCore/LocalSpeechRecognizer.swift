import FluidAudio
import Foundation

public actor LocalSpeechRecognizer {
    private var manager: AsrManager?
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

    public func transcribe(samples: [Float]) async throws -> Transcript {
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
                decoderState: &decoderState
            )
            return Transcript(text: result.text, phase: .final)
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
    }

    public func transcribe(file: URL) async throws -> Transcript {
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
                decoderState: &decoderState
            )
            return Transcript(text: result.text, phase: .final)
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
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
