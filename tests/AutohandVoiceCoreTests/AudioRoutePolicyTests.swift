import XCTest
@testable import AutohandVoiceCore

final class AudioRoutePolicyTests: XCTestCase {
    func testRankedPolicyChoosesFirstAvailableUniquePreference() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: ["usb", "missing", "usb", "bluetooth"],
            automaticHandoffEnabled: true
        )
        let devices = [
            device("bluetooth", kind: .bluetooth),
            device("built-in", kind: .builtIn, isDefault: true),
            device("usb", kind: .usb),
        ]

        let resolution = policy.resolve(
            devices: devices,
            clamshellClosed: false
        )

        XCTAssertEqual(policy.rankedDeviceUIDs, ["usb", "missing", "bluetooth"])
        XCTAssertEqual(
            resolution,
            .selected(
                AudioRouteSelection(
                    deviceUID: "usb",
                    reason: .rankedPreference,
                    requiresSegmentBoundary: false
                )
            )
        )
    }

    func testSystemDefaultAndFirstAvailableAreDeterministicFallbacks() {
        let policy = AudioRoutePolicy()
        let devices = [
            device("z-device", kind: .usb),
            device("default", kind: .builtIn, isDefault: true),
            device("a-device", kind: .bluetooth),
        ]

        XCTAssertEqual(
            policy.resolve(devices: devices, clamshellClosed: false),
            .selected(
                AudioRouteSelection(
                    deviceUID: "default",
                    reason: .systemDefault,
                    requiresSegmentBoundary: false
                )
            )
        )

        let noDefault = devices.map {
            device($0.id, kind: $0.kind, isDefault: false)
        }
        XCTAssertEqual(
            policy.resolve(devices: noDefault, clamshellClosed: false),
            .selected(
                AudioRouteSelection(
                    deviceUID: "a-device",
                    reason: .firstAvailable,
                    requiresSegmentBoundary: false
                )
            )
        )
    }

    func testSystemDefaultCanBeRankedAheadOfNamedDevices() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: [
                AudioRoutePolicy.systemDefaultSentinel,
                "usb",
            ]
        )

        XCTAssertEqual(
            policy.resolve(
                devices: [
                    device("usb", kind: .usb),
                    device(
                        "bluetooth",
                        kind: .bluetooth,
                        isDefault: true
                    ),
                ],
                clamshellClosed: false
            ),
            .selected(
                AudioRouteSelection(
                    deviceUID: "bluetooth",
                    reason: .systemDefault,
                    requiresSegmentBoundary: false
                )
            )
        )
    }

    func testReorderingDuringCaptureUsesHandoffBoundary() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: ["usb", "bluetooth"],
            automaticHandoffEnabled: true
        )

        XCTAssertEqual(
            policy.resolveHandoff(
                currentDeviceUID: "bluetooth",
                devices: [
                    device("bluetooth", kind: .bluetooth),
                    device("usb", kind: .usb),
                ],
                clamshellClosed: false
            ),
            .selected(
                AudioRouteSelection(
                    deviceUID: "usb",
                    reason: .rankedPreference,
                    requiresSegmentBoundary: true
                )
            )
        )
    }

    func testClamshellAvoidsBuiltInInputAndExplainsNoExternalRoute() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: ["built-in", "usb"]
        )

        XCTAssertEqual(
            policy.resolve(
                devices: [
                    device("built-in", kind: .builtIn, isDefault: true),
                    device("usb", kind: .usb),
                ],
                clamshellClosed: true
            ),
            .selected(
                AudioRouteSelection(
                    deviceUID: "usb",
                    reason: .externalForClamshell,
                    requiresSegmentBoundary: false
                )
            )
        )

        XCTAssertEqual(
            policy.resolve(
                devices: [
                    device("built-in", kind: .builtIn, isDefault: true),
                ],
                clamshellClosed: true
            ),
            .unavailable(.clamshellNoInput)
        )
    }

    func testAutomaticHandoffCreatesExplicitSegmentBoundary() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: ["usb", "bluetooth"],
            automaticHandoffEnabled: true
        )
        let devices = [
            device("bluetooth", kind: .bluetooth, isDefault: true),
        ]

        XCTAssertEqual(
            policy.resolveHandoff(
                currentDeviceUID: "usb",
                devices: devices,
                clamshellClosed: false
            ),
            .selected(
                AudioRouteSelection(
                    deviceUID: "bluetooth",
                    reason: .rankedPreference,
                    requiresSegmentBoundary: true
                )
            )
        )
    }

    func testDisabledHandoffKeepsFailureExplicit() {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: ["usb", "bluetooth"],
            automaticHandoffEnabled: false
        )

        XCTAssertEqual(
            policy.resolveHandoff(
                currentDeviceUID: "usb",
                devices: [
                    device("bluetooth", kind: .bluetooth, isDefault: true),
                ],
                clamshellClosed: false
            ),
            .unavailable(.routeChanged)
        )
    }

    private func device(
        _ id: String,
        kind: AudioInputDeviceKind,
        isDefault: Bool = false
    ) -> AudioInputDevice {
        AudioInputDevice(
            id: id,
            name: id,
            isSystemDefault: isDefault,
            kind: kind
        )
    }
}

final class AudioRouteTimelineTests: XCTestCase {
    func testHandoffCreatesExplicitFinalizedSegments() {
        var timeline = AudioRouteTimeline()
        timeline.start(deviceUID: "built-in", at: 10)
        timeline.handoff(to: "usb", at: 20)
        timeline.finishCurrent(as: .finalized, at: 30)

        XCTAssertEqual(
            timeline.segments,
            [
                AudioRouteSegment(
                    deviceUID: "built-in",
                    startedAtUptime: 10,
                    endedAtUptime: 20,
                    outcome: .handedOff
                ),
                AudioRouteSegment(
                    deviceUID: "usb",
                    startedAtUptime: 20,
                    endedAtUptime: 30,
                    outcome: .finalized
                ),
            ]
        )
    }

    func testTimelineIsBoundedAndDoesNotDoubleFinish() {
        var timeline = AudioRouteTimeline()
        for index in 0 ..< 24 {
            timeline.start(
                deviceUID: "device-\(index)",
                at: Double(index)
            )
            timeline.finishCurrent(
                as: .handedOff,
                at: Double(index) + 0.5
            )
        }
        timeline.finishCurrent(as: .failed, at: 100)

        XCTAssertEqual(
            timeline.segments.count,
            AudioRouteTimeline.maximumSegments
        )
        XCTAssertEqual(timeline.segments.first?.deviceUID, "device-8")
        XCTAssertEqual(timeline.segments.last?.outcome, .handedOff)
    }
}
