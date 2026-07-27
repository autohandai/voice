import Foundation

public struct DictationCommandResult: Equatable, Sendable {
    public let text: String
    public let shouldCancel: Bool
    public let commandsApplied: Int

    public init(
        text: String,
        shouldCancel: Bool,
        commandsApplied: Int
    ) {
        self.text = text
        self.shouldCancel = shouldCancel
        self.commandsApplied = commandsApplied
    }
}

public enum DictationCommandProcessor {
    private static let expression = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_])command\s+(new paragraph|new line|question mark|scratch that|cancel dictation|literal mode|comma|period)(?![\p{L}\p{N}_])"#,
        options: [.caseInsensitive]
    )

    public static func process(
        _ text: String,
        enabled: Bool,
        locale: Locale = .current
    ) -> DictationCommandResult {
        guard enabled, locale.language.languageCode?.identifier == "en" else {
            return .init(text: text, shouldCancel: false, commandsApplied: 0)
        }
        guard let expression else {
            return .init(text: text, shouldCancel: false, commandsApplied: 0)
        }

        let source = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: source.length)
        )
        guard !matches.isEmpty else {
            return .init(text: text, shouldCancel: false, commandsApplied: 0)
        }

        var output = ""
        var cursor = 0
        var applied = 0
        var stripsLeadingWhitespace = false

        for match in matches {
            let precedingRange = NSRange(
                location: cursor,
                length: match.range.location - cursor
            )
            var preceding = source.substring(with: precedingRange)
            if stripsLeadingWhitespace {
                preceding = preceding.trimmingPrefixWhitespace()
                stripsLeadingWhitespace = false
            }
            output += preceding

            let phrase = source.substring(with: match.range)
                .lowercased(with: locale)
                .replacingOccurrences(
                    of: #"^command\s+"#,
                    with: "",
                    options: .regularExpression
                )
            applied += 1
            cursor = NSMaxRange(match.range)

            switch phrase {
            case "comma":
                output.trimTrailingHorizontalWhitespace()
                output += ","
            case "period":
                output.trimTrailingHorizontalWhitespace()
                output += "."
            case "question mark":
                output.trimTrailingHorizontalWhitespace()
                output += "?"
            case "new line":
                output.trimTrailingHorizontalWhitespace()
                output += "\n"
                stripsLeadingWhitespace = true
            case "new paragraph":
                output.trimTrailingWhitespaceAndNewlines()
                output += "\n\n"
                stripsLeadingWhitespace = true
            case "scratch that":
                output = ""
                stripsLeadingWhitespace = true
            case "cancel dictation":
                return .init(
                    text: "",
                    shouldCancel: true,
                    commandsApplied: applied
                )
            case "literal mode":
                let remaining = source.substring(
                    from: NSMaxRange(match.range)
                ).trimmingPrefixWhitespace()
                output.trimTrailingHorizontalWhitespace()
                if !output.isEmpty, !remaining.isEmpty {
                    output += " "
                }
                output += remaining
                return .init(
                    text: output,
                    shouldCancel: false,
                    commandsApplied: applied
                )
            default:
                break
            }
        }

        var remainder = source.substring(from: cursor)
        if stripsLeadingWhitespace {
            remainder = remainder.trimmingPrefixWhitespace()
        }
        output += remainder
        return .init(
            text: output,
            shouldCancel: false,
            commandsApplied: applied
        )
    }
}

private extension String {
    func trimmingPrefixWhitespace() -> String {
        drop(while: { $0 == " " || $0 == "\t" }).description
    }

    mutating func trimTrailingHorizontalWhitespace() {
        while last == " " || last == "\t" {
            removeLast()
        }
    }

    mutating func trimTrailingWhitespaceAndNewlines() {
        while last?.isWhitespace == true {
            removeLast()
        }
    }
}
