import AppKit
import AutohandVoiceCore
import Foundation

@MainActor
final class HotKeyMonitor {
    private var monitor: Any?
    private var keyIsDown = false
    private let session: VoiceSession

    init(session: VoiceSession) {
        self.session = session
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        keyIsDown = false
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == session.preferences.pushToTalkKey.keyCode else {
            return
        }
        let isDown: Bool
        switch session.preferences.pushToTalkKey {
        case .rightOption:
            isDown = event.modifierFlags.contains(.option)
        case .rightControl:
            isDown = event.modifierFlags.contains(.control)
        }
        guard isDown != keyIsDown else { return }
        keyIsDown = isDown
        if isDown {
            session.beginRecording()
        } else {
            session.finishRecording()
        }
    }
}
