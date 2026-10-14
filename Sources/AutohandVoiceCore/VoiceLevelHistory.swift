import Foundation

/// Recent voice levels drawn as mirrored bars: the newest level sits in the
/// middle and older levels move outward, so the shape is the real voice
/// rather than an animation.
public struct VoiceLevelHistory: Equatable, Sendable {
    public let barCount: Int
    /// Newest first; one entry per distance from the middle bar.
    private var levels: [Double]

    public init(barCount: Int) {
        self.barCount = max(1, barCount)
        levels = Array(repeating: 0, count: (self.barCount + 1) / 2)
    }

    var storedLevelCount: Int { levels.count }

    public mutating func push(_ level: Double) {
        levels.removeLast()
        levels.insert(min(max(level, 0), 1), at: 0)
    }

    public mutating func reset() {
        levels = Array(repeating: 0, count: levels.count)
    }

    /// One 0...1 level per bar, left to right.
    public var barLevels: [Double] {
        let middle = Double(barCount - 1) / 2
        return (0..<barCount).map { index in
            levels[Int((Double(index) - middle).magnitude.rounded(.down))]
        }
    }
}
