import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(session: VoiceSession) {
        let model = AppSettingsModel(session: session)
        let hostingController = NSHostingController(
            rootView: AppSettingsView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Autohand Voice Settings"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(NSSize(width: 760, height: 540))
        window.minSize = NSSize(width: 680, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AutohandVoiceSettings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.setFrameUsingName("AutohandVoiceSettings") {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
