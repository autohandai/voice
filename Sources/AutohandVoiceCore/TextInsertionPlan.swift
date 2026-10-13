import Foundation

public enum TextInsertionStrategy: String, Equatable, Sendable {
    case accessibilitySelectedText
    case clipboardPreservingPaste
    case unicodeEvents
    case ownProcessResponder
}

public enum TextTargetProfile: String, Equatable, Sendable {
    case generic
    case appleTerminal
    case iTerm2
    case warp

    public var isTestedTerminal: Bool {
        self != .generic
    }
}

public struct TextInsertionPlan: Equatable, Sendable {
    public let profile: TextTargetProfile
    public let strategies: [TextInsertionStrategy]

    public init(
        profile: TextTargetProfile,
        strategies: [TextInsertionStrategy]
    ) {
        self.profile = profile
        self.strategies = strategies
    }
}

public enum TextInsertionPlanSelector {
    private static let terminalRoles: Set<String> = [
        "AXTextArea",
        "AXTextField",
    ]

    public static func profile(
        for context: TextInsertionContext
    ) -> TextTargetProfile {
        guard
            let role = context.accessibilityRole,
            terminalRoles.contains(role)
        else { return .generic }
        switch context.appBundleIdentifier {
        case "com.apple.Terminal":
            return .appleTerminal
        case "com.googlecode.iterm2":
            return .iTerm2
        case "dev.warp.Warp", "dev.warp.Warp-Stable":
            return .warp
        default:
            return .generic
        }
    }

    public static func plan(
        for context: TextInsertionContext
    ) -> TextInsertionPlan {
        if context.isOwnProcess {
            // Synthetic Command-V posted to this app is not routed to its
            // own text fields, so insert through the key window's responder.
            return TextInsertionPlan(
                profile: .generic,
                strategies: [
                    .ownProcessResponder,
                    .clipboardPreservingPaste,
                ]
            )
        }
        let profile = profile(for: context)
        if profile.isTestedTerminal {
            return TextInsertionPlan(
                profile: profile,
                strategies: [
                    .accessibilitySelectedText,
                    .unicodeEvents,
                ]
            )
        }
        return TextInsertionPlan(
            profile: .generic,
            strategies: [
                .clipboardPreservingPaste,
                .accessibilitySelectedText,
            ]
        )
    }
}
