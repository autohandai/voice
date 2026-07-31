import Foundation

public enum RevisionLimits {
    public static let maximumTextCharacters = 100_000
    public static let maximumChanges = 128
    public static let maximumDepth = 32
}

public enum CleanupLevel: String, Codable, CaseIterable, Sendable {
    case literal
    case light
    case medium
    case high
}

public enum RevisionKind: String, Codable, Sendable {
    case literal
    case lightCleanup
    case mediumCleanup
    case highTransform
    case manual
}

public enum RevisionOutcome: String, Codable, Equatable, Sendable {
    case unchanged
    case revised
    case localTransformUnavailable
}

public enum RevisionError: Error, Equatable, LocalizedError, Sendable {
    case emptyText
    case textTooLong
    case unknownRevision
    case noParentRevision
    case noRedoRevision
    case maximumDepthReached
    case localTransformUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyText:
            "The final transcript is empty."
        case .textTooLong:
            "The transcript exceeds the local revision limit."
        case .unknownRevision:
            "That transcript revision is no longer available."
        case .noParentRevision:
            "There is no earlier transcript revision."
        case .noRedoRevision:
            "There is no later transcript revision."
        case .maximumDepthReached:
            "This transcript reached the revision limit."
        case .localTransformUnavailable:
            "High cleanup needs the optional local Transform model."
        }
    }
}

public struct RawFinalTranscript:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let text: String
    public let languageCode: String
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        text: String,
        languageCode: String,
        createdAt: Date = Date()
    ) throws {
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw RevisionError.emptyText
        }
        guard text.count <= RevisionLimits.maximumTextCharacters else {
            throw RevisionError.textTooLong
        }
        self.id = id
        self.text = text
        self.languageCode = String(languageCode.prefix(32))
        self.createdAt = createdAt
    }
}

public struct BoundedTextChange: Codable, Equatable, Sendable {
    public let characterOffset: Int
    public let removedText: String
    public let insertedText: String

    public init(
        characterOffset: Int,
        removedText: String,
        insertedText: String
    ) {
        self.characterOffset = max(0, characterOffset)
        self.removedText = String(
            removedText.prefix(RevisionLimits.maximumTextCharacters)
        )
        self.insertedText = String(
            insertedText.prefix(RevisionLimits.maximumTextCharacters)
        )
    }
}

public struct TranscriptRevision:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let rootRawID: UUID
    public let parentID: UUID?
    public let text: String
    public let kind: RevisionKind
    public let policyVersion: String
    public let changes: [BoundedTextChange]
    public let depth: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        rootRawID: UUID,
        parentID: UUID?,
        text: String,
        kind: RevisionKind,
        policyVersion: String,
        changes: [BoundedTextChange],
        depth: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rootRawID = rootRawID
        self.parentID = parentID
        self.text = String(
            text.prefix(RevisionLimits.maximumTextCharacters)
        )
        self.kind = kind
        self.policyVersion = String(policyVersion.prefix(64))
        self.changes = Array(
            changes.prefix(RevisionLimits.maximumChanges)
        )
        self.depth = min(max(depth, 0), RevisionLimits.maximumDepth - 1)
        self.createdAt = createdAt
    }
}

public struct RevisionPolicy: Sendable {
    public static let currentVersion = "autohand-revision-1"

    public let level: CleanupLevel
    public let vocabularyRules: [ReplacementRule]
    public let context: TextInsertionContext
    public let addsTerminalPunctuation: Bool
    public let localeIdentifier: String
    public let englishSpellingPolicy: EnglishSpellingPolicy
    public let localTransformAvailable: Bool

