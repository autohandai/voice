import XCTest
@testable import AutohandVoiceCore

final class TalkConversationTests: XCTestCase {
    func testRequestStartsWithSystemPromptAndKeepsTurnOrder() {
        var conversation = TalkConversation()
        conversation.appendUser("What's on Mars?")
        conversation.appendAssistant("Dust, mostly.")
        conversation.appendUser("And the weather?")

        let messages = conversation.requestMessages(systemPrompt: "Be brief.")

        XCTAssertEqual(messages.map(\.role), [.system, .user, .assistant, .user])
        XCTAssertEqual(messages.first?.content, "Be brief.")
        XCTAssertEqual(messages.last?.content, "And the weather?")
    }

    func testHistoryIsTrimmedToRecentTurnsAndStartsWithUser() {
        var conversation = TalkConversation()
        for index in 0..<10 {
            conversation.appendUser("Question \(index)")
            conversation.appendAssistant("Answer \(index)")
        }
        conversation.appendUser("Latest")

        let history = conversation.requestMessages(systemPrompt: "S").dropFirst()

        XCTAssertLessThanOrEqual(history.count, TalkConversation.maximumMessages)
        XCTAssertEqual(history.first?.role, .user)
        XCTAssertEqual(history.last?.content, "Latest")
    }

    func testCharacterBudgetDropsOldTurnsButNeverTheLatestQuestion() {
        var conversation = TalkConversation()
        conversation.appendUser(String(repeating: "a", count: 3_000))
        conversation.appendAssistant(String(repeating: "b", count: 3_000))
        let latest = String(repeating: "c", count: 5_000)
        conversation.appendUser(latest)

        let history = conversation.requestMessages(systemPrompt: "S").dropFirst()

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.content.count, TalkConversation.maximumCharacters)
    }

    func testFailedQuestionCanBeWithdrawnWithoutTouchingAnswers() {
        var conversation = TalkConversation()
        conversation.appendUser("One")
        conversation.appendAssistant("Answer")
        conversation.appendUser("Two")

        conversation.withdrawUnansweredQuestion()
        XCTAssertEqual(conversation.messages.map(\.content), ["One", "Answer"])
        conversation.withdrawUnansweredQuestion()
        XCTAssertEqual(conversation.messages.map(\.content), ["One", "Answer"])
    }

    func testBlankTurnsAreIgnored() {
        var conversation = TalkConversation()
        conversation.appendUser("   ")
        conversation.appendAssistant("")
        XCTAssertTrue(conversation.messages.isEmpty)
    }
}

final class FantailRequestTests: XCTestCase {
    func testRequestUsesFantailStreamingAndASmallTokenBudget() throws {
        let conversationID = UUID()
        let request = FantailChatRequest(
            messages: [TalkMessage(role: .user, content: "Hi")],
            conversationID: conversationID
        )
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request))
                as? [String: Any]
        )

        XCTAssertEqual(json["model"] as? String, "fantail")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["max_tokens"] as? Int, FantailChatRequest.spokenMaxTokens)
        XCTAssertLessThanOrEqual(FantailChatRequest.spokenMaxTokens, 400)
        XCTAssertEqual(json["prompt_cache_key"] as? String, conversationID.uuidString)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages, [["role": "user", "content": "Hi"]])
    }
}

final class FantailStreamParserTests: XCTestCase {
    func testContentDeltasAreExtracted() {
        let line = #"data: {"choices":[{"index":0,"delta":{"content":"Hello"}}]}"#
        XCTAssertEqual(FantailStreamParser.parse(line: line), .content("Hello"))
    }

