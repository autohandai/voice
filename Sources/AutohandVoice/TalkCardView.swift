import AutohandVoiceCore
import SwiftUI

extension Color {
    /// Accent that marks Talk (Fantail) so it never looks like dictation.
    static let talkAccent = Color(red: 0.64, green: 0.55, blue: 1)
}

/// The Fantail reply card shown in the recording HUD window.
struct TalkCardView: View {
    let talk: TalkController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
            actions
        }
        .padding(14)
        .frame(width: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.05).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 12, y: 5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 8)
        .environment(\.colorScheme, .dark)
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: talk.phase)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.talkAccent)
            Text(talk.engine() == .local ? "On this Mac" : "Fantail")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            if talk.isHandsFree {
                Text("Hands-free")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.talkAccent)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Color.talkAccent.opacity(0.16), in: Capsule())
            }
            if talk.isWorking {
                TalkVoiceBars(speaker: talk.speaker, isThinking: isThinking)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            if let remaining = talk.account.quota?.remaining, remaining <= 5 {
                Text("\(remaining) left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
            Button {
                talk.endConversation()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help("End conversation")
            .accessibilityLabel("End conversation")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch talk.phase {
        case let .thinking(question):
            questionLine(question)
            if let progress = talk.localModelProgress {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        progress < 1
                            ? "Downloading the on-device model (one time only)…"
                            : "Loading the on-device model…"
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
                    if progress < 1 {
                        ProgressView(value: progress)
                            .tint(Color.talkAccent)
                    }
                }
            } else {
                Text("Thinking…")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
        case let .replying(question, reply, _):
            questionLine(question)
            Text(reply)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let voiceNotice = talk.voiceNotice {
                notice(voiceNotice)
            }
        case let .needsSignIn(question):
            questionLine(question)
            signInMessage
        case let .failed(failure, question):
            if let question {
                questionLine(question)
            }
            Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .labelStyle(TintedIconLabelStyle(tint: .orange))
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .listening:
            EmptyView()
        }
    }

    @ViewBuilder
    private var signInMessage: some View {
        if case let .signingIn(code, _) = talk.account.status {
            VStack(alignment: .leading, spacing: 4) {
                Text("Finish signing in in your browser.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                Text("Code: \(code)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled)
            }
        } else {
            Text("Sign in with Autohand to talk with Fantail. Your question is kept and sent once you're in.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            switch talk.phase {
            case .thinking:
                pill("Stop", prominent: false) { talk.stopSpeaking() }
                handsFreeHint
            case let .replying(_, _, isSpeaking):
                if isSpeaking {
                    pill("Stop", prominent: false) { talk.stopSpeaking() }
                    handsFreeHint
                } else {
                    pill("Insert", prominent: true) { talk.insertReply() }
                    pill("Copy", prominent: false) { talk.copyReply() }
                    if talk.history.turns.count > 1 {
                        pill("Copy Conversation", prominent: false) {
                            talk.copyConversation()
                        }
                    }
                    Spacer(minLength: 0)
                    if talk.isHandsFree {
                        handsFreeHint
                    } else if talk.history.turns.count <= 1 {
                        // With Copy Conversation the row is full; keep the
                        // buttons whole rather than squeeze them.
                        hint("Hold Fn + Shift to reply")
                    }
                }
            case .needsSignIn:
                if case .signingIn = talk.account.status {
                    pill("Open Browser", prominent: true) {
                        talk.account.reopenSignInPage()
                    }
                    pill("Cancel", prominent: false) {
                        talk.account.cancelSignIn()
                    }
                } else {
                    pill("Sign In", prominent: true) { talk.signInToContinue() }
                }
            case let .failed(failure, _):
                if failure.upgradeURL != nil {
                    pill("Upgrade", prominent: true) { talk.openUpgrade() }
                }
                if failure.isRetryable {
                    pill("Try Again", prominent: failure.upgradeURL == nil) {
                        talk.retry()
                    }
                }
            case .idle, .listening:
                EmptyView()
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var handsFreeHint: some View {
        if talk.isHandsFree {
            Spacer(minLength: 0)
            hint("Listening after each reply. Esc ends")
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.white.opacity(0.45))
            .lineLimit(1)
    }

    private var isThinking: Bool {
        if case .thinking = talk.phase { return true }
        return false
    }

    private func questionLine(_ question: String) -> some View {
        Text(question)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.5))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.orange.opacity(0.9))
            .lineLimit(2)
    }

    private func pill(
        _ title: LocalizedStringKey,
        prominent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(
                    prominent ? Color.white : Color.white.opacity(0.14),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon
                .foregroundStyle(tint)
            configuration.title
        }
    }
}

/// Small violet bars: follow the voice while speaking, a calm wave while
/// Fantail is thinking.
struct TalkVoiceBars: View {
    let speaker: TalkSpeaker
    let isThinking: Bool
    @State private var meter = VoiceBarsMeter(barCount: Self.count)

    private static let count = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let levels = barLevels(at: time)
            HStack(spacing: 2) {
                ForEach(0..<Self.count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(Color.talkAccent)
                        .frame(
                            width: 2.5,
                            height: 3 + CGFloat(levels[index]) * 9
                        )
                }
            }
            .frame(height: 12)
        }
    }

    /// Thinking is a calm wave; speaking follows the real voice output.
    private func barLevels(at time: TimeInterval) -> [Double] {
        if isThinking {
            return (0..<Self.count).map {
                0.35 * (0.55 + 0.45 * sin(time * 7 - Double($0) * 0.9))
            }
        }
        return meter.bars(
            level: StatusBarWaveformAnimation.meterLevel(rms: speaker.level),
            at: time
        )
    }
}