    public init(
        level: CleanupLevel,
        vocabularyRules: [ReplacementRule] = [],
        context: TextInsertionContext = .unknown,
        addsTerminalPunctuation: Bool = false,
        localeIdentifier: String = Locale.current.identifier,
        englishSpellingPolicy: EnglishSpellingPolicy = .automatic,
        localTransformAvailable: Bool = false
    ) {
        self.level = level
        self.vocabularyRules = Array(
            vocabularyRules.prefix(VocabularyLimits.maximumRules)
        )
        self.context = context
        self.addsTerminalPunctuation = addsTerminalPunctuation
        self.localeIdentifier = String(localeIdentifier.prefix(64))
        self.englishSpellingPolicy = englishSpellingPolicy
        self.localTransformAvailable = localTransformAvailable
    }
}

public struct RevisionResult: Equatable, Sendable {
    public let raw: RawFinalTranscript
    public let revision: TranscriptRevision
    public let outcome: RevisionOutcome
    public let matchedVocabularyRuleIDs: [UUID]
}

public actor Revision {
    private var revisions: [UUID: TranscriptRevision] = [:]
    private var rawFinals: [UUID: RawFinalTranscript] = [:]
    private var redoChild: [UUID: UUID] = [:]

    public init() {}

    public func propose(
        raw: RawFinalTranscript,
        policy: RevisionPolicy
    ) -> RevisionResult {
        let locale = Locale(identifier: policy.localeIdentifier)
        let output: String
        let outcome: RevisionOutcome
        let matchedVocabularyRuleIDs: [UUID]
        switch policy.level {
        case .literal:
            let application = VocabularyProcessor.applyWithUsage(
                to: raw.text,
                rules: policy.vocabularyRules,
                locale: locale
            )
            output = application.text
            matchedVocabularyRuleIDs = application.matchedRuleIDs
            outcome = output == raw.text ? .unchanged : .revised
        case .light:
            let refined = SpeechTextRefiner.refine(
                raw.text,
                enabled: true,
                locale: locale
            )
            let application = VocabularyProcessor.applyWithUsage(
                to: CanadianEnglishFormatter.apply(
                    to: refined,
                    policy: policy.englishSpellingPolicy,
                    languageCode: raw.languageCode
                ),
                rules: policy.vocabularyRules,
                locale: locale
            )
            output = application.text
            matchedVocabularyRuleIDs = application.matchedRuleIDs
            outcome = output == raw.text ? .unchanged : .revised
        case .medium:
            let application = VocabularyProcessor.applyWithUsage(
                to: CanadianEnglishFormatter.apply(
                    to: SpeechTextRefiner.refine(
                        raw.text,
                        enabled: true,
                        locale: locale
                    ),
                    policy: policy.englishSpellingPolicy,
                    languageCode: raw.languageCode
                ),
                rules: policy.vocabularyRules,
                locale: locale
            )
            let refined = application.text
            matchedVocabularyRuleIDs = application.matchedRuleIDs
            output = SmartTextFormatter.format(
                refined,
                context: policy.context,
                enabled: true,
                addsTerminalPunctuation: policy.addsTerminalPunctuation,
                locale: locale
            )
            outcome = output == raw.text ? .unchanged : .revised
        case .high:
            // A signed local Transform model is intentionally not bundled yet.
            // Availability never implies a remote or heuristic fallback.
            _ = policy.localTransformAvailable
            output = raw.text
            matchedVocabularyRuleIDs = []
            outcome = .localTransformUnavailable
        }

        let rawRevision = TranscriptRevision(
            id: raw.id,
            rootRawID: raw.id,
            parentID: nil,
            text: raw.text,
            kind: .literal,
            policyVersion: "raw-final-1",
            changes: [],
            depth: 0,
            createdAt: raw.createdAt
        )
        let revision = TranscriptRevision(
            rootRawID: raw.id,
            parentID: rawRevision.id,
            text: output,
            kind: kind(for: policy.level),
            policyVersion: RevisionPolicy.currentVersion,
            changes: Self.changeSet(from: raw.text, to: output),
            depth: 1
        )
        rawFinals[raw.id] = raw
        revisions[rawRevision.id] = rawRevision
        revisions[revision.id] = revision
        redoChild[rawRevision.id] = revision.id
        return RevisionResult(
            raw: raw,
            revision: revision,
            outcome: outcome,
            matchedVocabularyRuleIDs: matchedVocabularyRuleIDs
        )
    }

    public func revise(
        from parentID: UUID,
        text: String,
        kind: RevisionKind
    ) throws -> TranscriptRevision {
        guard let parent = revisions[parentID] else {
            throw RevisionError.unknownRevision
        }
        guard text.contains(where: { !$0.isWhitespace }) else {
            throw RevisionError.emptyText
        }
        guard text.count <= RevisionLimits.maximumTextCharacters else {
            throw RevisionError.textTooLong
        }
        guard parent.depth + 1 < RevisionLimits.maximumDepth else {
            throw RevisionError.maximumDepthReached
        }
        let revision = TranscriptRevision(
            rootRawID: parent.rootRawID,
            parentID: parent.id,
            text: text,
            kind: kind,
            policyVersion: RevisionPolicy.currentVersion,
            changes: Self.changeSet(from: parent.text, to: text),
            depth: parent.depth + 1
        )
        revisions[revision.id] = revision
        redoChild[parent.id] = revision.id
        return revision
    }

    public func undo(_ id: UUID) throws -> TranscriptRevision {
        guard let revision = revisions[id] else {
            throw RevisionError.unknownRevision
        }
        guard
            let parentID = revision.parentID,
            let parent = revisions[parentID]
        else {
            throw RevisionError.noParentRevision
        }
        return parent
    }

    public func redo(_ id: UUID) throws -> TranscriptRevision {
        guard revisions[id] != nil else {
            throw RevisionError.unknownRevision
        }
        guard
            let childID = redoChild[id],
            let child = revisions[childID]
        else {
            throw RevisionError.noRedoRevision
        }
        return child
    }

    public func rawFinal(for rootID: UUID) -> RawFinalTranscript? {
        rawFinals[rootID]
    }

    public func restore(
        raw: RawFinalTranscript,
        revision: TranscriptRevision
    ) throws {
        guard revision.rootRawID == raw.id else {
            throw RevisionError.unknownRevision
        }
        let rawRevision = TranscriptRevision(
            id: raw.id,
            rootRawID: raw.id,
            parentID: nil,
            text: raw.text,
            kind: .literal,
            policyVersion: "raw-final-1",
            changes: [],
            depth: 0,
            createdAt: raw.createdAt
        )
        rawFinals[raw.id] = raw
        revisions[rawRevision.id] = rawRevision
        revisions[revision.id] = revision
        if revision.id != rawRevision.id {
            redoChild[rawRevision.id] = revision.id
        }
    }

    private func kind(for level: CleanupLevel) -> RevisionKind {
        switch level {
        case .literal: .literal
        case .light: .lightCleanup
        case .medium: .mediumCleanup
        case .high: .highTransform
        }
    }

    private static func changeSet(
        from source: String,
        to destination: String
    ) -> [BoundedTextChange] {
        guard source != destination else { return [] }
        let lhs = Array(source)
        let rhs = Array(destination)
        var prefix = 0
        while
            prefix < lhs.count,
            prefix < rhs.count,
            lhs[prefix] == rhs[prefix]
        {
            prefix += 1
        }
        var suffix = 0
        while
            suffix < lhs.count - prefix,
            suffix < rhs.count - prefix,
            lhs[lhs.count - 1 - suffix] == rhs[rhs.count - 1 - suffix]
        {
            suffix += 1
        }
        let removedEnd = lhs.count - suffix
        let insertedEnd = rhs.count - suffix
        return [
            BoundedTextChange(
                characterOffset: prefix,
                removedText: String(lhs[prefix ..< removedEnd]),
                insertedText: String(rhs[prefix ..< insertedEnd])
            ),
        ]
    }
}
