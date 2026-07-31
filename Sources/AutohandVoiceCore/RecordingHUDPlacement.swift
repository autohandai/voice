import CoreGraphics
import Foundation

public enum RecordingHUDAnchor: String, Codable, CaseIterable, Sendable {
    case left
    case bottom
    case right
}

public enum RecordingHUDPresentationMode:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case automatic
    case compact
    case dot
}

public struct RecordingHUDDisplayPreference:
    Codable,
    Equatable,
    Sendable
{
    public let displayID: String
    public let anchor: RecordingHUDAnchor
    public let offset: CGSize

    public init(
        displayID: String,
        anchor: RecordingHUDAnchor,
        offset: CGSize
    ) {
        self.displayID = String(displayID.prefix(128))
        self.anchor = anchor
        self.offset = CGSize(
            width: min(max(offset.width, -10_000), 10_000),
            height: min(max(offset.height, -10_000), 10_000)
        )
    }
}

public struct RecordingHUDPreferences: Codable, Equatable, Sendable {
    public static let maximumDisplays = 8

    public let mode: RecordingHUDPresentationMode
    public let opacity: Double
    public let displays: [RecordingHUDDisplayPreference]

    public init(
        mode: RecordingHUDPresentationMode = .automatic,
        opacity: Double = 0.8,
        displays: [RecordingHUDDisplayPreference] = []
    ) {
        self.mode = mode
        self.opacity = min(max(opacity, 0.2), 1)
        var seen = Set<String>()
        self.displays = displays.filter {
            !$0.displayID.isEmpty && seen.insert($0.displayID).inserted
        }.prefix(Self.maximumDisplays).map { $0 }
    }

    public func placement(
        for displayID: String
    ) -> RecordingHUDDisplayPreference? {
        displays.first { $0.displayID == displayID }
    }
}

public enum RecordingHUDPlacement {
    public static let visualScale: CGFloat = 0.6

    public static func contentSize(
        mode: RecordingHUDPresentationMode = .automatic,
        anchor: RecordingHUDAnchor = .bottom,
        livePreviewEnabled: Bool,
        hasPreviewContent: Bool
    ) -> CGSize {
        scaled(
            baseContentSize(
                mode: mode,
                anchor: anchor,
                livePreviewEnabled: livePreviewEnabled,
                hasPreviewContent: hasPreviewContent
            )
        )
    }

    public static func baseContentSize(
        mode: RecordingHUDPresentationMode = .automatic,
        anchor: RecordingHUDAnchor = .bottom,
        livePreviewEnabled: Bool,
        hasPreviewContent: Bool
    ) -> CGSize {
        if mode == .dot {
            return CGSize(width: 52, height: 52)
        }
        if anchor != .bottom {
            guard livePreviewEnabled, hasPreviewContent else {
                return CGSize(width: 156, height: 184)
            }
            return CGSize(width: 184, height: 228)
        }
        guard livePreviewEnabled, hasPreviewContent else {
            return CGSize(width: 260, height: 74)
        }
        return CGSize(width: 300, height: 106)
    }

    private static func scaled(_ size: CGSize) -> CGSize {
        CGSize(
            width: (size.width * visualScale).rounded(),
            height: (size.height * visualScale).rounded()
        )
    }

    public static func preferredAnchor(
        for frame: CGRect,
        visibleFrame: CGRect,
        current: RecordingHUDAnchor,
        switchingThreshold: CGFloat = 56
    ) -> RecordingHUDAnchor {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let targets: [(RecordingHUDAnchor, CGPoint)] = [
            (
                .left,
                CGPoint(
                    x: visibleFrame.minX,
                    y: visibleFrame.midY
                )
            ),
            (
                .bottom,
                CGPoint(
                    x: visibleFrame.midX,
                    y: visibleFrame.minY
                )
            ),
            (
                .right,
                CGPoint(
                    x: visibleFrame.maxX,
                    y: visibleFrame.midY
                )
            ),
        ]
        func distance(to point: CGPoint) -> CGFloat {
            hypot(center.x - point.x, center.y - point.y)
        }
        guard
            let currentTarget = targets.first(where: {
                $0.0 == current
            })?.1,
            let candidate = targets.min(by: {
                distance(to: $0.1) < distance(to: $1.1)
            })
        else { return current }
        return distance(to: candidate.1) + switchingThreshold
            < distance(to: currentTarget)
            ? candidate.0
            : current
    }

    public static func frame(
        visibleFrame: CGRect,
        windowSize: CGSize,
        anchor: RecordingHUDAnchor = .bottom,
        offset: CGSize = .zero,
        edgeMargin: CGFloat = 20,
        bottomMargin: CGFloat = 40
    ) -> CGRect {
        let size = CGSize(
            width: min(windowSize.width, visibleFrame.width),
            height: min(windowSize.height, visibleFrame.height)
        )
        let baseOrigin: CGPoint
        switch anchor {
        case .left:
            baseOrigin = CGPoint(
                x: visibleFrame.minX + edgeMargin,
                y: visibleFrame.midY - (size.height / 2)
            )
        case .bottom:
            baseOrigin = CGPoint(
                x: visibleFrame.midX - (size.width / 2),
                y: visibleFrame.minY + bottomMargin
            )
        case .right:
            baseOrigin = CGPoint(
                x: visibleFrame.maxX - edgeMargin - size.width,
                y: visibleFrame.midY - (size.height / 2)
            )
        }
        let proposedX = baseOrigin.x + offset.width
        let proposedY = baseOrigin.y + offset.height
        let maximumX = visibleFrame.maxX - size.width
        let maximumY = visibleFrame.maxY - size.height

        return CGRect(
            x: min(max(proposedX, visibleFrame.minX), maximumX),
            y: min(max(proposedY, visibleFrame.minY), maximumY),
            width: size.width,
            height: size.height
        )
    }

    public static func preference(
        for frame: CGRect,
        visibleFrame: CGRect,
        anchor: RecordingHUDAnchor
    ) -> RecordingHUDDisplayPreference {
        let base = self.frame(
            visibleFrame: visibleFrame,
            windowSize: frame.size,
            anchor: anchor
        )
        return RecordingHUDDisplayPreference(
            displayID: "",
            anchor: anchor,
            offset: CGSize(
                width: frame.minX - base.minX,
                height: frame.minY - base.minY
            )
        )
    }
}
