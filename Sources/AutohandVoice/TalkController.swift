import AppKit
import AutohandVoiceCore
import Foundation
import Observation
import OSLog

/// Runs Talk conversations: a local transcript goes to Fantail, the streamed
/// reply is shown and spoken with the local voice. Audio never leaves the Mac.
@MainActor
@Observable
final class TalkController {
    enum Phase: Equatable {
        case idle
        case listening
        case needsSignIn(question: String)
        case thinking(question: String)
        case replying(question: String, reply: String, isSpeaking: Bool)
        case failed(TalkFailure, question: String?)
    }

    /// A conversation is forgotten after this long without a new turn.
    static let conversationIdleTimeout: Duration = .seconds(120)

    private(set) var phase: Phase = .idle {
        didSet {
            if phase != oldValue { onChange?() }
        }
    }
    private(set) var voiceNotice: String?
    private(set) var isPreparingVoice = false

    let account: AutohandAccount
    @ObservationIgnored let speaker: TalkSpeaker
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onInsert: ((String) -> Void)?

    @ObservationIgnored private let client: FantailClient
    @ObservationIgnored private var conversation = TalkConversation()
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "talk"
    )

    init(
        account: AutohandAccount? = nil,
        speaker: TalkSpeaker? = nil,
        client: FantailClient = FantailClient()
    ) {
        let account = account ?? AutohandAccount()
        let speaker = speaker ?? TalkSpeaker()
        self.account = account
        self.speaker = speaker
        self.client = client
        speaker.onIdle = { [weak self] in self?.speechFinished() }
        speaker.onFailure = { [weak self] error in
            self?.voiceNotice =
                "The voice couldn't play: \(error.localizedDescription)"
            self?.speechFinished()
        }
        account.onSignedIn = { [weak self] in self?.resumeAfterSignIn() }
    }

    /// True while the pill should show a Talk card (not while listening,
    /// which the recording HUD shows itself).
    var showsCard: Bool {
        switch phase {
        case .idle, .listening: false
        default: true
        }
    }

    var isWorking: Bool {
        if replyTask != nil { return true }
        if case let .replying(_, _, isSpeaking) = phase { return isSpeaking }
        return false
    }

    var currentReply: String? {
        if case let .replying(_, reply, _) = phase { return reply }
        return nil
    }

    // MARK: - Turns

    /// Fn+Shift is down: interrupt any reply and listen for the next question.
    func beginListening() {
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        expiryTask?.cancel()
        phase = .listening
    }

    /// The Talk recording was discarded or failed before producing text.
    func cancelListening() {
        guard phase == .listening else { return }
        phase = .idle
        scheduleExpiry()
    }

    func ask(_ question: String) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            cancelListening()
            return
        }
        replyTask?.cancel()
        speaker.stop()
        expiryTask?.cancel()
        voiceNotice = nil
        guard let token = account.token, account.isSignedIn else {
            phase = .needsSignIn(question: question)
            return
        }
        conversation.appendUser(question)
        phase = .thinking(question: question)
        let request = FantailChatRequest(
            messages: conversation.requestMessages(
                systemPrompt: FantailChatRequest.spokenSystemPrompt
            ),
            conversationID: conversation.id
        )
        replyTask = Task { [weak self] in
            await self?.streamReply(request, token: token, question: question)
        }
        onChange?()
        prepareVoiceInBackground()
    }

    func retry() {
        switch phase {
        case let .failed(_, question?), let .needsSignIn(question):
            ask(question)
        default:
            break
        }
    }

    func signInToContinue() {
        account.signIn()
    }

    /// Stops the voice and the rest of the reply; keeps what was received.
    func stopSpeaking() {
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        if case let .replying(question, reply, _) = phase {
            conversation.appendAssistant(reply)
            phase = .replying(question: question, reply: reply, isSpeaking: false)
        } else if case .thinking = phase {
            conversation.withdrawUnansweredQuestion()
            phase = .idle
        }
        scheduleExpiry()
    }

    /// Hides the card but keeps the conversation for a quick follow-up.
    func dismiss() {
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        phase = .idle
        scheduleExpiry()
    }

    /// Forgets the conversation entirely.
    func endConversation() {
        replyTask?.cancel()
        replyTask = nil
        expiryTask?.cancel()
        speaker.stop()
        conversation = TalkConversation()
        voiceNotice = nil
        phase = .idle
    }

    /// Speaks a short sample so people can hear the voice; the first call
    /// also downloads the voice model.
    func playVoiceSample() {
        guard !isPreparingVoice else { return }
        speaker.stop()
        voiceNotice = nil
        isPreparingVoice = !speaker.isPrepared
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.speaker.prepare()
                self.isPreparingVoice = false
                self.speaker.enqueue(
                    "Hi, I'm Fantail. Hold Fn and Shift, and ask me anything."
                )
            } catch {
                self.isPreparingVoice = false
                self.voiceNotice =
                    "The voice couldn't load: \(error.localizedDescription)"
            }
        }
    }

    func copyReply() {
        guard let reply = currentReply else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply, forType: .string)
    }

    func insertReply() {
        guard let reply = currentReply else { return }
        onInsert?(reply)
    }

    func openUpgrade() {
        guard case let .failed(failure, _) = phase, let url = failure.upgradeURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Streaming

    private func streamReply(
        _ request: FantailChatRequest,
        token: String,
        question: String
    ) async {
        var reply = ""
        var chunker = SpokenReplyChunker()
        defer {
            if !Task.isCancelled {
                replyTask = nil
                onChange?()
            }
        }
        do {
            for try await update in client.reply(to: request, token: token) {
                switch update {
                case let .quota(quota):
                    account.update(quota: quota)
                case let .text(text):
                    reply += text
                    phase = .replying(
                        question: question,
                        reply: SpokenText.clean(reply),
                        isSpeaking: true
                    )
                    chunker.append(text).forEach(speak)
                }
            }
            try Task.checkCancellation()
            if let rest = chunker.finish() {
                speak(rest)
            }
            let spoken = SpokenText.clean(reply)
            guard !spoken.isEmpty else { throw TalkFailure.unavailable }
            conversation.appendAssistant(spoken)
            let stillSpeaking = speaker.isSpeaking
            phase = .replying(
                question: question,
                reply: spoken,
                isSpeaking: stillSpeaking
            )
            if !stillSpeaking {
                scheduleExpiry()
            }
        } catch is CancellationError {
            return
        } catch {
            let failure = error as? TalkFailure ?? .connectionLost
            Self.logger.error("Talk turn failed: \(failure.message)")
            conversation.withdrawUnansweredQuestion()
            speaker.stop()
            if failure == .signInRequired {
                account.credentialRejected()
                phase = .needsSignIn(question: question)
            } else {
                phase = .failed(failure, question: question)
            }
        }
    }

    private func speak(_ sentence: String) {
        let text = SpokenText.clean(sentence)
        guard !text.isEmpty else { return }
        speaker.enqueue(text)
    }

    /// Speech went quiet. While the reply is still streaming this is only a
    /// gap between sentences; the stream's end settles the final state.
    private func speechFinished() {
        guard
            replyTask == nil,
            case let .replying(question, reply, true) = phase
        else { return }
        phase = .replying(question: question, reply: reply, isSpeaking: false)
        scheduleExpiry()
    }

    private func resumeAfterSignIn() {
        guard case let .needsSignIn(question) = phase else { return }
        ask(question)
    }

    /// Loads the voice while Fantail thinks, so the first sentence plays
    /// without waiting for the model.
    private func prepareVoiceInBackground() {
        guard !speaker.isPrepared else { return }
        Task { [weak self] in
            do {
                try await self?.speaker.prepare()
            } catch {
                self?.voiceNotice =
                    "The voice couldn't load: \(error.localizedDescription)"
            }
        }
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.conversationIdleTimeout)
            guard !Task.isCancelled, let self else { return }
            if !self.isWorking, self.phase != .listening {
                self.endConversation()
            }
        }
    }
}
