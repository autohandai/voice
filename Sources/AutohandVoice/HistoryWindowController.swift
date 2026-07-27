import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController: NSWindowController {
    init(session: VoiceSession) {
        let model = HistoryModel(session: session)
        let hostingController = NSHostingController(
            rootView: HistoryView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Dictation History"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 560, height: 380)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AutohandVoiceHistory")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.setFrameUsingName("AutohandVoiceHistory") {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
