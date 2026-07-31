import CryptoKit
import Foundation

public struct TextTargetDescriptor: Equatable, Sendable {
    public let bundleIdentifier: String?
    public let accessibilityRole: String?
    public let accessibilitySubrole: String?
    public let isProtectedContent: Bool

    public init(
        bundleIdentifier: String?,
        accessibilityRole: String?,
        accessibilitySubrole: String? = nil,
        isProtectedContent: Bool = false
    ) {
        self.bundleIdentifier = bundleIdentifier.map {
            String($0.prefix(255))
        }
        self.accessibilityRole = accessibilityRole.map {
            String($0.prefix(64))
        }
        self.accessibilitySubrole = accessibilitySubrole.map {
            String($0.prefix(64))
        }
        self.isProtectedContent = isProtectedContent
    }

    public var isSecureField: Bool {
        isProtectedContent
            || accessibilityRole == "AXSecureTextField"
            || accessibilitySubrole == "AXSecureTextField"
    }
}

public enum AppContextAccess: String, Codable, CaseIterable, Sendable {
    case inherit
    case enabled
    case disabled
}

public enum SensitiveContextDenial: String, Codable, Equatable, Sendable {
    case secureField
    case builtInSensitiveApp
    case localDenylist
    case profileSensitive
}

public enum SensitiveContextDecision: Equatable, Sendable {
    case deny(SensitiveContextDenial)
    case allow(contextScalarLimit: Int)
}

public struct SensitiveContextConfiguration: Equatable, Sendable {
    public let contextEnabled: Bool
    public let requestedScalarLimit: Int
    public let localDenylist: [String]
    public let profileContextAccess: AppContextAccess
    public let profileIsSensitive: Bool
    public let allowsBuiltInSensitiveApp: Bool

    public init(
        contextEnabled: Bool = false,
        requestedScalarLimit: Int = SensitiveContextPolicy.maximumScalars,
        localDenylist: [String] = [],
        profileContextAccess: AppContextAccess = .inherit,
        profileIsSensitive: Bool = false,
        allowsBuiltInSensitiveApp: Bool = false
    ) {
        self.contextEnabled = contextEnabled
        self.requestedScalarLimit = requestedScalarLimit
        self.localDenylist = Array(
            Set(
                localDenylist
                    .filter { !$0.isEmpty }
                    .map { String($0.prefix(255)) }
            )
        )
        self.profileContextAccess = profileContextAccess
        self.profileIsSensitive = profileIsSensitive
        self.allowsBuiltInSensitiveApp = allowsBuiltInSensitiveApp
    }
}

public struct SensitiveAppRuleset: Equatable, Sendable {
    public let version: String
    public let bundleIdentifiers: [String]
    public let signature: Data

    public init(
        version: String,
        bundleIdentifiers: [String],
        signature: Data
    ) {
        self.version = String(version.prefix(32))
        self.bundleIdentifiers = Array(
            Set(
                bundleIdentifiers
                    .filter { !$0.isEmpty }
                    .map { String($0.prefix(255)) }
            )
        ).sorted()
        self.signature = Data(signature.prefix(128))
    }

    public var canonicalPayload: Data {
        Data(
            ([version] + bundleIdentifiers)
                .joined(separator: "\n")
                .utf8
        )
    }

    public var hasValidSignature: Bool {
        guard
            let publicKeyData = Data(
                base64Encoded:
                    "HAGQz0EYj7p1nP/znRaTVO7KLsNUSN3sgb43tJCHOw4="
            ),
            let publicKey = try? Curve25519.Signing.PublicKey(
                rawRepresentation: publicKeyData
            )
        else { return false }
        return publicKey.isValidSignature(
            signature,
            for: canonicalPayload
        )
    }

    public static let builtIn = SensitiveAppRuleset(
        version: "v1",
        bundleIdentifiers: [
            "com.1password.1password",
            "com.apple.Passwords",
            "com.bitwarden.desktop",
            "com.dashlane.Dashlane",
            "org.keepassxc.keepassxc",
        ],
        signature: Data(
            base64Encoded:
                "1F+puxc2/2E9k3NzD635VK7GnXaSCtX5ugIBF9Wbg/C8CeZ0t7F1dVDH+sopA5Su9tcuO+WN5H6o/noMoOdjDA=="
        ) ?? Data()
    )
}

public struct SensitiveContextPolicy: Sendable {
    public static let maximumScalars = 64

    private let ruleset: SensitiveAppRuleset

    public init(ruleset: SensitiveAppRuleset = .builtIn) {
        self.ruleset = ruleset
    }

    public func decision(
        for target: TextTargetDescriptor,
        configuration: SensitiveContextConfiguration
    ) -> SensitiveContextDecision {
        if target.isSecureField {
            return .deny(.secureField)
        }
        if configuration.profileIsSensitive {
            return .deny(.profileSensitive)
        }
        if let bundleIdentifier = target.bundleIdentifier {
            if configuration.localDenylist.contains(bundleIdentifier) {
                return .deny(.localDenylist)
            }
            if !configuration.allowsBuiltInSensitiveApp,
               ruleset.hasValidSignature,
               ruleset.bundleIdentifiers.contains(bundleIdentifier) {
                return .deny(.builtInSensitiveApp)
            }
        }
        guard
            configuration.contextEnabled,
            configuration.profileContextAccess != .disabled
        else {
            return .allow(contextScalarLimit: 0)
        }
        return .allow(
            contextScalarLimit: min(
                max(configuration.requestedScalarLimit, 0),
                Self.maximumScalars
            )
        )
    }
}
