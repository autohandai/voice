import XCTest
@testable import AutohandVoiceCore

@MainActor
final class TextInsertionTests: XCTestCase {
    func testUsesPasteAsThePrimaryInsertionPath() throws {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commit(
            Transcript(text: "native dictation", phase: .final),
            mode: .type,
            target: target
        )

        XCTAssertTrue(driver.directInsertions.isEmpty)
        XCTAssertEqual(driver.pasteInsertions, ["native dictation"])
    }

    func testFallsBackToDirectInsertionWhenPasteCannotBePosted() throws {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: false
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commit(
            Transcript(text: "native dictation", phase: .final),
            mode: .type,
            target: target
        )

        XCTAssertEqual(driver.pasteInsertions, ["native dictation"])
        XCTAssertEqual(driver.directInsertions, ["native dictation"])
    }

    func testDoesNotPasteWithoutAFocusedControl() {
        let driver = TestTextInsertionDriver(
            directResult: .noFocusedElement,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        driver.targetAvailable = false

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "do not insert", phase: .final),
                mode: .type,
                target: nil
            )
        ) { error in
            XCTAssertEqual(error as? VoiceError, .noFocusedTextField)
        }
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
    }

    func testFocusChangeStopsBeforeDirectInsertion() throws {
        let driver = TestTextInsertionDriver(
            directResult: .focusMoved,
            pasteResult: .focusMoved
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "keep recoverable", phase: .final),
                mode: .type,
                target: target
            )
        ) { error in
            XCTAssertEqual(error as? VoiceError, .insertionTargetChanged)
        }
        XCTAssertEqual(driver.pasteInsertions, ["keep recoverable"])
        XCTAssertTrue(driver.directInsertions.isEmpty)
    }

    func testPasteFallbackRevalidatesCapturedTarget() throws {
        let driver = TestTextInsertionDriver(
            directResult: .unsupported,
            pasteResult: false
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        XCTAssertThrowsError(
            try inserter.commit(
                Transcript(text: "do not misdirect", phase: .final),
                mode: .type,
                target: target
            )
        )
        XCTAssertEqual(driver.pasteInsertions, ["do not misdirect"])
    }

    func testVerifiedFinalTextPreservesCommandLineBreaks() throws {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commitVerifiedFinalText(
            "first\nsecond\n",
            mode: .type,
            target: target
        )

        XCTAssertTrue(driver.directInsertions.isEmpty)
        XCTAssertEqual(driver.pasteInsertions, ["first\nsecond\n"])
    }

    func testTargetCaptureDefaultsToNoAdjacentContext() {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)

        _ = inserter.captureTarget()
        _ = inserter.captureTarget(contextScalarLimit: 12)

        XCTAssertEqual(driver.capturedScalarLimits, [0, 12])
    }

    func testTerminalPlanAvoidsClipboardPaste() throws {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        driver.context = TextInsertionContext(
            appBundleIdentifier: "com.apple.Terminal",
            accessibilityRole: "AXTextArea"
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commitVerifiedFinalText(
            "printf 'one\\ntwo'\n",
            mode: .type,
            target: target
        )

        XCTAssertEqual(driver.directInsertions, ["printf 'one\\ntwo'\n"])
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
        XCTAssertTrue(driver.unicodeInsertions.isEmpty)
    }

    func testTestedTerminalMayUseUnicodeEventsAfterAccessibilityRejectsText() throws {
        let driver = TestTextInsertionDriver(
            directResult: .unsupported,
            pasteResult: .inserted,
            unicodeResult: .inserted
        )
        driver.context = TextInsertionContext(
            appBundleIdentifier: "com.googlecode.iterm2",
            accessibilityRole: "AXTextArea"
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        try inserter.commitVerifiedFinalText(
            "one\ntwo",
            mode: .type,
            target: target
        )

        XCTAssertEqual(driver.directInsertions, ["one\ntwo"])
        XCTAssertTrue(driver.pasteInsertions.isEmpty)
        XCTAssertEqual(driver.unicodeInsertions, ["one\ntwo"])
    }

    func testExplicitEnterUsesCapturedTargetAndSurfacesFocusMove()
        throws
    {
        let driver = TestTextInsertionDriver(
            directResult: .inserted,
            pasteResult: true
        )
        let inserter = TextInserter(driver: driver)
        let target = try XCTUnwrap(inserter.captureTarget())

        driver.enterResult = .inserted
        try inserter.commitExplicitEnter(target: target)
        XCTAssertEqual(driver.enterAttempts, 1)

        driver.enterResult = .focusMoved
        XCTAssertThrowsError(
            try inserter.commitExplicitEnter(target: target)
        ) { error in
            XCTAssertEqual(
                error as? VoiceError,
                .insertionTargetChanged
            )
        }
        XCTAssertEqual(driver.enterAttempts, 2)
    }
}

@MainActor
private final class TestTextInsertionDriver: TextInsertionDriving {
    let directResult: DirectInsertionResult
    let pasteResult: PasteInsertionResult
    var targetAvailable = true
    var context = TextInsertionContext.unknown
    var directInsertions: [String] = []
    var pasteInsertions: [String] = []
    var unicodeInsertions: [String] = []
    var capturedScalarLimits: [Int] = []
    var unicodeResult: DirectInsertionResult = .unsupported
    var enterResult: DirectInsertionResult = .unsupported
    var enterAttempts = 0

    init(directResult: DirectInsertionResult, pasteResult: Bool) {
        self.directResult = directResult
        self.pasteResult = pasteResult ? .inserted : .failed
    }

    init(
        directResult: DirectInsertionResult,
        pasteResult: PasteInsertionResult,
        unicodeResult: DirectInsertionResult = .unsupported
    ) {
        self.directResult = directResult
        self.pasteResult = pasteResult
        self.unicodeResult = unicodeResult
    }

    func hasAccessibilityPermission(prompt: Bool) -> Bool {
        true
    }

    func captureTarget(contextScalarLimit: Int) -> TextInsertionTarget? {
        capturedScalarLimits.append(contextScalarLimit)
        return targetAvailable
            ? TextInsertionTarget(storage: NSObject(), context: context)
            : nil
    }

    func insertSelectedText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        directInsertions.append(text)
        return directResult
    }

    func pastePreservingClipboard(
        _ text: String,
        target: TextInsertionTarget
    ) -> PasteInsertionResult {
        pasteInsertions.append(text)
        return pasteResult
    }

    func insertUnicodeText(
        _ text: String,
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        unicodeInsertions.append(text)
        return unicodeResult
    }

    func sendEnter(
        target: TextInsertionTarget
    ) -> DirectInsertionResult {
        enterAttempts += 1
        return enterResult
    }
}
