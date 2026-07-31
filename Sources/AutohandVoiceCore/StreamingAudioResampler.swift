import Foundation

/// Incremental linear resampling with constant state across audio buffers.
///
/// The resampler retains only the previous source sample. This lets capture
/// store its authoritative buffer at the 16 kHz recognition rate instead of
/// retaining up to 20 minutes at the hardware sample rate.
public struct StreamingAudioResampler: Sendable {
    public let sourceRate: Double
    public let targetRate: Double

    private let ratio: Double
    private var sourceFramesSeen: Int64 = 0
    private var emittedOutputFrames: Int64 = 0
    private var previousSourceSample: Float?

    public init(sourceRate: Double, targetRate: Double) {
        self.sourceRate = sourceRate
        self.targetRate = targetRate
        ratio = sourceRate > 0 && targetRate > 0
            ? sourceRate / targetRate
            : 1
    }

    public mutating func consume(_ input: [Float]) -> [Float] {
        guard
            !input.isEmpty,
            sourceRate > 0,
            targetRate > 0
        else {
            return []
        }

        let chunkStart = sourceFramesSeen
        sourceFramesSeen += Int64(input.count)
        let targetOutputCount = Int64(
            Double(sourceFramesSeen) / ratio
        )
        var output: [Float] = []
        output.reserveCapacity(
            max(0, Int(targetOutputCount - emittedOutputFrames))
        )

        while emittedOutputFrames < targetOutputCount {
            let position = Double(emittedOutputFrames) * ratio
            let lowerIndex = Int64(position.rounded(.down))
            let fraction = Float(position - Double(lowerIndex))
            let upperIndex = lowerIndex + (fraction == 0 ? 0 : 1)

            // A fractional sample that needs the next chunk is deferred. The
            // previous source sample is retained so it can be completed later.
            guard upperIndex < sourceFramesSeen else {
                break
            }
            guard
                let lower = sample(
                    at: lowerIndex,
                    chunkStart: chunkStart,
                    input: input
                ),
                let upper = sample(
                    at: upperIndex,
                    chunkStart: chunkStart,
                    input: input
                )
            else {
                break
            }

            output.append(lower + ((upper - lower) * fraction))
            emittedOutputFrames += 1
        }

        previousSourceSample = input.last
        return output
    }

    public mutating func finish() -> [Float] {
        guard
            sourceRate > 0,
            targetRate > 0,
            let previousSourceSample
        else {
            return []
        }
        let targetOutputCount = Int64(
            Double(sourceFramesSeen) / ratio
        )
        var output: [Float] = []
        while emittedOutputFrames < targetOutputCount {
            output.append(previousSourceSample)
            emittedOutputFrames += 1
        }
        return output
    }

    private func sample(
        at globalIndex: Int64,
        chunkStart: Int64,
        input: [Float]
    ) -> Float? {
        if globalIndex == chunkStart - 1 {
            return previousSourceSample
        }
        let localIndex = globalIndex - chunkStart
        guard localIndex >= 0, localIndex < input.count else {
            return nil
        }
        return input[Int(localIndex)]
    }
}
