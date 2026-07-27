import Foundation

public struct Transcript: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case provisional
        case final
    }

    public let text: String
    public let phase: Phase

    public init(text: String, phase: Phase) {
        self.text = text
        self.phase = phase
    }

    public func finalText() throws -> String {
        guard phase == .final else {
            throw VoiceError.transcriptIsNotFinal
        }
        let normalized = TranscriptNormalizer.normalize(text)
        guard !normalized.isEmpty else {
            throw VoiceError.emptyTranscript
        }
        return normalized
    }
}

public enum TranscriptNormalizer {
    public static func normalize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let sentences = trimmed
            .split(separator: ".", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if sentences.count > 1,
           sentences.dropFirst().allSatisfy({
               $0.compare(
                   sentences[0],
                   options: [.caseInsensitive, .diacriticInsensitive]
               ) == .orderedSame
           }) {
            return sentences[0] + (trimmed.hasSuffix(".") ? "." : "")
        }
        return trimmed
    }
}

public struct ProvisionalPreviewBuffer: Sendable {
    public let maximumCharacters: Int
    public private(set) var transcript: Transcript?

    public init(maximumCharacters: Int = 500) {
        self.maximumCharacters = max(1, maximumCharacters)
    }

    public mutating func update(_ text: String) {
        let normalized = TranscriptNormalizer.normalize(text)
        guard !normalized.isEmpty else {
            transcript = nil
            return
        }
        transcript = Transcript(
            text: String(normalized.suffix(maximumCharacters)),
            phase: .provisional
        )
    }

    public mutating func clear() {
        transcript = nil
    }
}

public struct TranscriptAggregator: Sendable {
    public let maximumCharacters: Int
    private var entries: [String] = []

    public init(maximumCharacters: Int = 50_000) {
        self.maximumCharacters = max(1, maximumCharacters)
    }

    public mutating func append(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        entries.append(value)
        while entries.joined(separator: " ").count > maximumCharacters,
              entries.count > 1 {
            entries.removeFirst()
        }
        if entries.count == 1, entries[0].count > maximumCharacters {
            entries[0] = String(entries[0].suffix(maximumCharacters))
        }
    }

    public var text: String {
        entries.joined(separator: " ")
    }
}
