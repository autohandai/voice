import Foundation

public enum AudioRouteSelectionReason:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case currentRoute = "current_route"
    case rankedPreference = "ranked_preference"
    case systemDefault = "system_default"
    case externalForClamshell = "external_for_clamshell"
    case firstAvailable = "first_available"
}

public struct AudioRouteSelection: Codable, Equatable, Sendable {
    public let deviceUID: String
    public let reason: AudioRouteSelectionReason
    public let requiresSegmentBoundary: Bool

    public init(
        deviceUID: String,
        reason: AudioRouteSelectionReason,
        requiresSegmentBoundary: Bool
    ) {
        self.deviceUID = deviceUID
        self.reason = reason
        self.requiresSegmentBoundary = requiresSegmentBoundary
    }
}

public enum AudioRouteResolution: Equatable, Sendable {
    case selected(AudioRouteSelection)
    case unavailable(AudioRouteFailure)
}

public enum AudioRouteSegmentOutcome:
    String,
    Codable,
    Equatable,
    Sendable
{
    case active
    case handedOff = "handed_off"
    case finalized
    case cancelled
    case disconnected
    case failed
}

public struct AudioRouteSegment: Codable, Equatable, Sendable {
    public let deviceUID: String
    public let startedAtUptime: TimeInterval
    public var endedAtUptime: TimeInterval?
    public var outcome: AudioRouteSegmentOutcome

    public init(
        deviceUID: String,
        startedAtUptime: TimeInterval,
        endedAtUptime: TimeInterval? = nil,
        outcome: AudioRouteSegmentOutcome = .active
    ) {
        self.deviceUID = String(deviceUID.prefix(128))
        self.startedAtUptime = max(0, startedAtUptime)
        self.endedAtUptime = endedAtUptime.map {
            max(max(0, startedAtUptime), $0)
        }
        self.outcome = outcome
    }
}

public struct AudioRouteTimeline: Codable, Equatable, Sendable {
    public static let maximumSegments = 16

    public private(set) var segments: [AudioRouteSegment]

    public init(segments: [AudioRouteSegment] = []) {
        self.segments = Array(
            segments.suffix(Self.maximumSegments)
        )
    }

    public mutating func start(
        deviceUID: String,
        at uptime: TimeInterval
    ) {
        guard segments.last?.outcome != .active else { return }
        segments.append(
            AudioRouteSegment(
                deviceUID: deviceUID,
                startedAtUptime: uptime
            )
        )
        if segments.count > Self.maximumSegments {
            segments.removeFirst(segments.count - Self.maximumSegments)
        }
    }

    public mutating func handoff(
        to deviceUID: String,
        at uptime: TimeInterval
    ) {
        finishCurrent(as: .handedOff, at: uptime)
        start(deviceUID: deviceUID, at: uptime)
    }

    public mutating func finishCurrent(
        as outcome: AudioRouteSegmentOutcome,
        at uptime: TimeInterval
    ) {
        guard
            !segments.isEmpty,
            segments[segments.count - 1].outcome == .active
        else { return }
        segments[segments.count - 1].endedAtUptime = max(
            segments[segments.count - 1].startedAtUptime,
            uptime
        )
        segments[segments.count - 1].outcome = outcome
    }
}

public struct AudioRoutePolicy: Codable, Equatable, Sendable {
    public static let maximumRankedDevices = 16
    public static let systemDefaultSentinel = "__system_default__"

    public let rankedDeviceUIDs: [String]
    public let automaticHandoffEnabled: Bool

    public init(
        rankedDeviceUIDs: [String] = [],
        automaticHandoffEnabled: Bool = false
    ) {
        self.rankedDeviceUIDs = Self.normalized(
            rankedDeviceUIDs
        )
        self.automaticHandoffEnabled = automaticHandoffEnabled
    }

    public func resolve(
        devices: [AudioInputDevice],
        clamshellClosed: Bool
    ) -> AudioRouteResolution {
        let eligible = devices.filter {
            !clamshellClosed || $0.kind != .builtIn
        }
        guard !eligible.isEmpty else {
            return .unavailable(
                clamshellClosed
                    ? .clamshellNoInput
                    : .selectionFailed
            )
        }

        let byID = Dictionary(
            eligible.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for rankedID in rankedDeviceUIDs {
            if rankedID == Self.systemDefaultSentinel,
               let systemDefault = eligible.first(where: \.isSystemDefault) {
                return .selected(
                    AudioRouteSelection(
                        deviceUID: systemDefault.id,
                        reason: clamshellClosed
                            ? .externalForClamshell
                            : .systemDefault,
                        requiresSegmentBoundary: false
                    )
                )
            }
            if let ranked = byID[rankedID] {
                return .selected(
                    AudioRouteSelection(
                        deviceUID: ranked.id,
                        reason: clamshellClosed
                            ? .externalForClamshell
                            : .rankedPreference,
                        requiresSegmentBoundary: false
                    )
                )
            }
        }
        if let systemDefault = eligible.first(where: \.isSystemDefault) {
            return .selected(
                AudioRouteSelection(
                    deviceUID: systemDefault.id,
                    reason: clamshellClosed
                        ? .externalForClamshell
                        : .systemDefault,
                    requiresSegmentBoundary: false
                )
            )
        }
        let first = eligible.sorted {
            if $0.name != $1.name {
                return $0.name.localizedStandardCompare($1.name)
                    == .orderedAscending
            }
            return $0.id < $1.id
        }[0]
        return .selected(
            AudioRouteSelection(
                deviceUID: first.id,
                reason: clamshellClosed
                    ? .externalForClamshell
                    : .firstAvailable,
                requiresSegmentBoundary: false
            )
        )
    }

    public func resolveHandoff(
        currentDeviceUID: String,
        devices: [AudioInputDevice],
        clamshellClosed: Bool
    ) -> AudioRouteResolution {
        if let current = devices.first(where: {
            $0.id == currentDeviceUID
        }), !clamshellClosed || current.kind != .builtIn {
            if automaticHandoffEnabled,
               case let .selected(preferred) = resolve(
                   devices: devices,
                   clamshellClosed: clamshellClosed
               ),
               preferred.deviceUID != current.id
            {
                return .selected(
                    AudioRouteSelection(
                        deviceUID: preferred.deviceUID,
                        reason: preferred.reason,
                        requiresSegmentBoundary: true
                    )
                )
            }
            return .selected(
                AudioRouteSelection(
                    deviceUID: current.id,
                    reason: .currentRoute,
                    requiresSegmentBoundary: false
                )
            )
        }
        guard automaticHandoffEnabled else {
            return .unavailable(.routeChanged)
        }
        switch resolve(
            devices: devices,
            clamshellClosed: clamshellClosed
        ) {
        case let .selected(selection):
            return .selected(
                AudioRouteSelection(
                    deviceUID: selection.deviceUID,
                    reason: selection.reason,
                    requiresSegmentBoundary: true
                )
            )
        case let .unavailable(failure):
            return .unavailable(failure)
        }
    }

    static func normalized(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !value.isEmpty {
            guard seen.insert(value).inserted else { continue }
            result.append(value)
            if result.count == maximumRankedDevices {
                break
            }
        }
        return result
    }
}
