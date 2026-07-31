import XCTest
@testable import AutohandVoiceCore

final class SensitiveContextPolicyTests: XCTestCase {
    func testSecureFieldAlwaysDeniesBeforeAnyContextAccess() {
        let policy = SensitiveContextPolicy()
        let descriptor = TextTargetDescriptor(
            bundleIdentifier: "com.example.Editor",
            accessibilityRole: "AXTextField",
            accessibilitySubrole: "AXSecureTextField"
        )

        XCTAssertEqual(
            policy.decision(
                for: descriptor,
                configuration: .init(contextEnabled: true)
            ),
            .deny(.secureField)
        )
    }

    func testVerifiedBuiltInAndLocalRulesDenyExactBundleOnly() {
        let policy = SensitiveContextPolicy()

        XCTAssertTrue(SensitiveAppRuleset.builtIn.hasValidSignature)
        XCTAssertEqual(
            policy.decision(
                for: .init(
                    bundleIdentifier: "com.1password.1password",
                    accessibilityRole: "AXTextField"
                ),
                configuration: .init(contextEnabled: true)
            ),
            .deny(.builtInSensitiveApp)
        )
        XCTAssertEqual(
            policy.decision(
                for: .init(
                    bundleIdentifier: "com.example.Secret",
                    accessibilityRole: "AXTextArea"
                ),
                configuration: .init(
                    contextEnabled: true,
                    localDenylist: ["com.example.Secret"]
                )
            ),
            .deny(.localDenylist)
        )
        XCTAssertEqual(
            policy.decision(
                for: .init(
                    bundleIdentifier: "com.example.Secret.beta",
                    accessibilityRole: "AXTextArea"
                ),
                configuration: .init(
                    contextEnabled: true,
                    localDenylist: ["com.example.Secret"]
                )
            ),
            .allow(contextScalarLimit: SensitiveContextPolicy.maximumScalars)
        )
    }

    func testContextDefaultsToNoneAndProfileCanDisableGlobalConsent() {
        let policy = SensitiveContextPolicy()
        let descriptor = TextTargetDescriptor(
            bundleIdentifier: "com.example.Editor",
            accessibilityRole: "AXTextArea"
        )

        XCTAssertEqual(
            policy.decision(for: descriptor, configuration: .init()),
            .allow(contextScalarLimit: 0)
        )
        XCTAssertEqual(
            policy.decision(
                for: descriptor,
                configuration: .init(
                    contextEnabled: true,
                    profileContextAccess: .disabled
                )
            ),
            .allow(contextScalarLimit: 0)
        )
        XCTAssertEqual(
            policy.decision(
                for: descriptor,
                configuration: .init(
                    contextEnabled: true,
                    requestedScalarLimit: 10_000
                )
            ),
            .allow(contextScalarLimit: SensitiveContextPolicy.maximumScalars)
        )
    }

    func testProfileSensitiveClassificationWinsOverContextConsent() {
        let decision = SensitiveContextPolicy().decision(
            for: .init(
                bundleIdentifier: "com.example.Health",
                accessibilityRole: "AXTextArea"
            ),
            configuration: .init(
                contextEnabled: true,
                profileIsSensitive: true
            )
        )

        XCTAssertEqual(decision, .deny(.profileSensitive))
    }

    func testExplicitProfileOverrideCanAllowBuiltInAppButNotSecureField() {
        let policy = SensitiveContextPolicy()
        let configuration = SensitiveContextConfiguration(
            allowsBuiltInSensitiveApp: true
        )

        XCTAssertEqual(
            policy.decision(
                for: .init(
                    bundleIdentifier: "com.1password.1password",
                    accessibilityRole: "AXTextArea"
                ),
                configuration: configuration
            ),
            .allow(contextScalarLimit: 0)
        )
        XCTAssertEqual(
            policy.decision(
                for: .init(
                    bundleIdentifier: "com.1password.1password",
                    accessibilityRole: "AXSecureTextField"
                ),
                configuration: configuration
            ),
            .deny(.secureField)
        )
    }
}
