import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    private let model: AppSettingsModel

    init(session: VoiceSession) {
        let model = AppSettingsModel(session: session)
        self.model = model
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
        window.setContentSize(NSSize(width: 860, height: 620))
        window.minSize = NSSize(width: 760, height: 560)
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
        model.refresh()
        if !window.setFrameUsingName("AutohandVoiceSettings") {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func restoreAfterLifecycleChange() {
        model.restoreAfterLifecycleChange()
    }
}
