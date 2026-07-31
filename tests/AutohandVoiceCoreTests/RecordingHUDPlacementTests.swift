import XCTest
@testable import AutohandVoiceCore

final class RecordingHUDPlacementTests: XCTestCase {
    func testSideAnchorsUseACompactVerticalSize() {
        let bottom = RecordingHUDPlacement.contentSize(
            anchor: .bottom,
            livePreviewEnabled: false,
            hasPreviewContent: false
        )
        let side = RecordingHUDPlacement.contentSize(
            anchor: .left,
            livePreviewEnabled: false,
            hasPreviewContent: false
        )

        XCTAssertGreaterThan(bottom.width, bottom.height)
        XCTAssertGreaterThan(side.height, side.width)
    }

    func testAnchorSwitchRequiresCrossingTheMovementThreshold() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 800)

        XCTAssertEqual(
            RecordingHUDPlacement.preferredAnchor(
                for: CGRect(x: 520, y: 45, width: 200, height: 60),
                visibleFrame: visible,
                current: .bottom
            ),
            .bottom
        )
        XCTAssertEqual(
            RecordingHUDPlacement.preferredAnchor(
                for: CGRect(x: 10, y: 330, width: 160, height: 180),
                visibleFrame: visible,
                current: .bottom
            ),
            .left
        )
    }

    func testCompactContentSizeExpandsOnlyForActualPreviewContent() {
        XCTAssertEqual(
            RecordingHUDPlacement.contentSize(
                livePreviewEnabled: false,
                hasPreviewContent: false
            ),
            CGSize(width: 156, height: 44)
        )
        XCTAssertEqual(
            RecordingHUDPlacement.contentSize(
                livePreviewEnabled: true,
                hasPreviewContent: false
            ),
            CGSize(width: 156, height: 44)
        )
        XCTAssertEqual(
            RecordingHUDPlacement.contentSize(
                livePreviewEnabled: true,
                hasPreviewContent: true
            ),
            CGSize(width: 180, height: 64)
        )
    }

    func testPlacesHUDAtBottomCenterInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 1_440, y: 40, width: 1_920, height: 1_040)
        let windowSize = CGSize(width: 420, height: 132)

        let frame = RecordingHUDPlacement.frame(
            visibleFrame: visibleFrame,
            windowSize: windowSize
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX)
        XCTAssertEqual(frame.minY, visibleFrame.minY + 40)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testClampsOversizedHUDInsideSmallVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 24, width: 320, height: 200)

        let frame = RecordingHUDPlacement.frame(
            visibleFrame: visibleFrame,
            windowSize: CGSize(width: 420, height: 132)
        )

        XCTAssertEqual(frame.minX, visibleFrame.minX)
        XCTAssertEqual(frame.width, visibleFrame.width)
        XCTAssertTrue(visibleFrame.contains(frame))
    }

    func testLeftAndRightAnchorsRespectVisibleFrameAndOffsets() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1_000, height: 700)
        let size = CGSize(width: 300, height: 60)

        let left = RecordingHUDPlacement.frame(
            visibleFrame: visibleFrame,
            windowSize: size,
            anchor: .left,
            offset: CGSize(width: 15, height: 20)
        )
        let right = RecordingHUDPlacement.frame(
            visibleFrame: visibleFrame,
            windowSize: size,
            anchor: .right,
            offset: CGSize(width: -15, height: -20)
        )

        XCTAssertEqual(left.minX, visibleFrame.minX + 20 + 15)
        XCTAssertEqual(left.midY, visibleFrame.midY + 20)
        XCTAssertEqual(right.maxX, visibleFrame.maxX - 20 - 15)
        XCTAssertEqual(right.midY, visibleFrame.midY - 20)
        XCTAssertTrue(visibleFrame.contains(left))
        XCTAssertTrue(visibleFrame.contains(right))
    }

    func testDraggedFrameRoundTripsToBoundedOffset() {
        let visibleFrame = CGRect(x: 0, y: 24, width: 1_440, height: 876)
        let size = CGSize(width: 292, height: 56)
        let dragged = CGRect(x: 31, y: 410, width: size.width, height: size.height)

        let preference = RecordingHUDPlacement.preference(
            for: dragged,
            visibleFrame: visibleFrame,
            anchor: .left
        )
        let restored = RecordingHUDPlacement.frame(
            visibleFrame: visibleFrame,
            windowSize: size,
            anchor: preference.anchor,
            offset: preference.offset
        )

        XCTAssertEqual(restored.origin.x, dragged.origin.x, accuracy: 0.001)
        XCTAssertEqual(restored.origin.y, dragged.origin.y, accuracy: 0.001)
    }

    func testPresentationPreferencesClampOpacityAndDisplayCount() {
        let placements = (0..<20).map {
            RecordingHUDDisplayPreference(
                displayID: "display-\($0)",
                anchor: .right,
                offset: CGSize(width: 50_000, height: -50_000)
            )
        }
        let preferences = RecordingHUDPreferences(
            mode: .dot,
            opacity: 0.05,
            displays: placements
        )

        XCTAssertEqual(preferences.opacity, 0.2)
        XCTAssertEqual(
            preferences.displays.count,
            RecordingHUDPreferences.maximumDisplays
        )
        XCTAssertTrue(
            preferences.displays.allSatisfy {
                abs($0.offset.width) <= 10_000
                    && abs($0.offset.height) <= 10_000
            }
        )
    }

    func testDotPresentationHasCompactFixedSize() {
        XCTAssertEqual(
            RecordingHUDPlacement.contentSize(
                mode: .dot,
                livePreviewEnabled: true,
                hasPreviewContent: true
            ),
            CGSize(width: 31, height: 31)
        )
    }
}
