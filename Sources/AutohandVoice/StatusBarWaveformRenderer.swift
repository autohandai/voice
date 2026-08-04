import AppKit
import AutohandVoiceCore

@MainActor
enum StatusBarWaveformRenderer {
    private static let imageSize = NSSize(width: 18, height: 18)
    private static let barWidth: CGFloat = 2
    private static let barSpacing: CGFloat = 1.5
    private static let minimumBarHeight: CGFloat = 3
    private static let maximumBarHeight: CGFloat = 12

    static func frames() -> [NSImage] {
        (0..<StatusBarWaveformAnimation.frameCount).map { frame in
            image(
                barHeights: StatusBarWaveformAnimation.barHeights(for: frame)
            )
        }
    }

    private static func image(barHeights: [Double]) -> NSImage {
        let image = NSImage(
            size: imageSize,
            flipped: false
        ) { rect in
            NSColor.black.setFill()
            let totalWidth = CGFloat(barHeights.count) * barWidth
                + CGFloat(max(0, barHeights.count - 1)) * barSpacing
            var x = rect.midX - totalWidth / 2

            for normalizedHeight in barHeights {
                let height = minimumBarHeight
                    + CGFloat(normalizedHeight)
                        * (maximumBarHeight - minimumBarHeight)
                let bar = NSRect(
                    x: x,
                    y: rect.midY - height / 2,
                    width: barWidth,
                    height: height
                )
                NSBezierPath(
                    roundedRect: bar,
                    xRadius: barWidth / 2,
                    yRadius: barWidth / 2
                ).fill()
                x += barWidth + barSpacing
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Autohand Voice is starting"
        return image
    }
}
