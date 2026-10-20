import AppKit
import AutohandVoiceCore
import Foundation
import OSLog

/// Something a tool wants to do that changes the Mac; the person approves it
/// on the Talk card first.
struct ToolApprovalRequest: Equatable, Sendable {
    /// Groups requests for "Allow for this conversation".
    let kind: String
    let summary: String
}

/// The tools Talk offers Fantail: files in the workspace folder, and (when
/// switched on) operating apps through cua-driver. Reading is free;
/// anything that changes the Mac asks first.
@MainActor
final class TalkAgentToolbox {
    typealias Approver = (ToolApprovalRequest) async -> Bool

    private static let maximumResultCharacters = 8_000
    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "talk-tools"
    )

    var workspaceURL: () -> URL
    var computerUseEnabled: () -> Bool
    private let cua = CuaDriverClient()

    init(
        workspaceURL: @escaping () -> URL,
        computerUseEnabled: @escaping () -> Bool
    ) {
        self.workspaceURL = workspaceURL
        self.computerUseEnabled = computerUseEnabled
    }

    var definitions: [TalkToolDefinition] {
        Self.workspaceTools + (computerUseEnabled() && cua.isInstalled ? Self.computerTools : [])
    }

    /// Added to the system prompt so the model knows where it is working.
    var systemPromptAddendum: String {
        var lines = [
            "You can use tools. Files: list_files, read_file and write_file work only inside the user's workspace folder (\(workspaceURL().path)); paths are relative to it.",
            "Use a tool only when the user's request needs it, then answer briefly in plain spoken sentences.",
        ]
        if computerUseEnabled(), cua.isInstalled {
            lines.append("Computer: list_apps, list_windows and read_window look at apps; open_app, click, type_text and press_key operate them and the user approves each one. Read a window before acting on it and use element tokens from read_window.")
        }
        return lines.joined(separator: " ")
    }

    /// Short description shown on the card while a tool runs.
    func activity(for call: TalkToolCall) -> String {
        let path = (try? call.stringArgument("path")) ?? nil
        switch call.name {
        case "list_files": return "Looking in \(path?.isEmpty == false ? path! : "your workspace")…"
        case "read_file": return "Reading \(path ?? "a file")…"
        case "write_file": return "Writing \(path ?? "a file")…"
        case "list_apps", "list_windows": return "Looking at your open apps…"
        case "read_window": return "Reading a window…"
        case "open_app": return "Opening \(((try? call.stringArgument("name")) ?? nil) ?? "an app")…"
        case "click": return "Clicking…"
        case "type_text": return "Typing…"
        case "press_key": return "Pressing a key…"
        default: return "Working…"
        }
    }

    /// Runs one call and returns the text handed back to the model.
    func run(_ call: TalkToolCall, approve: Approver) async -> String {
        do {
            let result = try await perform(call, approve: approve)
            return String(result.prefix(Self.maximumResultCharacters))
        } catch let error as ToolError {
            return "Error: \(error.message)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    struct ToolError: Error {
        let message: String
    }

    private func perform(_ call: TalkToolCall, approve: Approver) async throws -> String {
        let sandbox = WorkspaceSandbox(root: workspaceURL())
        func string(_ key: String) throws -> String? {
            do { return try call.stringArgument(key) } catch {
                throw ToolError(message: "the arguments were not valid JSON")
            }
        }
        func required(_ key: String) throws -> String {
            guard let value = try string(key), !value.isEmpty else {
                throw ToolError(message: "missing \(key)")
            }
            return value
        }

        switch call.name {
        case "list_files":
            let entries = try sandbox.list(try string("path") ?? "")
            if entries.isEmpty { return "The folder is empty." }
            return entries.map { $0.isDirectory ? "\($0.name)/" : "\($0.name) (\($0.size) bytes)" }
                .joined(separator: "\n")

        case "read_file":
            return try sandbox.read(try required("path"))

        case "write_file":
            let path = try required("path")
            let contents = try string("contents") ?? ""
            if sandbox.exists(path) {
                guard await approve(ToolApprovalRequest(
                    kind: "overwrite",
                    summary: "Replace \(path) in your workspace?"
                )) else { return "The user declined to replace \(path)." }
            }
            try sandbox.write(path, contents: contents)
            return "Saved \(path) (\(contents.utf8.count) bytes)."

        case "list_apps", "list_windows", "read_window", "open_app", "click", "type_text", "press_key":
            guard computerUseEnabled() else {
                throw ToolError(message: "using this Mac is switched off in Settings")
            }
            return try await runComputerTool(call, approve: approve)

        default:
            throw ToolError(message: "unknown tool \(call.name)")
        }
    }

    private func runComputerTool(_ call: TalkToolCall, approve: Approver) async throws -> String {
        guard let object = try? JSONSerialization.jsonObject(
            with: Data((call.arguments.isEmpty ? "{}" : call.arguments).utf8)
        ) as? [String: Any] else {
            throw ToolError(message: "the arguments were not valid JSON")
        }
        let tool: String
        var arguments: [String: Any] = [:]
        var approval: ToolApprovalRequest?
        func copy(_ keys: [String]) {
            for key in keys { if let value = object[key] { arguments[key] = value } }
        }
        switch call.name {
        case "list_apps":
            tool = "list_apps"
        case "list_windows":
            tool = "list_windows"
            arguments["on_screen_only"] = true
            copy(["pid"])
        case "read_window":
            tool = "get_window_state"
            copy(["pid", "window_id", "query"])
            arguments["include_screenshot"] = false
            arguments["max_elements"] = 300
        case "open_app":
            tool = "launch_app"
            copy(["name", "bundle_id"])
            let name = (object["name"] ?? object["bundle_id"]).map { "\($0)" } ?? "an app"
            approval = ToolApprovalRequest(kind: "open_app", summary: "Open \(name)?")
        case "click":
            tool = "click"
            copy(["pid", "window_id", "element_token", "x", "y"])
            approval = ToolApprovalRequest(kind: "click", summary: "Click in \(appName(object))?")
        case "type_text":
            tool = "type_text"
            copy(["pid", "window_id", "element_token", "text"])
            let text = (object["text"] as? String).map { String($0.prefix(60)) } ?? ""
            approval = ToolApprovalRequest(kind: "type", summary: "Type “\(text)” in \(appName(object))?")
        case "press_key":
            tool = "press_key"
            copy(["pid", "window_id", "key", "modifiers"])
            let key = object["key"].map { "\($0)" } ?? "a key"
            approval = ToolApprovalRequest(kind: "key", summary: "Press \(key) in \(appName(object))?")
        default:
            throw ToolError(message: "unknown tool \(call.name)")
        }
        if let approval {
            guard await approve(approval) else {
                return "The user declined: \(approval.summary)"
            }
        }
        return try await cua.call(tool, arguments: arguments)
    }

    private func appName(_ object: [String: Any]) -> String {
        if let pid = object["pid"] as? Int,
           let app = NSRunningApplication(processIdentifier: pid_t(pid))?
               .localizedName {
            return app
        }
        return "the app"
    }

    // MARK: - Definitions

    private static func schema(
        _ properties: [String: JSONValue],
        required: [String] = []
    ) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
        ])
    }

    private static let workspaceTools = [
        TalkToolDefinition(
            name: "list_files",
            description: "List files and folders in the workspace. path is relative; empty for the top.",
            parameters: schema(["path": .object(["type": .string("string")])])
        ),
        TalkToolDefinition(
            name: "read_file",
            description: "Read a text file in the workspace.",
            parameters: schema(["path": .object(["type": .string("string")])], required: ["path"])
        ),
        TalkToolDefinition(
            name: "write_file",
            description: "Create or replace a text file in the workspace. Replacing asks the user first.",
            parameters: schema([
                "path": .object(["type": .string("string")]),
                "contents": .object(["type": .string("string")]),
            ], required: ["path", "contents"])
        ),
    ]

    private static let computerTools = [
        TalkToolDefinition(
            name: "list_apps",
            description: "List apps on this Mac with their pid and whether they are running.",
            parameters: schema([:])
        ),
        TalkToolDefinition(
            name: "list_windows",
            description: "List visible windows (window_id, pid, title).",
            parameters: schema(["pid": .object(["type": .string("integer")])])
        ),
        TalkToolDefinition(
            name: "read_window",
            description: "Read a window's controls and text. Returns elements with element_token values for click and type_text. query filters lines.",
            parameters: schema([
                "pid": .object(["type": .string("integer")]),
                "window_id": .object(["type": .string("integer")]),
                "query": .object(["type": .string("string")]),
            ], required: ["pid", "window_id"])
        ),
        TalkToolDefinition(
            name: "open_app",
            description: "Open an app by name or bundle_id. Asks the user first.",
            parameters: schema([
                "name": .object(["type": .string("string")]),
                "bundle_id": .object(["type": .string("string")]),
            ])
        ),
        TalkToolDefinition(
            name: "click",
            description: "Click an element (element_token from read_window). Asks the user first.",
            parameters: schema([
                "pid": .object(["type": .string("integer")]),
                "window_id": .object(["type": .string("integer")]),
                "element_token": .object(["type": .string("string")]),
            ], required: ["pid", "window_id", "element_token"])
        ),
        TalkToolDefinition(
            name: "type_text",
            description: "Type text into an app, optionally into an element_token. Asks the user first.",
            parameters: schema([
                "pid": .object(["type": .string("integer")]),
                "window_id": .object(["type": .string("integer")]),
                "element_token": .object(["type": .string("string")]),
                "text": .object(["type": .string("string")]),
            ], required: ["pid", "text"])
        ),
        TalkToolDefinition(
            name: "press_key",
            description: "Press a key such as return, tab or escape, with optional modifiers (cmd, shift, option, ctrl). Asks the user first.",
            parameters: schema([
                "pid": .object(["type": .string("integer")]),
                "window_id": .object(["type": .string("integer")]),
                "key": .object(["type": .string("string")]),
                "modifiers": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
            ], required: ["pid", "key"])
        ),
    ]
}

