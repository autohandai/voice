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
    /// room noise (about -60 dBFS) stays flat and speech fills the range.
    public static func meterLevel(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        let floor = -60.0
        let ceiling = -20.0
        return min(max((decibels - floor) / (ceiling - floor), 0), 1)
    }

    /// Bar heights for the recording waveform: flat when silent, rising with
    /// the normalized input level, and shifting each frame while speaking.
    public static func liveBarHeights(level: Double, frame: Int) -> [Double] {
        let level = min(max(level, 0), 1)
        return barHeights(for: frame).map {
            silentBarHeight + (1 - silentBarHeight) * level * $0
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
