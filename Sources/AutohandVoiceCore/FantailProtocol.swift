import Foundation

/// OpenAI-compatible Chat Completions body for Autohand's `fantail` model.
public struct FantailChatRequest: Encodable, Equatable, Sendable {
    /// The API reserves `max_tokens` against the per-minute output budget up
    /// front (default 16,000), so spoken replies always ask for a small cap.
    public static let spokenMaxTokens = 320

    public static let spokenSystemPrompt = """
        You are Autohand Voice, a helpful assistant the user talks to out \
        loud. Your reply is read aloud, so answer in plain spoken sentences \
        with no markdown, lists, tables, code or emoji. Keep it short: one to \
        three sentences unless the user asks for more.
        """

    public let model = "fantail"
    public let messages: [TalkMessage]
    public let stream = true
    public let maxTokens: Int
    public let temperature: Double
    public let promptCacheKey: String

    private enum CodingKeys: String, CodingKey {
        case model
        case messages
        case stream
        case maxTokens = "max_tokens"
        case temperature
        case promptCacheKey = "prompt_cache_key"
    }

    public init(
        messages: [TalkMessage],
        conversationID: UUID,
        maxTokens: Int = spokenMaxTokens,
        temperature: Double = 0.4
    ) {
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        promptCacheKey = conversationID.uuidString
    }
}

public enum FantailStreamEvent: Equatable, Sendable {
    case content(String)
    case finished(String)
    case done
    case ignored
}

/// Parses one line of the server-sent event stream.
public enum FantailStreamParser {
    private struct Chunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }

            let delta: Delta?
            let finishReason: String?

            private enum CodingKeys: String, CodingKey {
                case delta
                case finishReason = "finish_reason"
            }
        }

        let choices: [Choice]?
    }

    public static func parse(line: String) -> FantailStreamEvent {
        guard line.hasPrefix("data:") else { return .ignored }
        let payload = line.dropFirst("data:".count)
            .trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard
            let chunk = try? JSONDecoder().decode(
                Chunk.self,
                from: Data(payload.utf8)
            ),
            let choice = chunk.choices?.first
        else { return .ignored }
        if let content = choice.delta?.content, !content.isEmpty {
            return .content(content)
        }
        if let reason = choice.finishReason {
            return .finished(reason)
        }
        return .ignored
    }
}

/// A Talk request failure, mapped from the Autohand API error envelope to
/// what the user can do about it.
public enum TalkFailure: Error, Equatable, Sendable {
    case signInRequired
    case verifyEmail
    case quotaReached(resetAt: Date?, upgradeURL: URL?)
    case slowDown(retryAfter: TimeInterval?, upgradeURL: URL?)
    case busy(retryAfter: TimeInterval?)
    case blocked(message: String)
    case unavailable
    case connectionLost

    public var message: String {
        switch self {
        case .signInRequired:
            "Sign in with Autohand to talk with Fantail."
        case .verifyEmail:
            "Verify your Autohand email to use Talk."
        case let .quotaReached(resetAt, _):
            if let resetAt {
                "You've used your free Talk turns until "
                    + resetAt.formatted(date: .omitted, time: .shortened)
                    + "."
            } else {
                "You've used your free Talk turns."
            }
        case .slowDown:
            "Fantail needs a few seconds before the next turn."
        case .busy:
            "Fantail is busy. Try again in a moment."
        case let .blocked(message):
            message
        case .unavailable:
            "Fantail is unavailable right now."
        case .connectionLost:
            "The connection to Fantail was lost."
        }
    }

    /// Whether trying the same question again can succeed soon.
    public var isRetryable: Bool {
        switch self {
        case .slowDown, .busy, .unavailable, .connectionLost:
            true
        case .signInRequired, .verifyEmail, .quotaReached, .blocked:
            false
        }
    }

    public var upgradeURL: URL? {
        switch self {
        case let .quotaReached(_, url), let .slowDown(_, url):
            url
        default:
            nil
        }
    }
}

public enum AutohandAPIError {
    private struct Envelope: Decodable {
        struct Body: Decodable {
            let type: String?
            let message: String?
            let scope: String?
            let resetAt: Double?
            let upgradeUrl: String?
        }

        let error: Body
    }

    public static func failure(
        status: Int,
        body: Data,
        retryAfter: String?
    ) -> TalkFailure {
        let error = (try? JSONDecoder().decode(Envelope.self, from: body))?.error
        let retry = retryAfter.flatMap(TimeInterval.init)
        let upgrade = error.map { AutohandUpgradeLink.resolve($0.upgradeUrl) }
            ?? nil
        switch (status, error?.type, error?.scope) {
        case (401, _, _), (_, "unauthorized", _), (_, "invalid_credential", _),
             (_, "session_expired", _):
            return .signInRequired
        case (_, "eligibility_required", _):
            return .verifyEmail
        case (_, "content_blocked", _):
            return .blocked(
                message: error?.message
                    ?? "Autohand's safety check blocked this message."
            )
        case (_, "model_not_available", _),
             (_, _, "window_5h"), (_, _, "window_month"):
            return .quotaReached(
                resetAt: error?.resetAt.map(Date.init(timeIntervalSince1970:)),
                upgradeURL: upgrade
            )
        case (_, _, "input_tpm"), (_, _, "output_tpm"):
            return .slowDown(retryAfter: retry, upgradeURL: upgrade)
        case (429, _, _):
            return .busy(retryAfter: retry)
        default:
            return .unavailable
        }
    }
}

/// Only console.autohand.ai over https may be opened from an API response.
public enum AutohandUpgradeLink {
    public static let fallback = URL(string: "https://console.autohand.ai/upgrade/")

    public static func trusted(_ string: String?) -> URL? {
        guard
            let string,
            let url = URL(string: string),
            url.scheme == "https",
            url.host == "console.autohand.ai"
        else { return nil }
        return url
    }

    static func resolve(_ string: String?) -> URL? {
        trusted(string) ?? fallback
    }
}

/// Remaining Talk turns reported by the quota response headers.
public struct TalkQuota: Equatable, Sendable {
    public let remainingInWindow: Int?
    public let remainingThisMonth: Int?

    public init(remainingInWindow: Int?, remainingThisMonth: Int?) {
        self.remainingInWindow = remainingInWindow
        self.remainingThisMonth = remainingThisMonth
    }

    public init?(headers: [String: String]) {
        let lowered = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        let window = lowered["x-autohand-remaining-5h"].flatMap(Int.init)
        let month = lowered["x-autohand-remaining-month"].flatMap(Int.init)
        guard window != nil || month != nil else { return nil }
        self.init(remainingInWindow: window, remainingThisMonth: month)
    }

    /// The smaller of the two counters, when either is reported.
    public var remaining: Int? {
        [remainingInWindow, remainingThisMonth].compactMap { $0 }.min()
    }
}
