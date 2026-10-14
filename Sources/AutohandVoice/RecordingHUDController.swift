import AppKit
import AutohandVoiceCore
import Observation
import SwiftUI

@MainActor
final class RecordingHUDController: NSWindowController, NSWindowDelegate {
    private let session: VoiceSession
    private let layoutState: RecordingHUDLayoutState
    private var isApplyingPlacement = false
    private var moveMonitor: Any?
    private var dragStartFrame: CGRect?
    private var dragStartPreference: RecordingHUDDisplayPreference?

    init(session: VoiceSession) {
        self.session = session
        let layoutState = RecordingHUDLayoutState()
        self.layoutState = layoutState
        let hostingController = NSHostingController(
            rootView: RecordingHUDView(
                session: session,
                layoutState: layoutState
            )
        )
        let panel = NSPanel(
            contentRect: NSRect(
                origin: .zero,
                size: RecordingHUDPlacement.contentSize(
                    mode: session.effectiveHUDPresentationMode,
                    anchor: .bottom,
                    livePreviewEnabled: false,
                    hasPreviewContent: false
                )
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update() {
        guard session.effectiveShowRecordingHUD else {
            window?.orderOut(nil)
            return
        }
        window?.alphaValue = session.effectiveHUDOpacity
        switch session.state {
        case .ready:
            if session.recordingHUDIdlePresentation.isVisible
                || session.showsTalkCard
            {
                positionOnActiveScreen()
                window?.orderFrontRegardless()
            } else {
                window?.orderOut(nil)
            }
        case .starting, .recording, .processing, .failed:
            positionOnActiveScreen()
            window?.orderFrontRegardless()
        }
    }

    private func positionOnActiveScreen() {
        guard let window, let screen = activeScreen else { return }
        let displayID = displayID(for: screen)
        let placement = session.recordingHUDPlacement(for: displayID)
        layoutState.anchor = placement.anchor
        let isFlow = session.preferences.recordingHUDTheme == .flow
        let showsTalkCard = session.showsTalkCard
        // Flow and the Talk card draw their own soft shadow inside a fixed
        // transparent window.
        window.hasShadow = !isFlow && !showsTalkCard
        window.setContentSize(
            showsTalkCard
                ? RecordingHUDPlacement.talkContentSize
                : isFlow
                ? RecordingHUDPlacement.flowContentSize
                : RecordingHUDPlacement.contentSize(
                    mode: session.effectiveHUDPresentationMode,
                    anchor: placement.anchor,
                    livePreviewEnabled: session.effectiveLivePreviewEnabled,
                    hasPreviewContent:
                        session.shouldShowHUDPreviewContent
                )
        )
        let frame = RecordingHUDPlacement.frame(
            visibleFrame: screen.visibleFrame,
            windowSize: window.frame.size,
            anchor: placement.anchor,
            offset: placement.offset
        )
        isApplyingPlacement = true
        window.setFrame(frame, display: true)
        isApplyingPlacement = false
    }

    func windowDidMove(_ notification: Notification) {
        guard
            session.hudCustomizationEnabled,
            !isApplyingPlacement,
            let window,
            let screen = window.screen
        else { return }
        let displayID = displayID(for: screen)
        let current = session.recordingHUDPlacement(for: displayID)
        let anchor = RecordingHUDPlacement.preferredAnchor(
            for: window.frame,
            visibleFrame: screen.visibleFrame,
            current: current.anchor
        )
        if anchor != layoutState.anchor {
            layoutState.anchor = anchor
            window.setContentSize(
                RecordingHUDPlacement.contentSize(
                    mode: session.effectiveHUDPresentationMode,
                    anchor: anchor,
                    livePreviewEnabled:
                        session.effectiveLivePreviewEnabled,
                    hasPreviewContent:
                        session.shouldShowHUDPreviewContent
                )
            )
        }
        let derived = RecordingHUDPlacement.preference(
            for: window.frame,
            visibleFrame: screen.visibleFrame,
            anchor: anchor
        )
        session.setRecordingHUDPlacement(
            RecordingHUDDisplayPreference(
                displayID: displayID,
                anchor: anchor,
                offset: derived.offset
            )
        )
    }

    func windowWillMove(_ notification: Notification) {
        guard
            session.hudCustomizationEnabled,
            moveMonitor == nil,
            let window,
            let screen = window.screen
        else { return }
        dragStartFrame = window.frame
        dragStartPreference = session.recordingHUDPlacement(
            for: displayID(for: screen)
        )
        moveMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.cancelHUDMove()
                return nil
            }
            if event.type == .leftMouseUp {
                self.endHUDMove()
            }
            return event
        }
    }

    private func cancelHUDMove() {
        guard let window, let dragStartFrame else {
            endHUDMove()
            return
        }
        isApplyingPlacement = true
        if let dragStartPreference {
            layoutState.anchor = dragStartPreference.anchor
            session.setRecordingHUDPlacement(dragStartPreference)
        }
        window.setFrame(dragStartFrame, display: true)
        isApplyingPlacement = false
        endHUDMove()
    }

    private func endHUDMove() {
        if let moveMonitor {
            NSEvent.removeMonitor(moveMonitor)
        }
        moveMonitor = nil
        dragStartFrame = nil
        dragStartPreference = nil
    }

    private func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?
            .stringValue ?? screen.localizedName
    }

