import Foundation

/// One tool call the model asked for.
public struct TalkToolCall: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// JSON object text, as the model produced it.
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    private enum CodingKeys: String, CodingKey { case id, type, function }
    private struct Function: Codable { let name: String; let arguments: String }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let function = try container.decode(Function.self, forKey: .function)
        name = function.name
        arguments = function.arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("function", forKey: .type)
        try container.encode(Function(name: name, arguments: arguments), forKey: .function)
    }

    public enum ArgumentError: Error, Equatable { case invalidJSON }

    /// A string argument, or nil when absent. Throws if the arguments are
    /// not a JSON object.
    public func stringArgument(_ key: String) throws -> String? {
        guard let object = try? JSONSerialization.jsonObject(
            with: Data(arguments.isEmpty ? "{}".utf8 : arguments.utf8)
        ) as? [String: Any] else { throw ArgumentError.invalidJSON }
        switch object[key] {
        case let value as String: return value
        case let value as NSNumber: return value.stringValue
        default: return nil
        }
    }
}

/// A streamed fragment of a tool call.
public struct ToolCallDelta: Equatable, Sendable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let arguments: String?

    public init(index: Int, id: String?, name: String?, arguments: String?) {
        self.index = index
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

/// Joins streamed fragments into complete calls, in index order.
public struct ToolCallAccumulator: Equatable, Sendable {
    private var parts: [Int: (id: String, name: String, arguments: String)] = [:]

    public init() {}

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.calls == rhs.calls }

    public mutating func add(_ deltas: [ToolCallDelta]) {
        for delta in deltas {
            var part = parts[delta.index] ?? (id: "", name: "", arguments: "")
            if let id = delta.id, !id.isEmpty { part.id = id }
            if let name = delta.name, !name.isEmpty { part.name += part.name.isEmpty ? name : "" }
            if let arguments = delta.arguments { part.arguments += arguments }
            parts[delta.index] = part
        }
    }

    public var isEmpty: Bool { parts.isEmpty }

    public var calls: [TalkToolCall] {
        parts.keys.sorted().compactMap { index in
            guard let part = parts[index], !part.name.isEmpty else { return nil }
            return TalkToolCall(
                id: part.id.isEmpty ? "call_\(index)" : part.id,
                name: part.name,
                arguments: part.arguments
            )
        }
    }
}

/// A tool offered to the model.
public struct TalkToolDefinition: Encodable, Equatable, Sendable {
    public let name: String
    public let description: String
    public let parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    private enum CodingKeys: String, CodingKey { case type, function }
    private enum FunctionKeys: String, CodingKey { case name, description, parameters }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("function", forKey: .type)
        var function = container.nestedContainer(keyedBy: FunctionKeys.self, forKey: .function)
        try function.encode(name, forKey: .name)
        try function.encode(description, forKey: .description)
        try function.encode(parameters, forKey: .parameters)
    }
}

/// A JSON value, for tool parameter schemas.
public indirect enum JSONValue: Encodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}
