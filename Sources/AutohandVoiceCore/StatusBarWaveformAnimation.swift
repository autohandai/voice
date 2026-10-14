import Foundation

public enum StatusBarWaveformAnimation {
    public static let barCount = 5
    public static let frameCount = barCount
    public static let frameInterval: Duration = .milliseconds(220)
    public static let minimumVisibleDuration = 1.8

    private static let baseHeights = [0.28, 0.46, 1.0, 0.64, 0.36]

    public static func barHeights(for frame: Int) -> [Double] {
        let offset = ((frame % frameCount) + frameCount) % frameCount
        return baseHeights.indices.map {
            baseHeights[($0 + offset) % frameCount]
        }
    }

    /// Faster cadence while recording so the bars follow speech.
    public static let liveFrameInterval: Duration = .milliseconds(90)
    private static let silentBarHeight = 0.12

    /// Maps microphone RMS to 0...1 on a decibel scale, like a level meter:
    /// room tone (about -45 dBFS) stays low, conversational speech (about
    /// -20 dBFS) leaves headroom, and only loud speech fills the range.
    public static func meterLevel(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        let floor = -55.0
        let ceiling = -12.0
        return min(max((decibels - floor) / (ceiling - floor), 0), 1)
    }

    /// Bar heights for the recording waveform from the real recent voice
    /// levels: flat when silent, rising and moving with speech.
    public static func liveBarHeights(levels: [Double]) -> [Double] {
        levels.map {
            silentBarHeight + (1 - silentBarHeight) * min(max($0, 0), 1)
        }
    }

    public static func shouldRemainVisible(
        isPreparing: Bool,
        startedAtUptime: Double?,
        nowUptime: Double
    ) -> Bool {
        if isPreparing { return true }
        guard let startedAtUptime else { return false }
        return nowUptime - startedAtUptime < minimumVisibleDuration
    }
}
