import AppKit
import AutohandVoiceCore
import SwiftUI

/// Shows and changes the folder Talk may read and write.
struct TalkWorkspacePicker: View {
    let session: VoiceSession

    private var workspace: URL { session.preferences.talkWorkspaceURL }

    var body: some View {
        LabeledContent("Workspace") {
            HStack(spacing: 8) {
                Text((workspace.path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(workspace.path)
                Button("Choose…") { choose() }
                if session.preferences.talkWorkspacePath != nil {
                    Button("Use Desktop") { session.setTalkWorkspace(nil) }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = workspace
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Choose the folder Talk can read and write.")
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            session.setTalkWorkspace(url)
        }
    }
}

/// Lets Talk operate apps through cua-driver, with its install and
/// permission status.
struct TalkComputerUseSection: View {
    let session: VoiceSession
    private let cua = CuaDriverClient()

    var body: some View {
        Section("Use This Mac") {
            Toggle(
                "Let Talk use apps on this Mac",
                isOn: Binding(
                    get: { session.preferences.talkComputerUseEnabled },
                    set: { session.setTalkComputerUse($0) }
                )
            )
            .disabled(!cua.isInstalled)
            if cua.isInstalled {
                Text("Talk can look at your apps and windows. Opening apps, clicking, typing and pressing keys always ask you first on the Talk card. Uses cua-driver, which needs its own Accessibility and Screen Recording permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Grant cua-driver Permissions…") { grantPermissions() }
            } else {
                Text("Install cua-driver to let Talk use apps on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("About cua-driver", destination: URL(string: "https://github.com/trycua/cua")!)
                    .font(.caption)
            }
        }
    }

    private func grantPermissions() {
        guard let executable = cua.executable else { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["permissions", "grant"]
        try? process.run()
    }
}
