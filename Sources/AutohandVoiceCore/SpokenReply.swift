import Foundation

/// Splits a streamed reply into sentences so speech can start before the
/// whole answer arrives.
public struct SpokenReplyChunker: Sendable {
    public static let maximumChunkLength = 220

    private var buffer = ""

    public init() {}

    /// Adds streamed text and returns any sentences that are now complete.
    public mutating func append(_ delta: String) -> [String] {
        buffer += delta
        var sentences: [String] = []
        while let sentence = nextSentence() {
            sentences.append(sentence)
        }
        return sentences
    }

    /// Returns whatever text remains once the stream has ended.
    public mutating func finish() -> String? {
        let rest = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer = ""
        return rest.isEmpty ? nil : rest
    }

    private mutating func nextSentence() -> String? {
        let characters = Array(buffer)
        for index in characters.indices where index + 1 < characters.count {
            let character = characters[index]
            let next = characters[index + 1]
            let endsSentence = ".!?…".contains(character) && next.isWhitespace
            if endsSentence || character == "\n" {
                return take(upTo: index + 1)
            }
        }
        if characters.count > Self.maximumChunkLength {
            let window = characters.prefix(Self.maximumChunkLength)
            let split = window.lastIndex(where: { $0 == "," || $0 == ";" })
                ?? window.lastIndex(where: \.isWhitespace)
                ?? Self.maximumChunkLength - 1
            return take(upTo: split + 1)
        }
        return nil
    }

    private mutating func take(upTo count: Int) -> String? {
        let head = String(buffer.prefix(count))
        buffer = String(buffer.dropFirst(count))
        let sentence = head.trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nextSentence() : sentence
    }
}

/// Turns model output into text that sounds right when read aloud.
public enum SpokenText {
    public static func clean(_ text: String) -> String {
        var lines: [String] = []
        var inCodeBlock = false
        for rawLine in text.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            guard !inCodeBlock else { continue }
            let line = cleanInline(stripBlockMarkers(trimmed))
            if !line.isEmpty {
                lines.append(line)
            }
        }
        var result = ""
        for line in lines {
            if !result.isEmpty {
                let ending = result.last.map { ".!?:;,…".contains($0) } ?? true
                result += ending ? " " : ". "
            }
            result += line
        }
        return result
    }

    private static func stripBlockMarkers(_ line: String) -> String {
        var line = line
        while line.hasPrefix("#") {
            line.removeFirst()
        }
        line = line.trimmingCharacters(in: .whitespaces)
        for marker in ["- ", "* ", "+ ", "> "] where line.hasPrefix(marker) {
            line = String(line.dropFirst(marker.count))
        }
        if let range = line.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
            line.removeSubrange(range)
        }
        return line
    }

    private static func cleanInline(_ line: String) -> String {
        var line = line.replacingOccurrences(
            of: #"\[([^\]]+)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        for marker in ["**", "__", "`", "*", "~~"] {
            line = line.replacingOccurrences(of: marker, with: "")
        }
        return line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}
