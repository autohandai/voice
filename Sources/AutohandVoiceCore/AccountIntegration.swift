import CryptoKit
import Foundation
import Security

public enum AccountIntegrationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case invalidConfiguration
    case invalidCallback
    case stateMismatch
    case authorizationDenied
    case missingAuthorizationCode
    case invalidCredential
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "The account integration is not configured safely."
        case .invalidCallback:
            "The sign-in callback did not match this app."
        case .stateMismatch:
            "The sign-in callback state did not match."
        case .authorizationDenied:
            "Sign-in was cancelled or denied."
        case .missingAuthorizationCode:
            "The sign-in callback did not include an authorization code."
        case .invalidCredential:
            "The account credential was invalid."
        case let .keychain(status):
            "The account credential could not be stored in Keychain "
                + "(error \(status))."
        }
    }
}

public struct PKCEAuthorizationSession:
    Equatable,
    Sendable
{
    public let callbackURL: URL
    public let state: String
    public let nonce: String
    public let codeVerifier: String

    public init(
        callbackURL: URL,
        state: String,
        nonce: String,
        codeVerifier: String
    ) throws {
        guard
            Self.isAllowedCallback(callbackURL),
            (16...256).contains(state.count),
            (16...256).contains(nonce.count),
            (43...128).contains(codeVerifier.count),
            Self.isURLSafe(state),
            Self.isURLSafe(nonce),
            Self.isURLSafe(codeVerifier)
        else {
            throw AccountIntegrationError.invalidConfiguration
        }
        self.callbackURL = callbackURL
        self.state = state
        self.nonce = nonce
        self.codeVerifier = codeVerifier
    }

    public static func create(callbackURL: URL) throws -> Self {
        try Self(
            callbackURL: callbackURL,
            state: randomURLSafe(byteCount: 24),
            nonce: randomURLSafe(byteCount: 24),
            codeVerifier: randomURLSafe(byteCount: 32)
        )
    }

    public var codeChallenge: String {
        Self.base64URL(
            Data(SHA256.hash(data: Data(codeVerifier.utf8)))
        )
    }

    public func authorizationURL(
        endpoint: URL,
        clientID: String,
        scopes: [String]
    ) throws -> URL {
        guard
            endpoint.scheme?.lowercased() == "https",
            endpoint.host?.isEmpty == false,
            (1...256).contains(clientID.count),
            !scopes.isEmpty,
            scopes.count <= 32,
            scopes.allSatisfy({
                !$0.isEmpty && $0.count <= 128
            }),
            var components = URLComponents(
                url: endpoint,
                resolvingAgainstBaseURL: false
            )
        else {
            throw AccountIntegrationError.invalidConfiguration
        }
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(
                name: "redirect_uri",
                value: callbackURL.absoluteString
            ),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(
                name: "code_challenge_method",
                value: "S256"
            ),
        ]
        guard let result = components.url else {
            throw AccountIntegrationError.invalidConfiguration
        }
        return result
    }

    public func validateCallback(_ callback: URL) throws -> String {
        guard
            Self.callbackIdentity(callback)
                == Self.callbackIdentity(callbackURL),
            let components = URLComponents(
                url: callback,
                resolvingAgainstBaseURL: false
            )
        else {
            throw AccountIntegrationError.invalidCallback
        }
        let values = Dictionary(
            grouping: components.queryItems ?? [],
            by: \.name
        )
        if values["error"]?.isEmpty == false {
            throw AccountIntegrationError.authorizationDenied
        }
        guard
            let callbackState = values["state"]?.singleValue,
            callbackState == state
        else {
            throw AccountIntegrationError.stateMismatch
        }
        guard
            let code = values["code"]?.singleValue,
            !code.isEmpty,
            code.count <= 4_096
        else {
            throw AccountIntegrationError.missingAuthorizationCode
        }
        return code
    }

    private static func callbackIdentity(
        _ url: URL
    ) -> String? {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let scheme = components.scheme?.lowercased()
        else { return nil }
        return [
            scheme,
            components.host?.lowercased() ?? "",
            components.port.map(String.init) ?? "",
            components.path,
        ].joined(separator: "|")
    }

    private static func isAllowedCallback(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        if scheme == "https" {
            return url.host?.isEmpty == false
        }
        return scheme == "autohand-voice"
            && url.host == "oauth"
            && url.path == "/callback"
    }

    private static func isURLSafe(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9._~-]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func randomURLSafe(
        byteCount: Int
    ) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(
            kSecRandomDefault,
            bytes.count,
            &bytes
        )
        guard status == errSecSuccess else {
            throw AccountIntegrationError.keychain(status)
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct AccountCredential:
    Codable,
    Equatable,
    Sendable
{
    private enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expiresAt
    }

    public let accessToken: String
    public let refreshToken: String?
    public let expiresAt: Date

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date
    ) throws {
        guard
            !accessToken.isEmpty,
            accessToken.count <= 8_192,
            refreshToken?.count ?? 0 <= 8_192
        else {
            throw AccountIntegrationError.invalidCredential
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )
        try self.init(
            accessToken: container.decode(
                String.self,
                forKey: .accessToken
            ),
            refreshToken: container.decodeIfPresent(
                String.self,
                forKey: .refreshToken
            ),
            expiresAt: container.decode(
                Date.self,
                forKey: .expiresAt
            )
        )
    }
}

