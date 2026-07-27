import AppKit
import ApplicationServices
import Foundation

@MainActor
public struct TextInserter {
    public init() {}

    public func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func commit(_ transcript: Transcript, mode: OutputMode) throws {
        let text = try transcript.finalText()
        switch mode {
        case .clipboard:
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else {
                throw VoiceError.noFocusedTextField
            }
        case .type:
            guard hasAccessibilityPermission(prompt: true) else {
                throw VoiceError.accessibilityPermissionDenied
            }
            let system = AXUIElementCreateSystemWide()
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                system,
                kAXFocusedUIElementAttribute as CFString,
                &focused
            ) == .success,
            let focused
            else {
                throw VoiceError.noFocusedTextField
            }
            let element = focused as! AXUIElement
            guard AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFString
            ) == .success else {
                throw VoiceError.noFocusedTextField
            }
        }
    }
}
