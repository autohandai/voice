import FluidAudio
import Foundation

public actor LocalSpeechRecognizer {
    private var manager: AsrManager?
    private let modelVersion: AsrModelVersion

    public init(modelVersion: String = "v3") {
        self.modelVersion = modelVersion == "v2" ? .v2 : .v3
    }

    public func prepare() async throws {
        guard manager == nil else { return }
        do {
            let models = try await AsrModels.downloadAndLoad(version: modelVersion)
            let value = AsrManager(config: .default)
            try await value.loadModels(models)
            manager = value
        } catch {
            throw VoiceError.modelUnavailable(error.localizedDescription)
        }
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
}
