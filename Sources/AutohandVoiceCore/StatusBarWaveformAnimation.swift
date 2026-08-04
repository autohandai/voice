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
