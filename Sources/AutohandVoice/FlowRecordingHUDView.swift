import AutohandVoiceCore
import SwiftUI

/// The Flow recording HUD: a slim dark pill whose bars follow the voice.
/// Controls appear on hover while recording; result states keep their
/// actions visible.
struct FlowRecordingHUDView: View {
    let session: VoiceSession
    @State private var isHovering = false

    var body: some View {
        pill
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .environment(\.colorScheme, .dark)
    }

    private var pill: some View {
        HStack(spacing: 8) {
            if showsLeadingControl {
                leadingControl
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            center
            if showsTrailingControl {
                trailingControl
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.leading, showsLeadingControl ? 6 : 16)
        .padding(.trailing, showsTrailingControl ? 6 : 16)
        .frame(height: 34)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.05).opacity(0.94))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 10, y: 4)
        // Size the pill to its content; long messages truncate at maxWidth.
        .fixedSize()
        .contentShape(Capsule(style: .continuous))
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.82),
            value: phase
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - State

    private enum Phase: Equatable {
        case listening
        case transcribing
        case done
        case cancelled
        case failed
    }

    private var phase: Phase {
        switch session.state {
        case .starting, .recording:
            .listening
        case .processing:
            .transcribing
        case .failed:
            .failed
        case .ready:
            session.recordingHUDIdlePresentation == .cancelledRecording
                ? .cancelled
                : .done
        }
    }

    private var showsLeadingControl: Bool {
        switch phase {
        case .listening: isHovering
        case .transcribing, .done: false
        case .cancelled, .failed: true
        }
    }

    private var showsTrailingControl: Bool {
        switch phase {
        case .listening: isHovering
        case .transcribing: false
        case .done: session.canCopyFinalFromHUD
        case .cancelled, .failed: true
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var center: some View {
        switch phase {
        case .listening:
            if session.isTalkRecording {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.talkAccent)
                    FlowVoiceBars(session: session, mode: .live, tint: .talkAccent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Listening for Fantail")
            } else {
                FlowVoiceBars(session: session, mode: .live)
                    .accessibilityLabel("Listening")
            }
        case .transcribing:
            FlowVoiceBars(session: session, mode: .thinking)
                .accessibilityLabel("Creating transcript")
        case .done:
            message(
                symbol: "checkmark",
                tint: .green,
                text: "Done"
            )
        case .cancelled:
            message(symbol: nil, tint: .clear, text: "Cancelled")
        case .failed:
            message(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                text: failureMessage
            )
            .help(failureMessage)
        }
    }

    private var failureMessage: String {
        if case let .failed(message) = session.state { return message }
        return ""
    }

    private func message(
        symbol: String?,
        tint: Color,
        text: String
    ) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: 230)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Controls

    @ViewBuilder
    private var leadingControl: some View {
        switch phase {
        case .listening:
            control("xmark", label: "Cancel recording") {
                session.cancelRecording()
            }
        case .cancelled:
            control("xmark", label: "Discard cancelled recording") {
                session.discardRecoverableAudio()
            }
        case .failed:
            control("xmark", label: "Dismiss") {
                session.recover()
            }
        case .transcribing, .done:
            EmptyView()
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch phase {
        case .listening:
            control("stop.fill", label: "Stop recording", prominent: true) {
                session.finishRecording()
            }
        case .done:
            control("doc.on.doc", label: "Copy final transcript") {
                session.copyFinalFromHUD()
            }
        case .cancelled:
            control(
                "arrow.uturn.backward",
                label: "Undo cancelled recording",
                prominent: true
            ) {
                session.retryRecoverableAudio()
            }
        case .failed:
            control("arrow.clockwise", label: "Retry", prominent: true) {
                if session.pendingTranscript != nil {
                    session.retryPendingTranscriptHere()
                } else if session.hasRecoverableAudio {
                    session.retryRecoverableAudio()
                } else {
                    session.recover()
                }
            }
        case .transcribing:
            EmptyView()
        }
    }

    private func control(
        _ symbol: String,
        label: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(prominent ? .black : .white)
                .frame(width: 22, height: 22)
                .background(
                    prominent ? Color.white : Color.white.opacity(0.14),
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Nine bars: live mode draws the real recent microphone levels; thinking
/// mode is a calm travelling wave while the transcript is created.
private struct FlowVoiceBars: View {
    enum Mode {
        case live
        case thinking
    }

    let session: VoiceSession
    let mode: Mode
    var tint: Color = .white
    @State private var meter = VoiceBarsMeter(barCount: Self.envelope.count)

    private static let envelope: [Double] = [
        0.42, 0.6, 0.8, 0.94, 1, 0.94, 0.8, 0.6, 0.42,
    ]
    private static let barWidth: CGFloat = 3
    private static let spacing: CGFloat = 3
    private static let minimumHeight: CGFloat = 3
    private static let maximumHeight: CGFloat = 20

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let levels = barLevels(at: time)
            HStack(spacing: Self.spacing) {
                ForEach(Self.envelope.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(tint.opacity(mode == .live ? 0.95 : 0.6))
                        .frame(
                            width: Self.barWidth,
                            height: height(level: levels[index])
                        )
                }
            }
            .frame(height: Self.maximumHeight)
        }
        .frame(
            width: CGFloat(Self.envelope.count) * Self.barWidth
                + CGFloat(Self.envelope.count - 1) * Self.spacing
        )
    }

    private func barLevels(at time: TimeInterval) -> [Double] {
        switch mode {
        case .live:
            let levels = meter.bars(
                level: StatusBarWaveformAnimation.meterLevel(
                    rms: session.audioInputRMS
                ),
                at: time
            )
            // A gentle taper keeps the pill shape without inventing motion.
            return levels.indices.map {
                levels[$0] * (0.7 + 0.3 * Self.envelope[$0])
            }
        case .thinking:
            return Self.envelope.indices.map {
                0.32 * Self.envelope[$0]
                    * (0.5 + 0.5 * sin(time * 5 - Double($0) * 0.7))
            }
        }
    }

    private func height(level: Double) -> CGFloat {
        Self.minimumHeight
            + CGFloat(level) * (Self.maximumHeight - Self.minimumHeight)
    }
}

/// Turns a stream of meter readings into bar levels from the real voice:
/// readings are smoothed (quick rise, gentle fall) and sampled into a
/// short history at a steady pace, independent of the frame rate.
final class VoiceBarsMeter {
    private static let sampleInterval: TimeInterval = 0.05

    private var smoothed = 0.0
    private var history: VoiceLevelHistory
    private var lastSample: TimeInterval = 0

    init(barCount: Int) {
        history = VoiceLevelHistory(barCount: barCount)
    }

    func bars(level target: Double, at time: TimeInterval) -> [Double] {
        let rate = target > smoothed ? 0.55 : 0.2
        smoothed += (target - smoothed) * rate
        if time - lastSample >= Self.sampleInterval {
            history.push(smoothed)
            lastSample = time
        }
        return history.barLevels
    }
}
