import XCTest
@testable import AutohandVoiceCore

final class TalkToolCallingTests: XCTestCase {
    private func json(_ value: some Encodable) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any]
        )
    }

    func testPlainMessagesEncodeAsBefore() throws {
        let object = try json(TalkMessage(role: .user, content: "Hi"))
        XCTAssertEqual(object["role"] as? String, "user")
        XCTAssertEqual(object["content"] as? String, "Hi")
        XCTAssertNil(object["tool_calls"])
        XCTAssertNil(object["tool_call_id"])
    }

    func testAssistantToolCallsAndToolResultsUseTheOpenAIShape() throws {
        let call = TalkToolCall(id: "call_1", name: "read_file", arguments: #"{"path":"a.txt"}"#)
        let assistant = try json(TalkMessage(role: .assistant, content: "", toolCalls: [call]))
        let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.first?["id"] as? String, "call_1")
        XCTAssertEqual(calls.first?["type"] as? String, "function")
        let function = try XCTUnwrap(calls.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "read_file")
        XCTAssertEqual(function["arguments"] as? String, #"{"path":"a.txt"}"#)

        let result = try json(TalkMessage(toolResult: "hello", for: "call_1"))
        XCTAssertEqual(result["role"] as? String, "tool")
        XCTAssertEqual(result["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(result["content"] as? String, "hello")
    }

    func testRequestsOnlyOfferToolsWhenThereAreSome() throws {
        let plain = try json(FantailChatRequest(messages: [], conversationID: UUID()))
        XCTAssertNil(plain["tools"])
        XCTAssertNil(plain["tool_choice"])

        let tool = TalkToolDefinition(
            name: "read_file",
            description: "Read a text file in the workspace.",
            parameters: .object([
                "type": .string("object"),
                "properties": .object(["path": .object(["type": .string("string")])]),
                "required": .array([.string("path")]),
            ])
        )
        let withTools = try json(
            FantailChatRequest(messages: [], conversationID: UUID(), tools: [tool])
        )
        let tools = try XCTUnwrap(withTools["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "read_file")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["required"] as? [String], ["path"])
        XCTAssertEqual(withTools["tool_choice"] as? String, "auto")
        XCTAssertGreaterThan(withTools["max_tokens"] as? Int ?? 0, FantailChatRequest.spokenMaxTokens)
    }

    func testStreamedToolCallFragmentsAreParsed() {
        let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"pa"}}]}}]}"#
        XCTAssertEqual(
            FantailStreamParser.parse(line: line),
            .toolCalls([ToolCallDelta(index: 0, id: "call_1", name: "read_file", arguments: #"{"pa"#)])
        )
        XCTAssertEqual(
            FantailStreamParser.parse(line: #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#),
            .finished("tool_calls")
        )
    }

    func testFragmentsJoinIntoCompleteCallsInOrder() {
        var accumulator = ToolCallAccumulator()
        accumulator.add([ToolCallDelta(index: 0, id: "call_1", name: "read_file", arguments: #"{"pa"#)])
        accumulator.add([ToolCallDelta(index: 1, id: "call_2", name: "list_files", arguments: "{}")])
        accumulator.add([ToolCallDelta(index: 0, id: nil, name: nil, arguments: #"th":"a.txt"}"#)])
        XCTAssertEqual(accumulator.calls, [
            TalkToolCall(id: "call_1", name: "read_file", arguments: #"{"path":"a.txt"}"#),
            TalkToolCall(id: "call_2", name: "list_files", arguments: "{}"),
        ])
    }

    func testArgumentsDecodeIntoStringFields() throws {
        let call = TalkToolCall(id: "1", name: "write_file", arguments: #"{"path":"a.md","contents":"hi"}"#)
        XCTAssertEqual(try call.stringArgument("path"), "a.md")
        XCTAssertEqual(try call.stringArgument("contents"), "hi")
        XCTAssertNil(try call.stringArgument("missing"))
        XCTAssertThrowsError(try TalkToolCall(id: "1", name: "x", arguments: "not json").stringArgument("path"))
    }
}
