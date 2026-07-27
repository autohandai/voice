import AppKit
import ApplicationServices
import Foundation

enum DirectInsertionResult {
    case inserted
    case unsupported
    case noFocusedElement
}

@MainActor
protocol TextInsertionDriving: AnyObject {
    func hasAccessibilityPermission(prompt: Bool) -> Bool
    func insertSelectedText(_ text: String) -> DirectInsertionResult
    func pastePreservingClipboard(_ text: String) -> Bool
}

@MainActor
public struct TextInserter {
    private let driver: any TextInsertionDriving

    public init() {
        driver = SystemTextInsertionDriver()
    }

    init(driver: any TextInsertionDriving) {
        self.driver = driver
    }

    public func hasAccessibilityPermission(prompt: Bool = false) -> Bool {
        driver.hasAccessibilityPermission(prompt: prompt)
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

            switch driver.insertSelectedText(text) {
            case .inserted:
                return
            case .noFocusedElement:
                throw VoiceError.noFocusedTextField
            case .unsupported:
                guard driver.pastePreservingClipboard(text) else {
                    throw VoiceError.noFocusedTextField
                }
            }
        }
    }
}

@MainActor
private final class SystemTextInsertionDriver: TextInsertionDriving {
    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func insertSelectedText(_ text: String) -> DirectInsertionResult {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
        let focused
        else {
            return .noFocusedElement
        }

        let element = focused as! AXUIElement
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return status == .success ? .inserted : .unsupported
    }

    func pastePreservingClipboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return false
        }
        let temporaryChangeCount = pasteboard.changeCount

        guard
            let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 9,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 9,
                keyDown: false
            )
        else {
            snapshot.restore(to: pasteboard)
            return false
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
        return true
    }
}

private struct ClipboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            Dictionary(
                uniqueKeysWithValues: item.types.compactMap { type in
                    item.data(forType: type).map { (type, $0) }
                }
            )
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
