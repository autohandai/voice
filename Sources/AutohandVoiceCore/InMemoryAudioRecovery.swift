import Foundation

public struct InMemoryAudioRecovery: Sendable {
    public static let defaultExpiration: TimeInterval = 15 * 60

    public private(set) var sampleCount = 0

    private let maximumSamples: Int
    private let sampleRate: Double
    private let expiresAfter: TimeInterval
    private var retainedSamples: [Float] = []
    private var expiresAt: TimeInterval?

    public init(
        maximumSamples: Int = Int(
            AudioCapture.targetSampleRate * AudioCapture.maximumDuration
        ),
        sampleRate: Double = AudioCapture.targetSampleRate,
        expiresAfter: TimeInterval = Self.defaultExpiration
    ) {
        self.maximumSamples = max(0, maximumSamples)
        self.sampleRate = sampleRate
        self.expiresAfter = max(0, expiresAfter)
    }

    public var duration: TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return Double(sampleCount) / sampleRate
    }

    public mutating func store(
        _ samples: [Float],
        at timestamp: TimeInterval
    ) {
        retainedSamples = Array(samples.prefix(maximumSamples))
        sampleCount = retainedSamples.count
        expiresAt = retainedSamples.isEmpty ? nil : timestamp + expiresAfter
    }

    public mutating func samples(
        at timestamp: TimeInterval
    ) -> [Float]? {
        guard
            let expiresAt,
            timestamp < expiresAt,
            !retainedSamples.isEmpty
        else {
            discard()
            return nil
        }
        return retainedSamples
    }

    public mutating func discard() {
        retainedSamples.removeAll(keepingCapacity: false)
        sampleCount = 0
        expiresAt = nil
    }
}
