import Foundation

public enum SpeechTextRefiner {
    private static let fillerAlternatives = "um+|uh+|erm+|hmm+"
    private static let emphasizedRepetitions: Set<String> = [
        "again", "bye", "had", "never", "no", "really", "so", "very", "yes",
    ]

    public static func refine(
        _ text: String,
        enabled: Bool,
        locale: Locale = .current
    ) -> String {
        guard enabled, text.contains(where: { !$0.isWhitespace }) else {
            return text
        }

        var result = removeHighConfidenceFillers(from: text)
        result = collapseRepeatedPhrases(in: result)
        result = collapseRepeatedWords(in: result, locale: locale)
        return normalizeSpacing(in: result)
    }

    private static func removeHighConfidenceFillers(
        from text: String
    ) -> String {
        var result = replacing(
            pattern: "(?i)\\s*[,;:]\\s*(?:\(fillerAlternatives))"
                + "\\s*[,;:]?\\s*",
            in: text,
            with: " "
        )
        result = replacing(
            pattern: "(?i)^\\s*(?:\(fillerAlternatives))"
                + "\\s*[,;:]?\\s*",
            in: result,
            with: ""
        )
        result = replacing(
            pattern: "(?i)(?<![\\p{L}\\p{N}])"
                + "(?:\(fillerAlternatives))"
                + "(?![\\p{L}\\p{N}])",
            in: result,
            with: ""
        )
        return replacing(
            pattern: "(?i)\\s*,\\s*(?:you know|I mean)\\s*,\\s*",
            in: result,
            with: " "
        )
    }

    private static func collapseRepeatedPhrases(in text: String) -> String {
        let pattern = "(?i)(?<![\\p{L}\\p{N}])"
            + "([\\p{L}\\p{N}'’-]+"
            + "(?:\\s+[\\p{L}\\p{N}'’-]+){1,4})"
            + "(?:\\s+|\\s*,\\s*)\\1"
            + "(?![\\p{L}\\p{N}])"
        var result = text
        for _ in 0..<4 {
            let collapsed = replacing(pattern: pattern, in: result, with: "$1")
            guard collapsed != result else { break }
            result = collapsed
        }
        return result
    }

    private static func collapseRepeatedWords(
        in text: String,
        locale: Locale
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: "(?i)(?<![\\p{L}\\p{N}])"
                + "([\\p{L}\\p{N}'’-]{2,})\\s+\\1"
                + "(?![\\p{L}\\p{N}])"
        ) else {
            return text
        }
        let original = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: original.length)
        )
        let output = NSMutableString(string: text)
        for match in matches.reversed() {
            let word = original.substring(with: match.range(at: 1))
            guard !emphasizedRepetitions.contains(
                word.lowercased(with: locale)
            ) else {
                continue
            }
            output.replaceCharacters(in: match.range, with: word)
        }
        return output as String
    }

    private static func normalizeSpacing(in text: String) -> String {
        var result = replacing(
            pattern: "[\\t ]+",
            in: text,
            with: " "
        )
        result = replacing(
            pattern: "[\\t ]+([,.;:!?])",
            in: result,
            with: "$1"
        )
        result = replacing(
            pattern: "([,;:])(?=\\S)",
            in: result,
            with: "$1 "
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(
        pattern: String,
        in text: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(
            pattern: pattern
        ) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: replacement
        )
    }
}
