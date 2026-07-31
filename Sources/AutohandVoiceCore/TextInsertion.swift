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
    public let context: TextInsertionContext

    init(
        storage: AnyObject,
        context: TextInsertionContext = .unknown
    ) {
        self.storage = storage
        self.context = context
    }
}

@MainActor
protocol TextInsertionDriving: AnyObject {
    func hasAccessibilityPermission(prompt: Bool) -> Bool
    func captureTarget(contextScalarLimit: Int) -> TextInsertionTarget?
    func insertSelectedText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult
    func pastePreservingClipboard(
        _ text: String,
        target: TextInsertionTarget
    ) -> PasteInsertionResult
    func insertUnicodeText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult
    func sendEnter(
        target: TextInsertionTarget
    ) -> DirectInsertionResult
}

extension TextInsertionDriving {
    func insertUnicodeText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        .unsupported
    }

    func sendEnter(
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        .unsupported
    }
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

    public func captureTarget(
        contextScalarLimit: Int = 0
    ) -> TextInsertionTarget? {
        driver.captureTarget(
            contextScalarLimit: min(
                max(contextScalarLimit, 0),
                SensitiveContextPolicy.maximumScalars
            )
        )
    }

    public func commit(
        _ transcript: Transcript,
        mode: OutputMode,
        target: TextInsertionTarget? = nil
    ) throws {
        try commitVerifiedFinalText(
            transcript.finalText(),
            mode: mode,
            target: target
        )
    }

    public func commitVerifiedFinalText(
        _ text: String,
        mode: OutputMode,
        target: TextInsertionTarget? = nil
    ) throws {
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.emptyTranscript
        }
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
            if target.context.targetDescriptor.isSecureField {
                throw VoiceError.sensitiveTarget(.secureField)
            }
            let plan = TextInsertionPlanSelector.plan(for: target.context)
            for strategy in plan.strategies {
                switch strategy {
                case .clipboardPreservingPaste:
                    switch driver.pastePreservingClipboard(
                        text,
                        target: target
                    ) {
                    case .inserted:
                        return
                    case .focusMoved:
                        throw VoiceError.insertionTargetChanged
                    case .failed:
                        continue
                    }
                case .accessibilitySelectedText:
                    switch driver.insertSelectedText(text, target: target) {
                    case .inserted:
                        return
                    case .noFocusedElement:
                        throw VoiceError.noFocusedTextField
                    case .focusMoved:
                        throw VoiceError.insertionTargetChanged
                    case .unsupported:
                        continue
                    }
                case .unicodeEvents:
                    switch driver.insertUnicodeText(text, target: target) {
                    case .inserted:
                        return
                    case .noFocusedElement:
                        throw VoiceError.noFocusedTextField
                    case .focusMoved:
                        throw VoiceError.insertionTargetChanged
                    case .unsupported:
                        continue
                    }
                }
            }
            throw VoiceError.textInsertionFailed
        }
    }

    public func commitExplicitEnter(
        target: TextInsertionTarget
    ) throws {
        guard !target.context.targetDescriptor.isSecureField else {
            throw VoiceError.sensitiveTarget(.secureField)
        }
        switch driver.sendEnter(target: target) {
        case .inserted:
            return
        case .focusMoved:
            throw VoiceError.insertionTargetChanged
        case .noFocusedElement:
            throw VoiceError.noFocusedTextField
        case .unsupported:
            throw VoiceError.textInsertionFailed
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

    func captureTarget(contextScalarLimit: Int) -> TextInsertionTarget? {
        guard let element = focusedElement() else { return nil }
        var processID: pid_t = 0
        guard AXUIElementGetPid(element, &processID) == .success else {
            return nil
        }
        let selectedRange = attribute(
            element,
            name: kAXSelectedTextRangeAttribute
        )
        let role = attribute(element, name: kAXRoleAttribute) as? String
        let subrole = attribute(element, name: kAXSubroleAttribute) as? String
        let isProtectedContent = (
            attribute(element, name: "AXProtectedContent") as? NSNumber
        )?.boolValue ?? false
        return TextInsertionTarget(
            storage: SystemInsertionTarget(
                element: element,
                processID: processID,
                selectedRange: selectedRange
            ),
            context: insertionContext(
                element: element,
                processID: processID,
                selectedRange: selectedRange,
                role: role,
                subrole: subrole,
                contextScalarLimit: contextScalarLimit,
                isProtectedContent: isProtectedContent
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

        guard targetIsStillFocused(systemTarget) else {
            snapshot.restore(to: pasteboard)
            return .focusMoved
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            guard pasteboard.changeCount == temporaryChangeCount else { return }
            snapshot.restore(to: pasteboard)
        }
        return .inserted
    }

    func insertUnicodeText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        guard let systemTarget = target.storage as? SystemInsertionTarget else {
            return .noFocusedElement
        }
        let utf16 = Array(text.utf16)
        let maximumUnitsPerEvent = 16
        var offset = 0
        while offset < utf16.count {
            let targetRemainsValid = offset == 0
                ? targetIsStillFocused(systemTarget)
                : targetIsSameElement(systemTarget)
            guard targetRemainsValid else {
                return .focusMoved
            }
            let end = min(offset + maximumUnitsPerEvent, utf16.count)
            let chunk = Array(utf16[offset ..< end])
            guard
                let keyDown = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 0,
                    keyDown: true
                ),
                let keyUp = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 0,
                    keyDown: false
                )
            else {
                return .unsupported
            }
            chunk.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return }
                keyDown.keyboardSetUnicodeString(
                    stringLength: buffer.count,
                    unicodeString: baseAddress
                )
            }
            guard targetIsSameElement(systemTarget) else {
                return .focusMoved
            }
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
            offset = end
        }
        return .inserted
    }

    func sendEnter(
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        guard let systemTarget = target.storage as? SystemInsertionTarget else {
            return .noFocusedElement
        }
        guard targetIsSameElement(systemTarget) else {
            return .focusMoved
        }
        guard
            let keyDown = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 36,
                keyDown: true
            ),
            let keyUp = CGEvent(
                keyboardEventSource: nil,
                virtualKey: 36,
                keyDown: false
            )
        else {
            return .unsupported
        }
        guard targetIsSameElement(systemTarget) else {
            return .focusMoved
        }
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
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
        guard
            let current = focusedElement(),
            currentMatches(current, target: target)
        else { return false }
        return equal(
            target.selectedRange,
            attribute(current, name: kAXSelectedTextRangeAttribute)
        )
    }

    private func targetIsSameElement(
        _ target: SystemInsertionTarget
    ) -> Bool {
        guard let current = focusedElement() else { return false }
        return currentMatches(current, target: target)
    }

    private func currentMatches(
        _ current: AXUIElement,
        target: SystemInsertionTarget
    ) -> Bool {
        var processID: pid_t = 0
        return AXUIElementGetPid(current, &processID) == .success
            && processID == target.processID
            && CFEqual(current, target.element)
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

    private func insertionContext(
        element: AXUIElement,
        processID: pid_t,
        selectedRange: CFTypeRef?,
        role: String?,
        subrole: String?,
        contextScalarLimit: Int,
        isProtectedContent: Bool
    ) -> TextInsertionContext {
        guard
            let selectedRange,
            CFGetTypeID(selectedRange) == AXValueGetTypeID(),
            AXValueGetType(selectedRange as! AXValue) == .cfRange
        else {
            return .init(
                appBundleIdentifier: NSRunningApplication(
                    processIdentifier: processID
                )?.bundleIdentifier,
                accessibilityRole: role,
                accessibilitySubrole: subrole,
                isProtectedContent: isProtectedContent
            )
        }
        var range = CFRange()
        guard AXValueGetValue(
            selectedRange as! AXValue,
            .cfRange,
            &range
        ) else {
            return .unknown
        }
        guard contextScalarLimit > 0 else {
            return TextInsertionContext(
                hasSelection: range.length > 0,
                appBundleIdentifier: NSRunningApplication(
                    processIdentifier: processID
                )?.bundleIdentifier,
                accessibilityRole: role,
                accessibilitySubrole: subrole,
                isProtectedContent: isProtectedContent
            )
        }
        let count = (
            attribute(element, name: kAXNumberOfCharactersAttribute)
                as? NSNumber
        )?.intValue
        return TextInsertionContext(
            precedingCharacter: range.location > 0
                ? character(
                    in: element,
                    range: CFRange(location: range.location - 1, length: 1)
                )
                : nil,
            followingCharacter: count.map {
                range.location + range.length < $0
                    ? character(
                        in: element,
                        range: CFRange(
                            location: range.location + range.length,
                            length: 1
                        )
                    )
                    : nil
            } ?? nil,
            hasSelection: range.length > 0,
            isAtDocumentStart: range.location == 0,
            isAtDocumentEnd: count.map {
                range.location + range.length >= $0
            } ?? false,
            appBundleIdentifier: NSRunningApplication(
                processIdentifier: processID
            )?.bundleIdentifier,
            accessibilityRole: role,
            accessibilitySubrole: subrole,
            isProtectedContent: isProtectedContent
        )
    }

    private func character(
        in element: AXUIElement,
        range: CFRange
    ) -> Character? {
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        var result: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            value,
            &result
        ) == .success else {
            return nil
        }
        return (result as? String)?.first
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
