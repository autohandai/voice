import AVFoundation
import AutohandVoiceCore
import FluidAudio
import Foundation
import OSLog

/// Speaks Talk replies with the local Kokoro `af_heart` voice. Sentences are
/// synthesized in order and played as soon as each is ready.
@MainActor
final class TalkSpeaker {
    static let voice = "af_heart"

    /// Output level of the voice (RMS), read by the HUD to animate bars.
    private(set) var level: Float = 0
    private(set) var isPrepared = false
    /// Silences replies (diagnostics from the command line).
    var isMuted = false

    var onIdle: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    private let manager = KokoroAneManager(
        variant: .english,
        defaultVoice: TalkSpeaker.voice
    )
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(
        standardFormatWithSampleRate: Double(KokoroAneConstants.sampleRate),
        channels: 1
    )!
    private var isEngineConfigured = false
    private var pending: [String] = []
    private var worker: Task<Void, Never>?
    private var scheduledBuffers = 0
    private var generation = 0

    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "talk-voice"
    )

    var isSpeaking: Bool {
        worker != nil || scheduledBuffers > 0 || !pending.isEmpty
    }

    /// Downloads (first run) and loads the voice model.
    func prepare() async throws {
        guard !isPrepared else { return }
        try await manager.initialize()
        isPrepared = true
    }

    func enqueue(_ sentence: String) {
        guard !isMuted else { return }
        pending.append(sentence)
        guard worker == nil else { return }
        let generation = generation
        worker = Task { [weak self] in
            await self?.drain(generation: generation)
        }
    }

    /// Stops speech immediately and drops anything queued.
    func stop() {
        generation += 1
        pending.removeAll()
        worker?.cancel()
        worker = nil
        scheduledBuffers = 0
        if isEngineConfigured {
            player.stop()
        }
        level = 0
    }

    private func drain(generation: Int) async {
        while generation == self.generation, !pending.isEmpty {
            let sentence = pending.removeFirst()
            do {
                try await prepare()
                let result = try await manager.synthesizeDetailed(
                    text: sentence,
                    voice: Self.voice
                )
                guard generation == self.generation, !Task.isCancelled else {
                    return
                }
                try schedule(result.samples, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                Self.logger.error(
                    "Talk voice failed: \(error.localizedDescription)"
                )
                pending.removeAll()
                worker = nil
                onFailure?(error)
                return
            }
        }
        guard generation == self.generation else { return }
        worker = nil
        finishIfIdle()
    }

    private func schedule(_ samples: [Float], generation: Int) throws {
        guard
            !samples.isEmpty,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer {
            channel.update(from: $0.baseAddress!, count: samples.count)
        }
        try configureEngineIfNeeded()
        if !engine.isRunning {
            try engine.start()
        }
        scheduledBuffers += 1
        player.scheduleBuffer(
            buffer,
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.bufferFinished(generation: generation)
            }
        }
        if !player.isPlaying {
            player.play()
        }
    }

    private func bufferFinished(generation: Int) {
        guard generation == self.generation else { return }
        scheduledBuffers = max(0, scheduledBuffers - 1)
        finishIfIdle()
    }

    private func finishIfIdle() {
        guard worker == nil, scheduledBuffers == 0, pending.isEmpty else {
            return
        }
        level = 0
        onIdle?()
    }

    private func configureEngineIfNeeded() throws {
        guard !isEngineConfigured else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        player.installTap(onBus: 0, bufferSize: 1_024, format: format) {
            [weak self] buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count {
                sum += channel[index] * channel[index]
            }
            let rms = (sum / Float(count)).squareRoot()
            Task { @MainActor [weak self] in
                guard let self, self.isSpeaking else { return }
                self.level = rms
            }
        }
        engine.prepare()
        isEngineConfigured = true
    }
}
