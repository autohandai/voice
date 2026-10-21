import AppKit
import Foundation

/// Runs cua-driver (https://github.com/trycua/cua) tool calls for Talk's
/// computer use. cua-driver holds its own Accessibility and Screen Recording
/// permissions; Autohand Voice only invokes its command-line interface.
struct CuaDriverClient: Sendable {
    private static let maximumOutputBytes = 256 * 1_024
    private static let timeout: TimeInterval = 60
    private static let driverBundleIdentifier = "com.trycua.driver"
    private static let searchPaths = [
        "~/.local/bin/cua-driver",
        "/opt/homebrew/bin/cua-driver",
        "/usr/local/bin/cua-driver",
    ]

    var executable: URL? {
        Self.searchPaths
            .map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    var isInstalled: Bool { executable != nil }

    /// Calls one cua-driver tool and returns its output text. Starts the
    /// cua-driver service when it isn't running yet.
    func call(_ tool: String, arguments: [String: Any]) async throws -> String {
        guard let executable else {
            throw TalkAgentToolbox.ToolError(
                message: "cua-driver isn't installed, so Talk can't use this Mac"
            )
        }
        let json = String(
            decoding: try JSONSerialization.data(withJSONObject: arguments),
            as: UTF8.self
        )
        var result = try await Self.run(executable, ["call", tool, json])
        if result.output.contains("daemon is not running") {
            try await Self.startService(executable)
            result = try await Self.run(executable, ["call", tool, json])
        } else if result.output.hasPrefix("permissions_pending") {
            // A daemon started from a shell runs under that shell's
            // permissions, not CuaDriver's; restart it as CuaDriver once.
            _ = try? await Self.run(executable, ["stop"])
            try await Self.startService(executable)
            result = try await Self.run(executable, ["call", tool, json])
        }
        if result.output.hasPrefix("permissions_pending") {
            throw TalkAgentToolbox.ToolError(
                message: "cua-driver still needs Accessibility and Screen Recording permission. The user can grant it with: cua-driver permissions grant"
            )
        }
        guard result.status == 0 else {
            throw TalkAgentToolbox.ToolError(
                message: result.output.isEmpty ? "cua-driver failed (\(result.status))" : result.output
            )
        }
        return result.output
    }

    /// Starts the service through LaunchServices so it runs as CuaDriver.app
    /// and holds that app's permissions; a bare `serve` child would inherit
    /// Autohand Voice's instead. Falls back to the CLI without the app.
    private static func startService(_ executable: URL) async throws {
        let process = Process()
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: driverBundleIdentifier) != nil {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-n", "-g", "-b", driverBundleIdentifier, "--args", "serve"]
        } else {
            process.executableURL = executable
            process.arguments = ["serve"]
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            if let status = try? await run(executable, ["status"]),
               status.output.contains("daemon is running") {
                return
            }
        }
    }

    private static func run(
        _ executable: URL,
        _ arguments: [String]
    ) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                let deadline = DispatchTime.now() + timeout
                DispatchQueue.global().asyncAfter(deadline: deadline) {
                    if process.isRunning { process.terminate() }
                }
                var data = Data()
                let handle = pipe.fileHandleForReading
                while true {
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    if data.count < maximumOutputBytes { data.append(chunk) }
                }
                process.waitUntilExit()
                let text = String(decoding: data.prefix(maximumOutputBytes), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (process.terminationStatus, text))
            }
        }
    }
}
