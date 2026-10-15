import Foundation

/// Autohand service URLs. `AUTOHAND_VOICE_API_URL` and
/// `AUTOHAND_VOICE_INFERENCE_URL` may point at another https deployment.
public struct AutohandEndpoints: Equatable, Sendable {
    public static let production = AutohandEndpoints(environment: [:])

    public let api: URL
    public let inference: URL

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        api = Self.httpsURL(environment[Brand.environmentPrefix + "API_URL"])
            ?? URL(string: "https://api.autohand.ai/v1")!
        inference = Self.httpsURL(
            environment[Brand.environmentPrefix + "INFERENCE_URL"]
        ) ?? URL(string: "https://inference.autohand.ai/v1")!
    }

    public var chatCompletions: URL { inference.appending(path: "chat/completions") }
    public var deviceInitiate: URL { api.appending(path: "auth/cli/initiate") }
    public var devicePoll: URL { api.appending(path: "auth/cli/poll") }
    public var deviceCancel: URL { api.appending(path: "auth/cli/cancel") }
    public var accountProfile: URL { api.appending(path: "auth/me") }

    private static func httpsURL(_ string: String?) -> URL? {
        guard
            let string,
            let url = URL(string: string),
            url.scheme == "https",
            url.host != nil
        else { return nil }
        return url
    }
}

/// Body of `POST /v1/auth/cli/initiate`. `voice` is Autohand Voice's own
/// presentation identity; the API rejects unknown client types with 400.
public struct DeviceSignInRequest: Encodable, Sendable {
    public let clientId = "autohand-cli"
    public let clientType = "voice"
    public let schemaVersion = 2

    public init() {}
}

public struct DeviceSignInStart: Equatable, Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let interval: Int
    public let expiresIn: Int

    private struct Payload: Decodable {
        let deviceCode: String
        let userCode: String
        let verificationUri: String
        let verificationUriComplete: String?
        let expiresIn: Int
        let interval: Int
    }

    public static func decode(_ data: Data) throws -> Self {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard
            let url = URL(
                string: payload.verificationUriComplete ?? payload.verificationUri
            ),
            url.scheme == "https",
            !payload.deviceCode.isEmpty
        else {
            throw AccountIntegrationError.invalidConfiguration
        }
        return Self(
            deviceCode: payload.deviceCode,
            userCode: payload.userCode,
            verificationURL: url,
            interval: max(5, payload.interval),
            expiresIn: payload.expiresIn
        )
    }
}

public enum DeviceSignInPoll: Equatable, Sendable {
    case pending(interval: Int)
    case slowDown(retryAfter: Int)
    case authorized(token: String, email: String?)
    case expired
    case cancelled
    case failed

    private struct Payload: Decodable {
        struct User: Decodable {
            let email: String?
        }

        struct Failure: Decodable {
            let code: String?
        }

        let status: String?
        let interval: Int?
        let token: String?
        let user: User?
        let error: Failure?
    }

    public static func decode(
        status: Int,
        body: Data,
        retryAfter: String?
    ) -> Self {
        let payload = try? JSONDecoder().decode(Payload.self, from: body)
        if status == 429 || payload?.error?.code == "slow_down" {
            return .slowDown(retryAfter: retryAfter.flatMap(Int.init) ?? 10)
        }
        guard (200..<300).contains(status), let payload else { return .failed }
        switch payload.status {
        case "pending":
            return .pending(interval: max(5, payload.interval ?? 5))
        case "authorized":
            guard let token = payload.token, token.hasPrefix("ahc_") else {
                return .failed
            }
            return .authorized(token: token, email: payload.user?.email)
        case "expired":
            return .expired
        case "cancelled":
            return .cancelled
        default:
            return .failed
        }
    }
}