public struct KeychainAccountCredentialVault: Sendable {
    private let service: String
    private let account: String

    public init(
        service: String = Brand.bundleIdentifier + ".account-token",
        account: String = "control-plane"
    ) {
        self.service = String(service.prefix(256))
        self.account = String(account.prefix(256))
    }

    public func store(_ credential: AccountCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query = baseQuery
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(
            query as CFDictionary,
            attributes as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw AccountIntegrationError.keychain(updateStatus)
        }
        var add = query
        for (key, value) in attributes {
            add[key] = value
        }
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AccountIntegrationError.keychain(status)
        }
    }

    public func load() throws -> AccountCredential? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(
            query as CFDictionary,
            &item
        )
        if status == errSecItemNotFound {
            return nil
        }
        guard
            status == errSecSuccess,
            let data = item as? Data
        else {
            throw AccountIntegrationError.keychain(status)
        }
        return try JSONDecoder().decode(
            AccountCredential.self,
            from: data
        )
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard
            status == errSecSuccess || status == errSecItemNotFound
        else {
            throw AccountIntegrationError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public enum AccountRole: String, Codable, Sendable {
    case member
    case itAdministrator = "it_administrator"
}

public enum AccountAdminCapability:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case seats
    case billing
    case policies
    case aggregateUsage = "aggregate_usage"
    case complianceDocuments = "compliance_documents"
}

public struct AccountAuthorizationBoundary:
    Equatable,
    Sendable
{
    public let role: AccountRole

    public init(role: AccountRole) {
        self.role = role
    }

    public var adminCapabilities: Set<AccountAdminCapability> {
        role == .itAdministrator
            ? Set(AccountAdminCapability.allCases)
            : []
    }

    public var canAccessPrivateUserContent: Bool { false }
}

public struct EnforcedPrivacyPolicy:
    Equatable,
    Sendable
{
    public let syncPolicy: SyncPolicy
    public let diagnosticSharingAllowed: Bool

    public init(verifiedBAAEnforcement: Bool) {
        syncPolicy = SyncPolicy()
        diagnosticSharingAllowed = !verifiedBAAEnforcement
    }
}

public struct AccountSignOutPlan: Equatable, Sendable {
    public let revokeCredential: Bool
    public let deleteLocalDataRequested: Bool
    public let requiresSeparateLocalDataConfirmation: Bool

    public init(deleteLocalDataRequested: Bool) {
        revokeCredential = true
        self.deleteLocalDataRequested = deleteLocalDataRequested
        requiresSeparateLocalDataConfirmation =
            deleteLocalDataRequested
    }
}

private extension Array where Element == URLQueryItem {
    var singleValue: String? {
        count == 1 ? self[0].value : nil
    }
}
