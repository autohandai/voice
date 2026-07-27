import AppKit
import SwiftUI

@MainActor
final class RecordingHUDController: NSWindowController {
    private let session: VoiceSession

    init(session: VoiceSession) {
        self.session = session
        let hostingController = NSHostingController(
            rootView: RecordingHUDView(session: session)
        )
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 88),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update() {
        guard session.preferences.showRecordingHUD else {
            window?.orderOut(nil)
            return
        }
        switch session.state {
        case .ready:
            window?.orderOut(nil)
        case .starting, .recording, .processing, .failed:
            positionIfNeeded()
            window?.orderFrontRegardless()
        }
    }

    private func positionIfNeeded() {
        guard
            let window,
            !window.isVisible,
            let screen = NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - (window.frame.width / 2),
            y: visible.maxY - window.frame.height - 28
        )
        window.setFrameOrigin(origin)
    }
}

private struct RecordingHUDView: View {
    let session: VoiceSession

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: session.state.symbol)
                .font(.title2)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(session.state.label)
                    .font(.headline)
                    .lineLimit(2)

                if session.state == .recording {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(
                            value: Double(session.audioLevel),
                            total: 1
                        )
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Microphone level")
                        .accessibilityValue(
                            "\(Int(session.audioLevel * 100)) percent"
                        )
                        Text(
                            "\(session.audioInputName) · \(session.audioInputHealth.label)"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                } else {
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            actionButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 360)
        .frame(minHeight: 88)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    private var statusDetail: String {
        switch session.state {
        case .ready: "Ready"
        case .starting: "Connecting to the microphone"
        case .recording: "Listening locally"
        case .processing: "Finalizing on this Mac"
        case .failed:
            session.pendingTranscript == nil
                ? "Open the menu or Settings for recovery"
                : "Final transcript is recoverable from the menu"
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch session.state {
        case .starting, .recording:
            Button("Stop") {
                session.finishRecording()
            }
            .keyboardShortcut(.cancelAction)
        case .failed:
            Button("Dismiss") {
                session.recover()
            }
        case .ready, .processing:
            EmptyView()
        }
    }
}
