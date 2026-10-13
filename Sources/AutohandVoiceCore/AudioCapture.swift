import AVFoundation
import AudioToolbox
import Foundation

public final class AudioCapture: @unchecked Sendable {
    public static let targetSampleRate = 16_000.0
    public static let maximumDuration: TimeInterval = 300
    public static let maximumExtendedDuration: TimeInterval = 20 * 60

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private let captureMaximumDuration: TimeInterval
    private var samples: [Float] = []
    private var sourceSampleRate = 0.0
    private var streamingResampler: StreamingAudioResampler?
    private var recording = false
    private var startedAt: Date?
    private var levelHandler: (@Sendable (Float) -> Void)?
    private var sampleHandler: (@Sendable ([Float], Double) -> Void)?
    private var levelFramesSinceEmission = 0
    private var tapInstalled = false

    public init(maximumDuration: TimeInterval = AudioCapture.maximumDuration) {
        captureMaximumDuration = min(
            max(1, maximumDuration),
            Self.maximumExtendedDuration
        )
    }

    public static func maximumBufferedSampleCount(
        duration: TimeInterval
    ) -> Int {
        let boundedDuration = min(
            max(1, duration),
            maximumExtendedDuration
        )
        return Int(targetSampleRate * boundedDuration)
    }

    public static func maximumBufferedBytes(
        duration: TimeInterval
    ) -> Int {
        maximumBufferedSampleCount(duration: duration)
            * MemoryLayout<Float>.size
    }

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
        deviceUID: String? = nil,
        onLevel: (@Sendable (Float) -> Void)? = nil,
        onSamples: (@Sendable ([Float], Double) -> Void)? = nil
    ) async throws {
        guard await requestPermission() else {
            throw VoiceError.microphonePermissionDenied
        }

        let shouldStart = lock.withLock {
            guard !recording else { return false }
            samples.removeAll(keepingCapacity: true)
            levelHandler = onLevel
            sampleHandler = onSamples
            levelFramesSinceEmission = 0
            recording = true
            startedAt = Date()
            return true
        }
        guard shouldStart else { return }

        let input = engine.inputNode
        do {
            try selectInputDevice(deviceUID, for: input)
        } catch {
            reset()
            throw error
        }
        guard let format = Self.inputTapFormat(
            outputFormat: input.outputFormat(forBus: 0),
            hardwareFormat: input.inputFormat(forBus: 0)
        ) else {
            reset()
            throw VoiceError.microphoneUnavailable("no input audio format is available")
        }
        sourceSampleRate = format.sampleRate
        lock.withLock {
            streamingResampler = StreamingAudioResampler(
                sourceRate: format.sampleRate,
                targetRate: Self.targetSampleRate
            )
        }

        installTap(on: input, format: format)

        do {
            engine.prepare()
            try engine.start()
        } catch {
            removeTapIfInstalled(from: input)
            reset()
            throw VoiceError.microphoneUnavailable(error.localizedDescription)
        }
    }

    /// Moves an active capture to a different input without clearing the
    /// authoritative 16 kHz buffer. The previous resampler is finalized first,
    /// creating an explicit segment boundary.
    public func handoff(to deviceUID: String) throws {
        let input = engine.inputNode
        let wasRecording = lock.withLock {
            guard recording else { return false }
            if var streamingResampler {
                let remaining = max(
                    0,
                    Self.maximumBufferedSampleCount(
                        duration: captureMaximumDuration
                    ) - samples.count
                )
                samples.append(
                    contentsOf: streamingResampler.finish().prefix(remaining)
                )
            }
            streamingResampler = nil
            return true
        }
        guard wasRecording else {
            throw VoiceError.microphoneUnavailable(
                "there is no active capture to hand off"
            )
        }

        engine.stop()
        removeTapIfInstalled(from: input)
        do {
            try selectInputDevice(deviceUID, for: input)
            guard let format = Self.inputTapFormat(
                outputFormat: input.outputFormat(forBus: 0),
                hardwareFormat: input.inputFormat(forBus: 0)
            ) else {
                throw VoiceError.microphoneUnavailable(
                    "the replacement input has no audio format"
                )
            }
            lock.withLock {
                sourceSampleRate = format.sampleRate
                streamingResampler = StreamingAudioResampler(
                    sourceRate: format.sampleRate,
                    targetRate: Self.targetSampleRate
                )
                levelFramesSinceEmission = 0
            }
            installTap(on: input, format: format)
            engine.prepare()
            try engine.start()
        } catch {
            removeTapIfInstalled(from: input)
            throw error
        }
    }

    private func selectInputDevice(
        _ deviceUID: String?,
        for input: AVAudioInputNode
    ) throws {
        guard let audioUnit = input.audioUnit else {
            throw VoiceError.microphoneUnavailable(
                "the audio input unit is unavailable"
            )
        }
        var deviceID = try AudioInputDevices.deviceID(forUID: deviceUID)
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw VoiceError.microphoneUnavailable(
                "the selected input could not be opened (error \(status))"
            )
        }
    }

    public func stop() throws -> [Float] {
        let captured = finishCapture()
        guard captured.count >= Int(Self.targetSampleRate * 0.1) else {
            throw VoiceError.recordingTooShort
        }
        return captured
    }

    /// Ends capture without committing anything and returns only valid local
    /// samples for a short-lived explicit Undo Cancel action.
    public func cancelRetainingSamples() -> [Float] {
        finishCapture()
    }

    private func finishCapture() -> [Float] {
        lock.lock()
        let wasRecording = recording
        let hadTap = tapInstalled
        tapInstalled = false
        recording = false
        if var streamingResampler {
            let remaining = max(
                0,
                Self.maximumBufferedSampleCount(
                    duration: captureMaximumDuration
                ) - samples.count
            )
            samples.append(
                contentsOf: streamingResampler.finish().prefix(remaining)
            )
        }
        let captured = samples
        samples.removeAll(keepingCapacity: false)
        streamingResampler = nil
        levelHandler = nil
        sampleHandler = nil
        levelFramesSinceEmission = 0
        startedAt = nil
        lock.unlock()

        guard wasRecording else { return [] }
        engine.stop()
        if hadTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        return captured
    }

    public func cancel() {
        lock.lock()
        let wasRecording = recording
        let hadTap = tapInstalled
        tapInstalled = false
        lock.unlock()
        if wasRecording {
            engine.stop()
            if hadTap {
                engine.inputNode.removeTap(onBus: 0)
            }
        }
        reset()
    }

    private func reset() {
        lock.lock()
        recording = false
        samples.removeAll(keepingCapacity: false)
        streamingResampler = nil
        levelHandler = nil
        sampleHandler = nil
        levelFramesSinceEmission = 0
        tapInstalled = false
        startedAt = nil
        lock.unlock()
    }

    private func installTap(
        on input: AVAudioInputNode,
        format: AVAudioFormat
    ) {
        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        lock.withLock {
            tapInstalled = true
        }
    }

    /// On macOS the input node's output format can follow the default
    /// output device's sample rate. When input and output run at different
    /// rates, tapping in that format fails to start with -10868, so the tap
    /// uses the input hardware format and resampling stays in
    /// `StreamingAudioResampler`.
    static func inputTapFormat(
        outputFormat: AVAudioFormat,
        hardwareFormat: AVAudioFormat
    ) -> AVAudioFormat? {
        if hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 {
            return hardwareFormat
        }
        if outputFormat.sampleRate > 0, outputFormat.channelCount > 0 {
            return outputFormat
        }
        return nil
    }

    private func removeTapIfInstalled(from input: AVAudioInputNode) {
        let shouldRemove = lock.withLock {
            let installed = tapInstalled
            tapInstalled = false
            return installed
        }
        if shouldRemove {
            input.removeTap(onBus: 0)
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        let incoming = Array(UnsafeBufferPointer(start: channel, count: count))
        let sum = incoming.reduce(Float.zero) { $0 + ($1 * $1) }
        let rms = sqrt(sum / Float(count))

        lock.lock()
        guard recording else {
            lock.unlock()
            return
        }
        let converted = streamingResampler?.consume(incoming) ?? []
        let maximumSamples = Self.maximumBufferedSampleCount(
            duration: captureMaximumDuration
        )
        let remaining = max(0, maximumSamples - samples.count)
        if remaining > 0 {
            samples.append(contentsOf: converted.prefix(remaining))
        }
        levelFramesSinceEmission += count
        let emissionInterval = max(1, Int(sourceSampleRate / 20))
        let handler: (@Sendable (Float) -> Void)?
        if levelFramesSinceEmission >= emissionInterval {
            levelFramesSinceEmission = 0
            handler = levelHandler
        } else {
            handler = nil
        }
        let samplesHandler = sampleHandler
        let rate = sourceSampleRate
        lock.unlock()
        handler?(rms)
        samplesHandler?(incoming, rate)
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
