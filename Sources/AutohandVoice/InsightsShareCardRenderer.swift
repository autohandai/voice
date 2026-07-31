import AppKit
import AutohandVoiceCore

enum InsightsShareCardRenderer {
    static func render(
        _ card: InsightsShareCard
    ) -> NSImage? {
        let size = NSSize(width: 1_200, height: 630)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor(
            calibratedRed: 0.055,
            green: 0.067,
            blue: 0.10,
            alpha: 1
        ).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()

        let title = "Autohand Voice"
        title.draw(
            at: NSPoint(x: 72, y: 520),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 42, weight: .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        "Private, local usage summary".draw(
            at: NSPoint(x: 72, y: 474),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 24),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )

        drawMetric(
            card.wordCount.formatted(),
            label: "words dictated",
            x: 72
        )
        drawMetric(
            card.wordsPerMinute.formatted(
                .number.precision(.fractionLength(0))
            ),
            label: "words per minute",
            x: 420
        )
        drawMetric(
            card.currentStreakDays.formatted(),
            label: "day current streak",
            x: 790
        )

        "Generated locally. No transcript text or account data.".draw(
            at: NSPoint(x: 72, y: 62),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 19),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )
        return image
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard
            let tiff = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(
                using: .png,
                properties: [:]
            ),
            ShareCardMetadataAudit.hasNoHiddenTextMetadata(pngData: data)
        else { return nil }
        return data
    }

    private static func drawMetric(
        _ value: String,
        label: String,
        x: CGFloat
    ) {
        value.draw(
            at: NSPoint(x: x, y: 270),
            withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(
                    ofSize: 72,
                    weight: .bold
                ),
                .foregroundColor: NSColor(
                    calibratedRed: 0.40,
                    green: 0.82,
                    blue: 0.95,
                    alpha: 1
                ),
            ]
        )
        label.draw(
            at: NSPoint(x: x, y: 228),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 22),
                .foregroundColor: NSColor.white,
            ]
        )
    }
}
