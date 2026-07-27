import AppKit
import Carbon
import Foundation

@MainActor
final class HotKeyCheckDelegate: NSObject, NSApplicationDelegate {
    private let session = VoiceSession()
    private var monitor: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = HotKeyMonitor(session: session)
        let status = monitor?.start() ?? OSStatus(eventNotHandledErr)
        print("{\"available\":\(status == noErr),\"status\":\(status)}")
        fflush(stdout)
        monitor?.stop()
        NSApp.terminate(nil)
    }
}
