import Foundation
import XCTest
@testable import AutohandVoiceCore

final class AccountIntegrationTests: XCTestCase {
    private let state = "state_12345678901234567890"
    private let nonce = "nonce_12345678901234567890"
    private let verifier =
        "verifier_12345678901234567890123456789012345"

    func testAuthorizationRequestUsesPKCEStateNonceAndExactCallback()
        throws
    {
        let session = try fixtureSession()
        let authorization = try session.authorizationURL(
            endpoint: URL(string: "https://accounts.autohand.ai/oauth")!,
            clientID: "voice-macos",
            scopes: ["openid", "profile"]
        )
        let query = try XCTUnwrap(
            URLComponents(
                url: authorization,
                resolvingAgainstBaseURL: false
            )?.queryItems
        )

        XCTAssertEqual(value("state", in: query), state)
        XCTAssertEqual(value("nonce", in: query), nonce)
        XCTAssertEqual(
            value("code_challenge_method", in: query),
            "S256"
        )
        XCTAssertNotEqual(
            value("code_challenge", in: query),
            verifier
        )
    }

    func testCallbackRejectsSpoofedOriginAndMismatchedState()
        throws
    {
        let session = try fixtureSession()

        XCTAssertThrowsError(
            try session.validateCallback(
                URL(
                    string:
                        "autohand-voice://attacker/callback?state=\(state)&code=secret"
                )!
            )
        ) { error in
            XCTAssertEqual(
                error as? AccountIntegrationError,
                .invalidCallback
            )
        }
        XCTAssertThrowsError(
            try session.validateCallback(
                URL(
                    string:
                        "autohand-voice://oauth/callback?state=wrong_state_123456789&code=secret"
                )!
            )
        ) { error in
            XCTAssertEqual(
                error as? AccountIntegrationError,
                .stateMismatch
            )
        }
    }

    func testValidCallbackReturnsOnlyTheAuthorizationCode() throws {
        let session = try fixtureSession()
        let callback = URL(
            string:
                "autohand-voice://oauth/callback?state=\(state)&code=authorization-code"
        )!

        XCTAssertEqual(
            try session.validateCallback(callback),
            "authorization-code"
        )
    }

    func testAdminAndBAABoundariesNeverExposePrivateContent() {
        let admin = AccountAuthorizationBoundary(
            role: .itAdministrator
        )
        let enforced = EnforcedPrivacyPolicy(
            verifiedBAAEnforcement: true
        )

        XCTAssertEqual(
            admin.adminCapabilities,
            Set(AccountAdminCapability.allCases)
        )
        XCTAssertFalse(admin.canAccessPrivateUserContent)
        XCTAssertTrue(enforced.syncPolicy.enabledClasses.isEmpty)
        XCTAssertFalse(enforced.diagnosticSharingAllowed)
    }

    func testSignOutNeverDeletesLocalDataWithoutSeparateConfirmation() {
        let keep = AccountSignOutPlan(
            deleteLocalDataRequested: false
        )
        let delete = AccountSignOutPlan(
            deleteLocalDataRequested: true
        )

        XCTAssertTrue(keep.revokeCredential)
        XCTAssertFalse(keep.deleteLocalDataRequested)
        XCTAssertFalse(keep.requiresSeparateLocalDataConfirmation)
        XCTAssertTrue(delete.requiresSeparateLocalDataConfirmation)
    }

    func testDecodedCredentialsEnforceTheSameBoundsAsNewCredentials()
        throws
    {
        let valid = try AccountCredential(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                AccountCredential.self,
                from: JSONEncoder().encode(valid)
            ),
            valid
        )

        let invalid = """
        {
          "accessToken": "",
          "expiresAt": 0
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                AccountCredential.self,
                from: invalid
            )
        ) { error in
            XCTAssertEqual(
                error as? AccountIntegrationError,
                .invalidCredential
            )
        }
    }

    private func fixtureSession() throws -> PKCEAuthorizationSession {
        try PKCEAuthorizationSession(
            callbackURL: URL(
                string: "autohand-voice://oauth/callback"
            )!,
            state: state,
            nonce: nonce,
            codeVerifier: verifier
        )
    }

    private func value(
        _ name: String,
        in items: [URLQueryItem]
    ) -> String? {
        items.first { $0.name == name }?.value
    }
}
