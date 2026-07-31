import AppKit
import AutohandVoiceCore
import SwiftUI

@MainActor
final class ScratchpadWindowController: NSWindowController {
    let model: ScratchpadModel

    init(
        workspace: LocalWorkspace,
        startQuickDictation: @escaping () -> Void
    ) {
        model = ScratchpadModel(workspace: workspace)
        let root = ScratchpadView(
            model: model,
            startQuickDictation: startQuickDictation
        )
        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 620),
            styleMask: [
                .titled,
                .closable,
                .resizable,
                .miniaturizable,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )
        panel.title = "Autohand Voice Scratchpad"
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.moveToActiveSpace]
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        window.center()
        window.orderFrontRegardless()
    }

    func prepareForLocalDataReset() async {
        window?.orderOut(nil)
        await model.prepareForLocalDataReset()
    }
}
