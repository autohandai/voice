import AVFoundation
import Foundation

public final class AudioCapture: @unchecked Sendable {
    public static let targetSampleRate = 16_000.0
    public static let maximumDuration: TimeInterval = 300

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var sourceSampleRate = 0.0
    private var recording = false
    private var startedAt: Date?
    private var levelHandler: (@Sendable (Float) -> Void)?

    public init() {}

    public func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    public func start(
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        guard await requestPermission() else {
            throw VoiceError.microphonePermissionDenied
        }

        let shouldStart = lock.withLock {
            guard !recording else { return false }
            samples.removeAll(keepingCapacity: true)
            levelHandler = onLevel
            recording = true
            startedAt = Date()
            return true
        }
        guard shouldStart else { return }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            reset()
            throw VoiceError.microphoneUnavailable("no input audio format is available")
        }
        sourceSampleRate = format.sampleRate

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            self?.consume(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            reset()
            throw VoiceError.microphoneUnavailable(error.localizedDescription)
        }
    }

    public func stop() throws -> [Float] {
        lock.lock()
        let wasRecording = recording
        recording = false
        let captured = samples
        let inputRate = sourceSampleRate
        samples.removeAll(keepingCapacity: false)
        levelHandler = nil
        startedAt = nil
        lock.unlock()

        guard wasRecording else { return [] }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        guard captured.count >= Int(inputRate * 0.1) else {
            throw VoiceError.recordingTooShort
        }
        return Self.resample(
            captured,
            from: inputRate,
            to: Self.targetSampleRate
        )
    }

    public func cancel() {
        lock.lock()
        let wasRecording = recording
        lock.unlock()
        if wasRecording {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        reset()
    }

    private func reset() {
        lock.lock()
        recording = false
        samples.removeAll(keepingCapacity: false)
        levelHandler = nil
        startedAt = nil
        lock.unlock()
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let incoming = Array(UnsafeBufferPointer(start: channel, count: count))
        let sum = incoming.reduce(Float.zero) { $0 + ($1 * $1) }
        let rms = sqrt(sum / Float(count))

        lock.lock()
        defer { lock.unlock() }
        guard recording else { return }
        let maximumSamples = Int(sourceSampleRate * Self.maximumDuration)
        let remaining = max(0, maximumSamples - samples.count)
        if remaining > 0 {
            samples.append(contentsOf: incoming.prefix(remaining))
        }
        levelHandler?(rms)
    }

    static func resample(
        _ input: [Float],
        from sourceRate: Double,
        to targetRate: Double
    ) -> [Float] {
        guard !input.isEmpty, sourceRate > 0, targetRate > 0 else { return [] }
        guard sourceRate != targetRate else { return input }
        let ratio = sourceRate / targetRate
        let outputCount = Int(Double(input.count) / ratio)
        return (0..<outputCount).map { index in
            let position = Double(index) * ratio
            let lower = min(Int(position), input.count - 1)
            let upper = min(lower + 1, input.count - 1)
            let fraction = Float(position - Double(lower))
            return input[lower] + ((input[upper] - input[lower]) * fraction)
        }
    }
}
