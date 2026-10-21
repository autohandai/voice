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
        /// A tool is running (reading a file, looking at a window…).
        case working(question: String, activity: String)
        /// A tool wants to change something and waits for the person.
        case awaitingApproval(question: String, request: ToolApprovalRequest)
        case failed(TalkFailure, question: String?)
    }

    /// Most tool rounds one question may take.
    static let maximumToolRounds = 8

    /// A conversation is forgotten after this long without a new turn.
    static let conversationIdleTimeout: Duration = .seconds(120)

    private(set) var phase: Phase = .idle {
        didSet {
            if phase != oldValue { onChange?() }
        }
    }
    private(set) var voiceNotice: String?
    private(set) var isPreparingVoice = false
    /// Every turn of this conversation, for Copy Conversation.
    private(set) var history = TalkHistory()
    /// The conversation keeps listening between replies (no keys held).
    private(set) var isHandsFree = false
    /// Download (below 1) or loading (1) progress of the on-device model
    /// while a question waits for it.
    private(set) var localModelProgress: Double?

    let account: AutohandAccount
    @ObservationIgnored let speaker: TalkSpeaker
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onInsert: ((String) -> Void)?
    /// A turn is over. `keepListening` is false when the conversation cannot
    /// continue on its own (a failure or sign-in is needed).
    @ObservationIgnored var onTurnEnded: ((_ keepListening: Bool) -> Void)?
    /// The person closed the conversation from the card.
    @ObservationIgnored var onConversationEnded: (() -> Void)?

    @ObservationIgnored private let client: FantailClient
    /// Files and computer tools offered to Fantail.
    @ObservationIgnored var toolbox: TalkAgentToolbox?
    @ObservationIgnored private var approvalContinuation: CheckedContinuation<Bool, Never>?
    @ObservationIgnored private var allowedForConversation: Set<String> = []
    @ObservationIgnored private var declinedThisTurn: Set<String> = []
    /// Answers on this Mac when the person picked the local model.
    @ObservationIgnored var localModel: LocalTalkModel?
    /// The engine chosen in Settings, read when each question is asked.
    @ObservationIgnored var engine: () -> TalkEngine = { .fantail }
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

    /// Thinking, running a tool or waiting for approval: no reply yet.
    private var isBusyWithoutReply: Bool {
        switch phase {
        case .thinking, .working, .awaitingApproval: true
        default: false
        }
    }

    var currentReply: String? {
        if case let .replying(_, reply, _) = phase { return reply }
        return nil
    }

    // MARK: - Turns

    /// Fn+Shift is down: interrupt any reply and listen for the next question.
    func beginListening() {
        cancelPendingApproval()
        if engine() == .local {
            localModel?.prepareInBackground()
        }
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
        if engine() == .local {
            askLocally(question)
            return
        }
        guard account.isSignedIn, let token = account.currentToken() else {
            phase = .needsSignIn(question: question)
            onTurnEnded?(false)
            return
        }
        conversation.appendUser(question)
        phase = .thinking(question: question)
        var systemPrompt = FantailChatRequest.spokenSystemPrompt
        if let addendum = toolbox?.systemPromptAddendum {
            systemPrompt += " " + addendum
        }
        let messages = conversation.requestMessages(systemPrompt: systemPrompt)
        replyTask = Task { [weak self] in
            await self?.runFantailTurn(messages, token: token, question: question)
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
        cancelPendingApproval()
        let wasStreaming = replyTask != nil
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        let wasAnswering: Bool
        if case let .replying(question, reply, isSpeaking) = phase {
            wasAnswering = isSpeaking
            // A finished reply was recorded when its stream ended.
            if isSpeaking, wasStreaming {
                conversation.appendAssistant(reply)
                history.append(TalkTurn(question: question, reply: reply))
            }
            phase = .replying(question: question, reply: reply, isSpeaking: false)
        } else if isBusyWithoutReply {
            wasAnswering = true
            conversation.withdrawUnansweredQuestion()
            phase = .idle
        } else {
            wasAnswering = false
        }
        scheduleExpiry()
        if wasAnswering {
            onTurnEnded?(true)
        }
    }

    /// Hides the card but keeps the conversation for a quick follow-up.
    func dismiss() {
        cancelPendingApproval()
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        phase = .idle
        scheduleExpiry()
    }

    /// Forgets the conversation entirely.
    func endConversation() {
        cancelPendingApproval()
        replyTask?.cancel()
        replyTask = nil
        expiryTask?.cancel()
        speaker.stop()
        conversation = TalkConversation()
        history.removeAll()
        allowedForConversation.removeAll()
        isHandsFree = false
        voiceNotice = nil
        phase = .idle
        onConversationEnded?()
    }

    // MARK: - Hands-free

    func beginHandsFree() {
        isHandsFree = true
        expiryTask?.cancel()
    }

    /// Stops the hands-free loop but keeps the conversation on screen so it
    /// can be copied.
    func endHandsFree() {
        guard isHandsFree else { return }
        isHandsFree = false
        let wasStreaming = replyTask != nil
        replyTask?.cancel()
        replyTask = nil
        speaker.stop()
        switch phase {
        case .listening, .thinking:
            if let last = history.turns.last {
                phase = .replying(
                    question: last.question,
                    reply: last.reply,
                    isSpeaking: false
                )
            } else {
                phase = .idle
            }
        case let .replying(question, reply, true):
            if wasStreaming {
                conversation.appendAssistant(reply)
                history.append(TalkTurn(question: question, reply: reply))
            }
            phase = .replying(question: question, reply: reply, isSpeaking: false)
        default:
            break
        }
        scheduleExpiry()
    }

    var conversationText: String {
        TalkTranscript.text(
            history.turns,
            assistantName: engine() == .local ? "Bonsai" : "Fantail"
        )
    }

    func copyConversation() {
        let text = conversationText
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    private func askLocally(_ question: String) {
        guard let localModel else {
            phase = .failed(.localModelUnavailable(
                "The on-device model isn't available in this build."
            ), question: question)
            onTurnEnded?(false)
            return
        }
        if let reason = localModel.unavailableReason {
            phase = .failed(.localModelUnavailable(reason), question: question)
            onTurnEnded?(false)
            return
        }
        conversation.appendUser(question)
        phase = .thinking(question: question)
        let messages = conversation.requestMessages(
            systemPrompt: FantailChatRequest.spokenSystemPrompt
        )
        replyTask = Task { [weak self] in
            guard let self else { return }
            do {
                if !localModel.isReady {
                    self.localModelProgress = 0
                    defer { self.localModelProgress = nil }
                    try await localModel.prepare { progress in
                        Task { @MainActor [weak self] in
                            guard let self, self.localModelProgress != nil else {
                                return
                            }
                            self.localModelProgress = progress
                        }
                    }
                }
                try Task.checkCancellation()
                let updates = localModel.reply(
                    to: messages,
                    maxTokens: FantailChatRequest.spokenMaxTokens
                )
                await self.consumeReply(
                    AsyncThrowingStream { continuation in
                        let task = Task {
                            do {
                                for try await text in updates {
                                    continuation.yield(.text(text))
                                }
                                continuation.finish()
                            } catch {
                                continuation.finish(throwing: error)
                            }
                        }
                        continuation.onTermination = { _ in task.cancel() }
                    },
                    question: question
                )
            } catch is CancellationError {
                return
            } catch {
                await self.consumeReply(
                    AsyncThrowingStream { $0.finish(throwing: error) },
                    question: question
                )
            }
        }
        onChange?()
        prepareVoiceInBackground()
    }

    /// One Fantail question, with tools: when the reply asks for tools,
    /// run them (approving changes on the card) and ask again, up to
    /// `maximumToolRounds` times. Only the final answer joins the history.
    private func runFantailTurn(
        _ base: [TalkMessage],
        token: String,
        question: String
    ) async {
        var messages = base
        var reply = ""
        var chunker = SpokenReplyChunker()
        declinedThisTurn.removeAll()
        defer {
            if !Task.isCancelled {
                replyTask = nil
                onChange?()
            }
        }
        do {
            let tools = toolbox?.definitions ?? []
            for round in 0..<Self.maximumToolRounds {
                let lastRound = round == Self.maximumToolRounds - 1
                let request = FantailChatRequest(
                    messages: messages,
                    conversationID: conversation.id,
                    tools: lastRound ? [] : tools
                )
                var roundText = ""
                var calls = ToolCallAccumulator()
                for try await update in client.reply(to: request, token: token) {
                    switch update {
                    case let .quota(quota):
                        account.update(quota: quota)
                    case let .text(text):
                        roundText += text
                        reply += text
                        phase = .replying(
                            question: question,
                            reply: SpokenText.clean(reply),
                            isSpeaking: true
                        )
                        chunker.append(text).forEach(speak)
                    case let .toolCalls(deltas):
                        calls.add(deltas)
                    }
                }
                try Task.checkCancellation()
                let requested = calls.calls
                guard !requested.isEmpty, let toolbox else { break }
                // Text before a tool call is narration ("let me look"); the
                // answer that follows restates it, so only the answer stays.
                reply = String(reply.dropLast(roundText.count))
                chunker = SpokenReplyChunker()
                messages.append(TalkMessage(
                    role: .assistant,
                    content: roundText,
                    toolCalls: requested
                ))
                for call in requested {
                    try Task.checkCancellation()
                    phase = .working(
                        question: question,
                        activity: toolbox.activity(for: call)
                    )
                    let result = await toolbox.run(call) { [weak self] request in
                        await self?.requestApproval(request, question: question) ?? false
                    }
                    try Task.checkCancellation()
                    messages.append(TalkMessage(toolResult: result, for: call.id))
                }
            }
            try finishReply(reply, chunker: &chunker, question: question)
        } catch is CancellationError {
            return
        } catch {
            failTurn(error, question: question)
        }
    }

    // MARK: - Approval

    /// Pauses a tool until the person allows or denies it on the card.
    private func requestApproval(
        _ request: ToolApprovalRequest,
        question: String
    ) async -> Bool {
        if allowedForConversation.contains(request.kind) { return true }
        // Asking again for something just declined would nag; decline it.
        if declinedThisTurn.contains(request.summary) { return false }
        cancelPendingApproval()
        phase = .awaitingApproval(question: question, request: request)
        return await withCheckedContinuation { continuation in
            approvalContinuation = continuation
        }
    }

    func approvePendingTool(forConversation: Bool = false) {
        if forConversation, case let .awaitingApproval(_, request) = phase {
            allowedForConversation.insert(request.kind)
        }
        resolveApproval(true)
    }

    func denyPendingTool() {
        resolveApproval(false)
    }

    private func resolveApproval(_ allowed: Bool) {
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        if !allowed, case let .awaitingApproval(_, request) = phase {
            declinedThisTurn.insert(request.summary)
        }
        if case let .awaitingApproval(question, _) = phase {
            phase = .working(
                question: question,
                activity: allowed ? "Working…" : "Skipping that…"
            )
        }
        continuation.resume(returning: allowed)
    }

    /// Any interruption counts as "no", so a tool never waits forever.
    private func cancelPendingApproval() {
        guard let continuation = approvalContinuation else { return }
        approvalContinuation = nil
        continuation.resume(returning: false)
    }

    private func consumeReply(
        _ updates: AsyncThrowingStream<FantailClient.Update, Error>,
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
            for try await update in updates {
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
                case .toolCalls:
                    // The on-device model answers without tools.
                    break
                }
            }
            try Task.checkCancellation()
            try finishReply(reply, chunker: &chunker, question: question)
        } catch is CancellationError {
            return
        } catch {
            failTurn(error, question: question)
        }
    }

    private func finishReply(
        _ reply: String,
        chunker: inout SpokenReplyChunker,
        question: String
    ) throws {
        if let rest = chunker.finish() {
            speak(rest)
        }
        let spoken = SpokenText.clean(reply)
        guard !spoken.isEmpty else { throw TalkFailure.unavailable }
        conversation.appendAssistant(spoken)
        history.append(TalkTurn(question: question, reply: spoken))
        let stillSpeaking = speaker.isSpeaking
        phase = .replying(
            question: question,
            reply: spoken,
            isSpeaking: stillSpeaking
        )
        if !stillSpeaking {
            scheduleExpiry()
            onTurnEnded?(true)
        }
    }

    private func failTurn(_ error: Error, question: String) {
        let failure = error as? TalkFailure
            ?? (engine() == .local
                ? .localModelUnavailable(error.localizedDescription)
                : .connectionLost)
        Self.logger.error("Talk turn failed: \(failure.message)")
        conversation.withdrawUnansweredQuestion()
        speaker.stop()
        if failure == .signInRequired {
            account.credentialRejected()
            phase = .needsSignIn(question: question)
        } else {
            phase = .failed(failure, question: question)
        }
        onTurnEnded?(false)
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
        onTurnEnded?(true)
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
            if !self.isWorking, !self.isHandsFree, self.phase != .listening {
                self.endConversation()
            }
        }
    }
}
