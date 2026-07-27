import AppKit
import SwiftUI

@MainActor
final class FileTranscriptionWindowController: NSWindowController {
    private let model: FileTranscriptionModel

    init(session: VoiceSession) {
        let model = FileTranscriptionModel(session: session)
        self.model = model
        let hostingController = NSHostingController(
            rootView: FileTranscriptionView(model: model)
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Transcribe Audio File"
        window.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
        ]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 600, height: 440)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("AutohandVoiceFileTranscription")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func show() {
        guard let window else { return }
        if !window.setFrameUsingName("AutohandVoiceFileTranscription") {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func cancel() {
        model.cancel()
    }
}