    private var activeScreen: NSScreen? {
        let pointerLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            NSMouseInRect(pointerLocation, $0.frame, false)
        } ?? NSScreen.main ?? NSScreen.screens.first
    }
}

@MainActor
@Observable
private final class RecordingHUDLayoutState {
    var anchor: RecordingHUDAnchor = .bottom
}

private struct RecordingHUDView: View {
    let session: VoiceSession
    let layoutState: RecordingHUDLayoutState

    var body: some View {
        if session.showsTalkCard {
            TalkCardView(talk: session.talk)
                .frame(
                    width: RecordingHUDPlacement.talkContentSize.width,
                    height: RecordingHUDPlacement.talkContentSize.height
                )
        } else if session.preferences.recordingHUDTheme == .flow {
            FlowRecordingHUDView(session: session)
                .frame(
                    width: RecordingHUDPlacement.flowContentSize.width,
                    height: RecordingHUDPlacement.flowContentSize.height
                )
        } else {
            Group {
                if session.effectiveHUDPresentationMode == .dot {
                    dotContent
                } else {
                    standardContent
                }
            }
            .frame(width: contentSize.width, height: contentSize.height)
            .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder
    private var standardContent: some View {
        if layoutState.anchor == .bottom {
            bottomContent
        } else {
            sideContent
        }
    }

    private var bottomContent: some View {
        VStack(spacing: hud(8)) {
            capsuleControls
                .frame(width: hud(260), height: hud(74))
                .parityGlassCapsule(tint: .cyan.opacity(0.17))

            if session.shouldShowHUDPreviewContent {
                preview
                    .padding(.horizontal, hud(12))
                    .frame(width: hud(300), height: hud(24))
                    .parityGlassCapsule(tint: .cyan.opacity(0.08))
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sideContent: some View {
        VStack(spacing: hud(12)) {
            leftActionButton
            VoiceWaveform(session: session)
            if session.shouldShowHUDPreviewContent {
                preview
                    .transition(.opacity)
            }
            rightActionButton
        }
        .padding(hud(14))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .parityGlassSurface(
            cornerRadius: hud(44),
            tint: .cyan.opacity(0.17)
        )
    }

    @ViewBuilder
    private var dotContent: some View {
        ZStack {
            switch session.state {
            case .starting, .recording, .failed:
                actionButton
            case .processing:
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("Creating transcript")
            case .ready:
                if session.recordingHUDIdlePresentation.isVisible {
                    actionButton
                } else {
                    Circle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: hud(12), height: hud(12))
                }
            }
        }
        .frame(width: hud(52), height: hud(52))
        .parityGlassSurface(
            cornerRadius: hud(26),
            tint: .cyan.opacity(0.17)
        )
    }

    private var capsuleControls: some View {
        HStack(spacing: 0) {
            leftActionButton

            Spacer(minLength: hud(12))

            VoiceWaveform(session: session)

            Spacer(minLength: hud(12))

            rightActionButton
        }
        .padding(.horizontal, hud(14))
    }

    private var leftActionButton: some View {
        Button {
            switch session.state {
            case .starting, .recording:
                session.cancelRecording()
            case .failed:
                session.recover()
            case .ready:
                if session.recordingHUDIdlePresentation
                    == .cancelledRecording {
                    session.discardRecoverableAudio()
                } else {
                    session.dismissCompletionHUD()
                }
            case .processing:
                break
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: hud(23), weight: .medium))
                .foregroundStyle(.white)
                .frame(width: hud(44), height: hud(44))
                .background(.black, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(session.state == .processing)
        .opacity(session.state == .processing ? 0.72 : 1)
        .help(leftActionHelp)
        .accessibilityLabel(leftActionAccessibilityLabel)
    }

    @ViewBuilder
    private var rightActionButton: some View {
        switch session.state {
        case .starting, .recording:
            Button {
                session.finishRecording()
            } label: {
                Image(systemName: "stop")
                    .font(.system(size: hud(20), weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: hud(40), height: hud(40))
                    .background(.white.opacity(0.36), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop and create transcript")
            .accessibilityLabel("Stop recording")
        case .processing:
            ProgressView()
                .controlSize(.mini)
                .tint(.black)
                .frame(width: hud(40), height: hud(40))
                .background(.white.opacity(0.3), in: Circle())
                .accessibilityLabel("Creating transcript")
        case .ready:
            if session.recordingHUDIdlePresentation
                == .cancelledRecording {
                Button {
                    session.retryRecoverableAudio()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: hud(20), weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: hud(40), height: hud(40))
                        .background(.white.opacity(0.36), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Undo cancel and transcribe locally")
                .accessibilityLabel("Undo cancelled recording")
            } else if session.canCopyFinalFromHUD {
                Button {
                    session.copyFinalFromHUD()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: hud(22), weight: .medium))
                        .foregroundStyle(.black)
                        .frame(width: hud(40), height: hud(40))
                        .background(.white.opacity(0.36), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Copy final transcript")
                .accessibilityLabel("Copy final transcript")
            }
        case .failed:
            Button {
                if session.pendingTranscript != nil {
                    session.retryPendingTranscriptHere()
                } else if session.hasRecoverableAudio {
                    session.retryRecoverableAudio()
                } else {
                    session.recover()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: hud(19), weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: hud(40), height: hud(40))
                    .background(.white.opacity(0.36), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Retry")
            .accessibilityLabel("Retry")
        }
    }

    private var leftActionHelp: String {
        switch session.state {
        case .starting, .recording:
            "Cancel recording — Autohand Voice stays in the menu bar"
        case .processing:
            "Local processing cannot be interrupted"
        case .ready, .failed:
            session.recordingHUDIdlePresentation == .cancelledRecording
                ? "Discard cancelled recording"
                : "Dismiss"
        }
    }

    private var leftActionAccessibilityLabel: String {
        switch session.state {
        case .starting, .recording:
            "Cancel recording"
        case .processing:
            "Local processing cannot be interrupted"
        case .ready, .failed:
            session.recordingHUDIdlePresentation == .cancelledRecording
                ? "Discard cancelled recording"
                : "Dismiss"
        }
    }

    private var contentSize: CGSize {
        RecordingHUDPlacement.contentSize(
            mode: session.effectiveHUDPresentationMode,
            anchor: layoutState.anchor,
            livePreviewEnabled: session.effectiveLivePreviewEnabled,
            hasPreviewContent: session.shouldShowHUDPreviewContent
        )
    }

    private var title: String {
        switch session.state {
        case .ready:
            if session.recordingHUDIdlePresentation == .cancelledRecording {
                "Recording cancelled"
            } else {
                session.completionPresentation == nil ? "Ready" : "Done"
            }
        case .starting: "Waking up"
        case .recording: "Listening · \(elapsedLabel)"
        case .processing: "Creating transcript"
        case .failed: "Needs attention"
        }
    }

    private var detail: String {
        switch session.state {
        case .ready:
            if session.recordingHUDIdlePresentation == .cancelledRecording {
                "Undo to transcribe locally, or discard"
            } else {
                session.completionPresentation
                    ?? "Ready for private, on-device dictation"
            }
        case .starting:
            "Connecting to \(session.audioInputName)"
        case .recording:
            durationWarningLabel ?? recordingInstruction
        case .processing:
            "Finishing privately on this Mac"
        case let .failed(message):
            message
        }
    }

    private var elapsedLabel: String {
        let seconds = max(0, Int(session.recordingElapsed.rounded(.down)))
        return String(
            format: "%02d:%02d",
            seconds / 60,
            seconds % 60
        )
    }

    private var durationWarningLabel: String? {
        switch session.durationWarning {
        case .fifteenMinutes:
            "15 minutes elapsed"
        case .nineteenMinutes:
            "One minute remaining"
        case .none:
            nil
        }
    }

    private var recordingInstruction: String {
        let key = session.preferences.shortcut.displayName
        let instruction: String
        if session.recordingStartedWithFunctionKey {
            instruction = "Release Fn"
        } else {
            switch session.effectiveRecordingMode {
            case .pressAndHold:
                instruction = "Release \(key)"
            case .toggle:
                instruction = "Press \(key) to finish"
            case .handsFree:
                instruction = "Press \(key) to finish · Esc cancels"
            }
        }
        return "\(session.activeStyleLabel) · \(instruction)"
    }

    private var styleMenu: some View {
        Menu {
            Button("Use Profile or Default") {
                session.setTemporaryDictationStyle(nil)
            }
            Divider()
            ForEach(session.dictationStyles) { style in
                Button {
                    session.setTemporaryDictationStyle(style.id)
                } label: {
                    if session.temporaryStyleOverrideID == style.id {
                        Label(style.name, systemImage: "checkmark")
                    } else {
                        Text(style.name)
                    }
                }
            }
        } label: {
            Text(session.activeStyleLabel)
                .font(.caption2)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Temporary dictation style")
        .accessibilityLabel(
            "Dictation style, \(session.activeStyleLabel)"
        )
    }

    private var languageMenu: some View {
        Menu {
            ForEach(
                session.compatibleDictationLanguages,
                id: \.self
            ) { language in
                Button {
                    session.setDictationLanguage(language)
                } label: {
                    if language == session.activeDictationLanguage {
                        Label(
                            language.displayName,
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        } label: {
            Text(session.activeDictationLanguage.code.uppercased())
                .font(.caption2.monospaced())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(
            session.isRecordingOrStarting
                || session.state == .processing
                || session.activeAppProfile?.dictationLanguageCode != nil
        )
        .help("Active dictation language")
        .accessibilityLabel(
            "Dictation language, "
                + session.activeDictationLanguage.displayName
        )
    }

    @ViewBuilder
    private var preview: some View {
        if let provisional = session.provisionalTranscript {
            HStack(alignment: .firstTextBaseline, spacing: hud(7)) {
                Circle()
                    .fill(.cyan)
                    .frame(width: hud(4), height: hud(4))
                    .accessibilityHidden(true)

                Text(provisional)
                    .font(.system(size: 9))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Live preview, \(provisional)")
        } else if let notice = session.provisionalPreviewNotice {
            Label(notice, systemImage: "exclamationmark.circle")
                .font(.system(size: 8))
                .foregroundStyle(.orange)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var standardActionButtons: some View {
        if session.state == .ready, session.canCopyFinalFromHUD {
            Button {
                session.undoPostDictationRevision()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .disabled(!session.canUndoPostDictationRevision)
            .help("Undo Revision")
            .accessibilityLabel("Undo Revision")

            Button {
                session.redoPostDictationRevision()
            } label: {
                Image(systemName: "arrow.uturn.forward")
            }
            .buttonStyle(.borderless)
            .disabled(!session.canRedoPostDictationRevision)
            .help("Redo Revision")
            .accessibilityLabel("Redo Revision")
        } else if case .failed = session.state {
            if session.pendingTranscript != nil {
                Button {
                    session.retryPendingTranscriptHere()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Retry Here")
                .accessibilityLabel("Retry Here")

                Button {
                    session.copyPendingTranscript()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy Final")
                .accessibilityLabel("Copy Final")
            } else if session.hasRecoverableAudio {
                Button {
                    session.retryRecoverableAudio()
                } label: {
                    Image(systemName: "waveform.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Retry Local Audio")
                .accessibilityLabel("Retry Local Audio")
            }
        }
        actionButton
    }

    @ViewBuilder
    private var actionButton: some View {
        switch session.state {
        case .starting, .recording:
            Button {
                session.finishRecording()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: hud(8), weight: .bold))
                    .frame(width: hud(28), height: hud(28))
                    .foregroundStyle(.white)
                    .background(.red.gradient, in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Stop and create transcript")
            .accessibilityLabel("Stop recording")
        case .failed:
            Button {
                session.recover()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: hud(10), weight: .semibold))
                    .frame(width: hud(28), height: hud(28))
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        case .ready:
            if session.recordingHUDIdlePresentation
                == .cancelledRecording {
                Button {
                    session.retryRecoverableAudio()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: hud(10), weight: .semibold))
                        .frame(width: hud(28), height: hud(28))
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Undo cancel and transcribe locally")
                .accessibilityLabel("Undo cancelled recording")
            } else if session.canCopyFinalFromHUD {
                Button {
                    session.copyFinalFromHUD()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: hud(10), weight: .semibold))
                        .frame(width: hud(28), height: hud(28))
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Copy Final")
                .accessibilityLabel("Copy Final")
            }
        case .processing:
            EmptyView()
        }
    }
}

private struct VoiceWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let session: VoiceSession

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion || isFailed
            )
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 5.2

            HStack(spacing: hud(5)) {
                ForEach(0..<11, id: \.self) { index in
                    Capsule()
                        .frame(
                            width: hud(3),
                            height: barHeight(index: index, phase: phase)
                        )
                }
            }
            .frame(width: hud(83), height: hud(30))
            .foregroundStyle(
                isFailed
                    ? Color.orange.opacity(0.9)
                    : Color.black.opacity(0.92)
            )
            .animation(
                .spring(response: 0.18, dampingFraction: 0.72),
                value: session.audioLevel
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone activity")
        .accessibilityValue(
            "\(Int(session.audioLevel * 100)) percent"
        )
    }

    private func barHeight(index: Int, phase: TimeInterval) -> CGFloat {
        let level: CGFloat
        switch session.state {
        case .recording:
            level = max(CGFloat(session.audioLevel), 0.12)
        case .starting:
            level = 0
        case .processing:
            level = 0.42
        case .ready, .failed:
            level = 0
        }
        let motionPhase = reduceMotion ? 0 : phase
        let wave = 0.25
            + (0.75 * abs(sin(motionPhase + Double(index) * 0.74)))
        let center = 1 - abs(CGFloat(index - 5)) / 8
        return hud(3 + (20 * level * CGFloat(wave) * center))
    }

    private var isFailed: Bool {
        if case .failed = session.state {
            return true
        }
        return false
    }
}

/// Scales a HUD design dimension to its on-screen size. The HUD is laid out
/// at its final size rather than shrunk with `scaleEffect`, which rendered
/// text, symbols, and the glass surface at the wrong resolution.
private func hud(_ value: CGFloat) -> CGFloat {
    value * RecordingHUDPlacement.visualScale
}

private extension VoiceSession {
    var shouldShowHUDPreviewContent: Bool {
        guard effectiveLivePreviewEnabled, state == .recording else {
            return false
        }
        return provisionalTranscript?.isEmpty == false
            || provisionalPreviewNotice?.isEmpty == false
    }
}
