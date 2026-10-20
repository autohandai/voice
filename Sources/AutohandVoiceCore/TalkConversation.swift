import Foundation

public struct TalkMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public let role: Role
    public let content: String
    /// Tools the assistant asked to run (assistant messages only).
    public let toolCalls: [TalkToolCall]?
    /// The call a tool result answers (tool messages only).
    public let toolCallID: String?

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    public init(
        role: Role,
        content: String,
        toolCalls: [TalkToolCall]? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls?.isEmpty == true ? nil : toolCalls
        toolCallID = nil
    }

    /// The result of running one tool call.
    public init(toolResult: String, for callID: String) {
        role = .tool
        content = toolResult
        toolCalls = nil
        toolCallID = callID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        toolCalls = try container.decodeIfPresent([TalkToolCall].self, forKey: .toolCalls)
        toolCallID = try container.decodeIfPresent(String.self, forKey: .toolCallID)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(toolCallID, forKey: .toolCallID)
    }
}

/// One spoken conversation with Fantail. History stays in memory only and is
/// trimmed before every request: the free plan meters input tokens per
/// minute, so a voice turn must stay small.
public struct TalkConversation: Equatable, Sendable {
    public static let maximumMessages = 6
    public static let maximumCharacters = 2_400

    public let id: UUID
    public private(set) var messages: [TalkMessage] = []

    public init(id: UUID = UUID()) {
        self.id = id
    }

    public mutating func appendUser(_ text: String) {
        append(.user, text)
    }

    public mutating func appendAssistant(_ text: String) {
        append(.assistant, text)
    }

    /// Removes the latest question when it never received an answer, so a
    /// retry does not send it twice.
    public mutating func withdrawUnansweredQuestion() {
        guard messages.last?.role == .user else { return }
        messages.removeLast()
    }

    /// System prompt followed by the most recent turns that fit the budget.
    /// The newest message is always kept (truncated if it alone is too long)
    /// and the history never starts with an assistant turn.
    public func requestMessages(systemPrompt: String) -> [TalkMessage] {
        var kept: [TalkMessage] = []
        var characters = 0
        for message in messages.reversed() {
            guard kept.count < Self.maximumMessages else { break }
            let remaining = Self.maximumCharacters - characters
            if kept.isEmpty {
                let content = String(message.content.prefix(remaining))
                kept.append(TalkMessage(role: message.role, content: content))
                characters += content.count
                continue
            }
            guard message.content.count <= remaining else { break }
            kept.append(message)
            characters += message.content.count
        }
        kept.reverse()
        while kept.first?.role == .assistant {
            kept.removeFirst()
        }
        return [TalkMessage(role: .system, content: systemPrompt)] + kept
    }

    private mutating func append(_ role: TalkMessage.Role, _ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(TalkMessage(role: role, content: trimmed))
    }
}
