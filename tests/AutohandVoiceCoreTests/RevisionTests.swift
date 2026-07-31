import XCTest
@testable import AutohandVoiceCore

final class RevisionTests: XCTestCase {
    func testLiteralPreservesRawFinalExactly() async throws {
        let raw = try RawFinalTranscript(
            text: "Um, keep this this exactly",
            languageCode: "en"
        )
        let engine = Revision()

        let result = await engine.propose(
            raw: raw,
            policy: RevisionPolicy(level: .literal)
        )

        XCTAssertEqual(result.revision.text, raw.text)
        XCTAssertTrue(result.revision.changes.isEmpty)
        XCTAssertEqual(result.outcome, .unchanged)
    }

    func testLightAppliesDeterministicCleanupAndExplicitVocabulary() async throws {
        let raw = try RawFinalTranscript(
            text: "Um, ask eager costa this this week",
            languageCode: "en"
        )
        let engine = Revision()
        let policy = RevisionPolicy(
            level: .light,
            vocabularyRules: [
                ReplacementRule(
                    source: "eager costa",
                    replacement: "Igor Costa"
                ),
            ]
        )

        let result = await engine.propose(raw: raw, policy: policy)

        XCTAssertEqual(result.revision.text, "ask Igor Costa this week")
        XCTAssertFalse(result.revision.changes.isEmpty)
        XCTAssertEqual(result.revision.parentID, raw.id)
        let rawRevision = try await engine.undo(result.revision.id)
        XCTAssertEqual(rawRevision.id, raw.id)
        XCTAssertEqual(rawRevision.text, raw.text)
    }

    func testMediumPreservesExistingSmartFormattingBehavior() async throws {
        let raw = try RawFinalTranscript(
            text: "hello from autohand voice",
            languageCode: "en"
        )
        let engine = Revision()
        let policy = RevisionPolicy(
            level: .medium,
            context: TextInsertionContext(
                isAtDocumentStart: true,
                isAtDocumentEnd: true
            ),
            addsTerminalPunctuation: true
        )

        let result = await engine.propose(raw: raw, policy: policy)

        XCTAssertEqual(result.revision.text, "Hello from autohand voice.")
    }

    func testHighWithoutLocalModelReturnsUnchangedExplicitFailure() async throws {
        let raw = try RawFinalTranscript(
            text: "keep this local",
            languageCode: "en"
        )
        let engine = Revision()

        let result = await engine.propose(
            raw: raw,
            policy: RevisionPolicy(
                level: .high,
                localTransformAvailable: false
            )
        )

        XCTAssertEqual(result.outcome, .localTransformUnavailable)
        XCTAssertEqual(result.revision.text, raw.text)
        XCTAssertTrue(result.revision.changes.isEmpty)
    }

    func testUndoRedoAndBranchingRemainWithinOneRawRoot() async throws {
        let raw = try RawFinalTranscript(
            text: "Um, hello",
            languageCode: "en"
        )
        let engine = Revision()
        let first = await engine.propose(
            raw: raw,
            policy: RevisionPolicy(level: .light)
        )
        let second = try await engine.revise(
            from: first.revision.id,
            text: "Hello.",
            kind: .manual
        )

        let undone = try await engine.undo(second.id)
        XCTAssertEqual(undone.id, first.revision.id)
        let redone = try await engine.redo(undone.id)
        XCTAssertEqual(redone.id, second.id)

        _ = try await engine.undo(second.id)
        let branch = try await engine.revise(
            from: first.revision.id,
            text: "Hello!",
            kind: .manual
        )
        let branchedRedo = try await engine.redo(first.revision.id)
        XCTAssertEqual(branchedRedo.id, branch.id)
        XCTAssertNotEqual(branchedRedo.id, second.id)
        XCTAssertEqual(branch.parentID, first.revision.id)
        XCTAssertEqual(branch.rootRawID, raw.id)
    }

    func testRawAndRevisionBoundsAreEnforced() async throws {
        XCTAssertThrowsError(
            try RawFinalTranscript(
                text: String(repeating: "x", count: RevisionLimits.maximumTextCharacters + 1),
                languageCode: "en"
            )
        ) { error in
            XCTAssertEqual(error as? RevisionError, .textTooLong)
        }

        let raw = try RawFinalTranscript(text: "one", languageCode: "en")
        let engine = Revision()
        let first = await engine.propose(
            raw: raw,
            policy: RevisionPolicy(level: .literal)
        )
        var current = first.revision
        for index in 0 ..< RevisionLimits.maximumDepth - 2 {
            current = try await engine.revise(
                from: current.id,
                text: "value \(index)",
                kind: .manual
            )
        }
        await XCTAssertThrowsErrorAsync(
            try await engine.revise(
                from: current.id,
                text: "too deep",
                kind: .manual
            )
        ) { error in
            XCTAssertEqual(error as? RevisionError, .maximumDepthReached)
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in },
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
