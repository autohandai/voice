import AVFoundation
import AutohandVoiceCore
import Foundation

/// Audio preparation for Qwen3-ASR: mono Float32 at 16 kHz, bounded length.
enum Qwen3AudioInput {
    static let sampleRate: Double = 16_000

    /// Converts mono samples to 16 kHz with AVAudioConverter, falling back
    /// to the capture path's linear resampler if the converter is
    /// unavailable.
    static func resample(
        _ samples: [Float],
        from inputRate: Double,
        to outputRate: Double = sampleRate
    ) -> [Float] {
        guard inputRate > 0, outputRate > 0, inputRate != outputRate,
              !samples.isEmpty
        else { return samples }
        if let converted = convert(samples, from: inputRate, to: outputRate) {
            return converted
        }
        var linear = StreamingAudioResampler(
            sourceRate: inputRate,
            targetRate: outputRate
        )
        return linear.consume(samples) + linear.finish()
    }

    private static func convert(
        _ samples: [Float],
        from inputRate: Double,
        to outputRate: Double
    ) -> [Float]? {
        guard
            let source = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputRate,
                channels: 1,
                interleaved: false
            ),
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: source, to: target),
            let input = AVAudioPCMBuffer(
                pcmFormat: source,
                frameCapacity: AVAudioFrameCount(samples.count)
            ),
            let channel = input.floatChannelData?[0]
        else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { pointer in
            channel.update(from: pointer.baseAddress!, count: samples.count)
        }

        let capacity = AVAudioFrameCount(
            (Double(samples.count) * outputRate / inputRate).rounded(.up) + 1_024
        )
        guard let output = AVAudioPCMBuffer(
            pcmFormat: target,
            frameCapacity: capacity
        ) else { return nil }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) {
            _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, conversionError == nil,
              let data = output.floatChannelData?[0]
        else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }

    /// Decodes an audio file to mono 16 kHz samples in bounded chunks.
    /// Throws when the file is longer than `maximumSeconds`.
    static func loadFile(
        _ url: URL,
        maximumSeconds: Double
    ) throws -> [Float] {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw VoiceError.modelUnavailable(
                "the audio file could not be read: \(error.localizedDescription)"
            )
        }
        let format = file.processingFormat
        let rate = format.sampleRate
        guard rate > 0, format.channelCount > 0 else {
            throw VoiceError.modelUnavailable("the audio file has no audio track")
        }
        let duration = Double(file.length) / rate
        guard duration <= maximumSeconds else {
            throw VoiceError.modelUnavailable(
                "the audio is longer than \(Int(maximumSeconds / 60)) minutes"
            )
        }

        let chunkFrames: AVAudioFrameCount = 1 << 16
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: chunkFrames
        ) else {
            throw VoiceError.modelUnavailable("audio buffer allocation failed")
        }
        var mono: [Float] = []
        mono.reserveCapacity(Int(file.length))
        let channels = Int(format.channelCount)
        while file.framePosition < file.length {
            do {
                try file.read(into: buffer, frameCount: chunkFrames)
            } catch {
                throw VoiceError.modelUnavailable(
                    "the audio file could not be decoded: \(error.localizedDescription)"
                )
            }
            let frames = Int(buffer.frameLength)
            guard frames > 0, let data = buffer.floatChannelData else { break }
            if channels == 1 {
                mono.append(contentsOf: UnsafeBufferPointer(start: data[0], count: frames))
            } else {
                for frame in 0..<frames {
                    var sum: Float = 0
                    for channel in 0..<channels {
                        sum += data[channel][frame]
                    }
                    mono.append(sum / Float(channels))
                }
            }
        }
        return resample(mono, from: rate)
    }
}

#if arch(arm64)
/// Adapter for the vendored feature extractor, which resampled through
/// speech-swift's AudioCommon module.
enum AudioFileLoader {
    static func resample(_ samples: [Float], from inputRate: Int, to outputRate: Int) -> [Float] {
        Qwen3AudioInput.resample(
            samples,
            from: Double(inputRate),
            to: Double(outputRate)
        )
    }
}
#endif
