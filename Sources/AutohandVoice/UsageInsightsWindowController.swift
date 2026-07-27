import AppKit
import SwiftUI

@MainActor
final class UsageInsightsWindowController: NSWindowController {
    init(session: VoiceSession) {
        let model = UsageInsightsModel(session: session)
        let hostingController = NSHostingController(
            rootView: UsageInsightsView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Private Usage Insights"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(NSSize(width: 820, height: 620))
        window.minSize = NSSize(width: 680, height: 500)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AutohandVoiceUsageInsights")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.setFrameUsingName("AutohandVoiceUsageInsights") {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
