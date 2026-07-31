import Foundation

/// Internal release gates for incomplete or externally dependent capabilities.
///
/// Flags are explicit opt-ins. Missing, unknown, and malformed values never
/// enable a capability.
public enum FeatureFlag: String, CaseIterable, Sendable {
    case hudEdgePlacement = "HUD_EDGE_PLACEMENT"
    case longDictation20 = "LONG_DICTATION_20"
    case mouseFlow = "MOUSE_FLOW"
    case minimalContext = "MINIMAL_CONTEXT"
    case localTransforms = "LOCAL_TRANSFORMS"
    case persistentRecovery = "PERSISTENT_RECOVERY"
    case workspaceV2 = "WORKSPACE_V2"
    case scratchpad = "SCRATCHPAD"
    case notifications = "NOTIFICATIONS"
    case advancedInsights = "ADVANCED_INSIGHTS"
    case encryptedSync = "ENCRYPTED_SYNC"
    case accounts = "ACCOUNTS"

    public var environmentKey: String {
        Brand.environmentPrefix + rawValue
    }
}

public struct FeatureFlags: Equatable, Sendable {
    private static let enabledValues: Set<String> = [
        "1",
        "true",
        "yes",
        "on",
    ]

    private let enabledFlags: Set<FeatureFlag>

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        enabledFlags = Set(
            FeatureFlag.allCases.filter { flag in
                guard let value = environment[flag.environmentKey] else {
                    return false
                }
                return Self.enabledValues.contains(value.lowercased())
            }
        )
    }

    public func isEnabled(_ flag: FeatureFlag) -> Bool {
        enabledFlags.contains(flag)
    }
}