    func testDoneKeepaliveBlankAndUsageLinesAreHandled() {
        XCTAssertEqual(FantailStreamParser.parse(line: "data: [DONE]"), .done)
        XCTAssertEqual(FantailStreamParser.parse(line: ": keepalive"), .ignored)
        XCTAssertEqual(FantailStreamParser.parse(line: ""), .ignored)
        XCTAssertEqual(
            FantailStreamParser.parse(line: #"data: {"choices":[],"usage":{"prompt_tokens":3}}"#),
            .ignored
        )
        XCTAssertEqual(
            FantailStreamParser.parse(line: #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"length"}]}"#),
            .finished("length")
        )
    }

    func testMalformedDataIsIgnoredNotFatal() {
        XCTAssertEqual(FantailStreamParser.parse(line: "data: {not json"), .ignored)
    }
}

final class AutohandAPIErrorTests: XCTestCase {
    private func body(_ json: String) -> Data { Data(json.utf8) }

    func testFiveHourQuotaMapsToUpgradePromptWithResetTime() {
        let failure = AutohandAPIError.failure(
            status: 429,
            body: body(#"{"error":{"type":"rate_limited","message":"You've used all your requests in this 5-hour window.","scope":"window_5h","resetAt":1760012345,"upgradeUrl":"https://console.autohand.ai/upgrade/?from=cli&tier=lite"}}"#),
            retryAfter: "8123"
        )
        XCTAssertEqual(
            failure,
            .quotaReached(
                resetAt: Date(timeIntervalSince1970: 1_760_012_345),
                upgradeURL: URL(string: "https://console.autohand.ai/upgrade/?from=cli&tier=lite")
            )
        )
    }

    func testMonthlyQuotaAndMissingModelAlsoOfferUpgrade() {
        let monthly = AutohandAPIError.failure(
            status: 429,
            body: body(#"{"error":{"type":"rate_limited","scope":"window_month","upgradeUrl":"https://console.autohand.ai/upgrade/"}}"#),
            retryAfter: nil
        )
        XCTAssertEqual(monthly, .quotaReached(resetAt: nil, upgradeURL: URL(string: "https://console.autohand.ai/upgrade/")))

        let model = AutohandAPIError.failure(
            status: 403,
            body: body(#"{"error":{"type":"model_not_available","upgradeUrl":"https://console.autohand.ai/upgrade/"}}"#),
            retryAfter: nil
        )
        XCTAssertEqual(model, .quotaReached(resetAt: nil, upgradeURL: URL(string: "https://console.autohand.ai/upgrade/")))
    }

    func testThroughputRequestRateAndCapacityAreRetryable() {
        XCTAssertEqual(
            AutohandAPIError.failure(
                status: 429,
                body: body(#"{"error":{"type":"rate_limited","scope":"output_tpm","upgradeUrl":"https://console.autohand.ai/upgrade/"}}"#),
                retryAfter: "12"
            ),
            .slowDown(retryAfter: 12, upgradeURL: URL(string: "https://console.autohand.ai/upgrade/"))
        )
        XCTAssertEqual(
            AutohandAPIError.failure(
                status: 429,
                body: body(#"{"error":{"type":"rate_limited","scope":"rpm"}}"#),
                retryAfter: "3"
            ),
            .busy(retryAfter: 3)
        )
    }

    func testCredentialAndEligibilityErrors() {
        for type in ["unauthorized", "invalid_credential", "session_expired"] {
            XCTAssertEqual(
                AutohandAPIError.failure(status: 401, body: body(#"{"error":{"type":"\#(type)"}}"#), retryAfter: nil),
                .signInRequired
            )
        }
        XCTAssertEqual(
            AutohandAPIError.failure(
                status: 402,
                body: body(#"{"error":{"type":"eligibility_required","upgradeUrl":"https://console.autohand.ai/upgrade/"}}"#),
                retryAfter: nil
            ),
            .verifyEmail
        )
    }

    func testBlockedContentKeepsServerMessageAndUnknownErrorsAreUnavailable() {
        XCTAssertEqual(
            AutohandAPIError.failure(
                status: 400,
                body: body(#"{"error":{"type":"content_blocked","message":"Rephrase it and try again."}}"#),
                retryAfter: nil
            ),
            .blocked(message: "Rephrase it and try again.")
        )
        XCTAssertEqual(
            AutohandAPIError.failure(status: 502, body: Data("<html>".utf8), retryAfter: nil),
            .unavailable
        )
    }

    func testUntrustedUpgradeLinksAreDropped() {
        XCTAssertNil(AutohandUpgradeLink.trusted("http://console.autohand.ai/upgrade/"))
        XCTAssertNil(AutohandUpgradeLink.trusted("https://evil.example/upgrade/"))
        XCTAssertNil(AutohandUpgradeLink.trusted("https://console.autohand.ai.evil.example/"))
        XCTAssertNotNil(AutohandUpgradeLink.trusted("https://console.autohand.ai/upgrade/?tier=lite"))
        XCTAssertEqual(
            AutohandAPIError.failure(
                status: 429,
                body: body(#"{"error":{"type":"rate_limited","scope":"window_5h","upgradeUrl":"https://evil.example/"}}"#),
                retryAfter: nil
            ),
            .quotaReached(resetAt: nil, upgradeURL: AutohandUpgradeLink.fallback)
        )
    }

    func testQuotaHeadersReportRemainingTurns() {
        let quota = TalkQuota(headers: [
            "x-autohand-remaining-5h": "4",
            "X-Autohand-Remaining-Month": "61",
        ])
        XCTAssertEqual(quota, TalkQuota(remainingInWindow: 4, remainingThisMonth: 61))
        XCTAssertNil(TalkQuota(headers: [:]))
    }
}

final class SpokenReplyTests: XCTestCase {
    func testChunkerEmitsCompleteSentencesAsTheyStream() {
        var chunker = SpokenReplyChunker()
        XCTAssertEqual(chunker.append("Sure. I moved"), ["Sure."])
        XCTAssertEqual(chunker.append(" it to Thursday! Want"), ["I moved it to Thursday!"])
        XCTAssertEqual(chunker.append(" the details?"), [])
        XCTAssertEqual(chunker.finish(), "Want the details?")
        XCTAssertNil(chunker.finish())
    }

    func testChunkerDoesNotSplitDecimalsAndBreaksLongRuns() {
        var chunker = SpokenReplyChunker()
        XCTAssertEqual(chunker.append("Pi is 3.14 roughly"), [])
        let long = String(repeating: "word ", count: 80)
        let emitted = chunker.append(long)
        XCTAssertFalse(emitted.isEmpty)
        XCTAssertTrue(emitted.allSatisfy { $0.count <= SpokenReplyChunker.maximumChunkLength })
    }

    func testMarkdownIsRemovedBeforeSpeaking() {
        XCTAssertEqual(
            SpokenText.clean("## Plan\n- **Move** the `meeting`\n- See [docs](https://x.y)"),
            "Plan. Move the meeting. See docs"
        )
        XCTAssertEqual(SpokenText.clean("Run:\n```\nrm -rf /\n```\nDone."), "Run: Done.")
    }
}

final class AutohandDeviceSignInTests: XCTestCase {
    func testInitiationDecodes() throws {
        let start = try DeviceSignInStart.decode(Data(#"""
        {"success":true,"schemaVersion":2,"deviceCode":"dev123","userCode":"ABCD-EFGH","verificationUri":"https://autohand.ai/signin","verificationUriComplete":"https://autohand.ai/signin?user_code=ABCD-EFGH","expiresIn":300,"interval":5}
        """#.utf8))
        XCTAssertEqual(start.userCode, "ABCD-EFGH")
        XCTAssertEqual(start.deviceCode, "dev123")
        XCTAssertEqual(start.verificationURL.absoluteString, "https://autohand.ai/signin?user_code=ABCD-EFGH")
        XCTAssertEqual(start.interval, 5)
        XCTAssertEqual(start.expiresIn, 300)
    }

    func testInitiationRequestIdentifiesAsVoice() throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DeviceSignInRequest())) as? [String: Any]
        XCTAssertEqual(body?["clientId"] as? String, "autohand-cli")
        XCTAssertEqual(body?["clientType"] as? String, "voice")
        XCTAssertEqual(body?["schemaVersion"] as? Int, 2)
        XCTAssertEqual(body?.count, 3)
    }

    func testInitiationRejectsNonHTTPSVerificationLinks() {
        XCTAssertThrowsError(try DeviceSignInStart.decode(Data(#"""
        {"deviceCode":"d","userCode":"U","verificationUri":"http://x","verificationUriComplete":"http://x","expiresIn":300,"interval":5}
        """#.utf8)))
    }

    func testPollStates() {
        XCTAssertEqual(
            DeviceSignInPoll.decode(status: 200, body: Data(#"{"status":"pending","interval":5}"#.utf8), retryAfter: nil),
            .pending(interval: 5)
        )
        XCTAssertEqual(
            DeviceSignInPoll.decode(status: 429, body: Data(#"{"success":false,"error":{"code":"slow_down"}}"#.utf8), retryAfter: "10"),
            .slowDown(retryAfter: 10)
        )
        XCTAssertEqual(
            DeviceSignInPoll.decode(
                status: 200,
                body: Data(#"{"status":"authorized","token":"ahc_abc","user":{"id":"u1","email":"a@b.c","name":"Ana"}}"#.utf8),
                retryAfter: nil
            ),
            .authorized(token: "ahc_abc", email: "a@b.c")
        )
        XCTAssertEqual(
            DeviceSignInPoll.decode(status: 200, body: Data(#"{"status":"expired"}"#.utf8), retryAfter: nil),
            .expired
        )
        XCTAssertEqual(
            DeviceSignInPoll.decode(status: 200, body: Data(#"{"status":"cancelled"}"#.utf8), retryAfter: nil),
            .cancelled
        )
        XCTAssertEqual(
            DeviceSignInPoll.decode(status: 409, body: Data(#"{"error":{"code":"credential_already_delivered"}}"#.utf8), retryAfter: nil),
            .failed
        )
    }

    func testEndpointsDefaultToProductionAndAcceptHTTPSOverrides() {
        let defaults = AutohandEndpoints(environment: [:])
        XCTAssertEqual(defaults.chatCompletions.absoluteString, "https://inference.autohand.ai/v1/chat/completions")
        XCTAssertEqual(defaults.deviceInitiate.absoluteString, "https://api.autohand.ai/v1/auth/cli/initiate")
        XCTAssertEqual(defaults.devicePoll.absoluteString, "https://api.autohand.ai/v1/auth/cli/poll")
        XCTAssertEqual(defaults.deviceCancel.absoluteString, "https://api.autohand.ai/v1/auth/cli/cancel")
        XCTAssertEqual(defaults.accountProfile.absoluteString, "https://api.autohand.ai/v1/auth/me")

        let overridden = AutohandEndpoints(environment: [
            "AUTOHAND_VOICE_API_URL": "https://staging.autohand.ai/v1",
            "AUTOHAND_VOICE_INFERENCE_URL": "http://insecure.example/v1",
        ])
        XCTAssertEqual(overridden.deviceInitiate.absoluteString, "https://staging.autohand.ai/v1/auth/cli/initiate")
        XCTAssertEqual(overridden.chatCompletions.absoluteString, "https://inference.autohand.ai/v1/chat/completions")
    }
}
