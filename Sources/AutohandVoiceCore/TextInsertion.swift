import AppKit
import ApplicationServices
import Foundation

enum DirectInsertionResult {
    case inserted
    case unsupported
    case noFocusedElement
    case focusMoved
}

enum PasteInsertionResult {
    case inserted
    case focusMoved
    case failed
}

@MainActor
public final class TextInsertionTarget {
    let storage: AnyObject

    init(storage: AnyObject) {
        self.storage = storage
    }
}

@MainActor
protocol TextInsertionDriving: AnyObject {
    func hasAccessibilityPermission(prompt: Bool) -> Bool
    func captureTarget() -> TextInsertionTarget?
    func insertSelectedText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult
    func pastePreservingClipboard(
        _ text: String,
        target: TextInsertionTarget
    ) -> PasteInsertionResult
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

    public func captureTarget() -> TextInsertionTarget? {
        driver.captureTarget()
    }

    public func commit(
        _ transcript: Transcript,
        mode: OutputMode,
        target: TextInsertionTarget? = nil
    ) throws {
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

            guard let target else {
                throw VoiceError.noFocusedTextField
            }
            switch driver.insertSelectedText(text, target: target) {
            case .inserted:
                return
            case .noFocusedElement:
                throw VoiceError.noFocusedTextField
            case .focusMoved:
                throw VoiceError.insertionTargetChanged
            case .unsupported:
                switch driver.pastePreservingClipboard(text, target: target) {
                case .inserted:
                    return
                case .focusMoved:
                    throw VoiceError.insertionTargetChanged
                case .failed:
                    throw VoiceError.textInsertionFailed
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

    func captureTarget() -> TextInsertionTarget? {
        guard let element = focusedElement() else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else {
            return nil
        }
        let selectedRange = attribute(
            element,
            name: kAXSelectedTextRangeAttribute
        )
        return TextInsertionTarget(
            storage: SystemInsertionTarget(
                element: element,
                processID: processID,
                selectedRange: selectedRange
            )
        )
    }

    func insertSelectedText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        guard let systemTarget = target.storage as? SystemInsertionTarget else {
            return .noFocusedElement
        }
        guard targetIsStillFocused(systemTarget) else {
            return .focusMoved
        }
        let status = AXUIElementSetAttributeValue(
            systemTarget.element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        return status == .success ? .inserted : .unsupported
    }

    func pastePreservingClipboard(
        _ text: String,
        target: TextInsertionTarget
    ) -> PasteInsertionResult {
        guard
            let systemTarget = target.storage as? SystemInsertionTarget,
            targetIsStillFocused(systemTarget)
        else {
            return .focusMoved
        }
        let pasteboard = NSPasteboard.general
        let snapshot = ClipboardSnapshot(pasteboard: pasteboard)
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            snapshot.restore(to: pasteboard)
            return .failed
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
            return .failed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
        return .inserted
    }

    private func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        ) == .success,
        let focused
        else {
            return nil
        }
        return (focused as! AXUIElement)
    }

    private func targetIsStillFocused(
        _ target: SystemInsertionTarget
    ) -> Bool {
        guard let current = focusedElement() else { return false }
        var processID: pid_t = 0
        guard
            AXUIElementGetPid(current, &processID) == .success,
            processID == target.processID,
            CFEqual(current, target.element)
        else {
            return false
        }
        return equal(
            target.selectedRange,
            attribute(current, name: kAXSelectedTextRangeAttribute)
        )
    }

    private func attribute(
        _ element: AXUIElement,
        name: String
    ) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            name as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value
    }

    private func equal(_ lhs: CFTypeRef?, _ rhs: CFTypeRef?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            CFEqual(lhs, rhs)
        default:
            false
        }
    }
}

@MainActor
private final class SystemInsertionTarget {
    let element: AXUIElement
    let processID: pid_t
    let selectedRange: CFTypeRef?

    init(
        element: AXUIElement,
        processID: pid_t,
        selectedRange: CFTypeRef?
    ) {
        self.element = element
        self.processID = processID
        self.selectedRange = selectedRange
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
