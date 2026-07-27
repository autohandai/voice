import Foundation

public struct TextInsertionContext: Equatable, Sendable {
    public let precedingCharacter: Character?
    public let followingCharacter: Character?
    public let hasSelection: Bool
    public let isAtDocumentStart: Bool
    public let isAtDocumentEnd: Bool
    public let appBundleIdentifier: String?

    public init(
        precedingCharacter: Character? = nil,
        followingCharacter: Character? = nil,
        hasSelection: Bool = false,
        isAtDocumentStart: Bool = false,
        isAtDocumentEnd: Bool = false,
        appBundleIdentifier: String? = nil
    ) {
        self.precedingCharacter = precedingCharacter
        self.followingCharacter = followingCharacter
        self.hasSelection = hasSelection
        self.isAtDocumentStart = isAtDocumentStart
        self.isAtDocumentEnd = isAtDocumentEnd
        self.appBundleIdentifier = appBundleIdentifier
    }

    public static let unknown = TextInsertionContext()
}

public enum SmartTextFormatter {
    private static let terminalPunctuation: Set<Character> = [".", "!", "?"]
    private static let noLeadingSpace: Set<Character> = [
        ",", ".", ";", ":", "!", "?", ")", "]", "}",
    ]
    private static let openingDelimiters: Set<Character> = [
        "(", "[", "{", "\n",
    ]
    private static let noTrailingSpace: Set<Character> = [
        ",", ".", ";", ":", "!", "?", ")", "]", "}", "\n",
    ]

    public static func format(
        _ text: String,
        context: TextInsertionContext,
        enabled: Bool,
        addsTerminalPunctuation: Bool,
        locale: Locale = .current
    ) -> String {
        guard enabled, contextIsKnown(context), !text.isEmpty else {
            return text
        }

        var result = capitalizeSentences(
            text,
            capitalizesFirst: context.isAtDocumentStart
                || context.precedingCharacter.map {
                    terminalPunctuation.contains($0) || $0 == "\n"
                } == true,
            locale: locale
        )

        if addsTerminalPunctuation,
           context.isAtDocumentEnd,
           let last = result.last,
           !last.isWhitespace,
           !terminalPunctuation.contains(last) {
            result.append(".")
        }

        if needsLeadingSpace(result, context: context) {
            result.insert(" ", at: result.startIndex)
        }
        if needsTrailingSpace(result, context: context) {
            result.append(" ")
        }
        return result
    }

    private static func contextIsKnown(_ context: TextInsertionContext) -> Bool {
        context.isAtDocumentStart
            || context.isAtDocumentEnd
            || context.precedingCharacter != nil
            || context.followingCharacter != nil
            || context.hasSelection
    }

    private static func capitalizeSentences(
        _ text: String,
        capitalizesFirst: Bool,
        locale: Locale
    ) -> String {
        var output = ""
        var shouldCapitalize = capitalizesFirst
        for character in text {
            if shouldCapitalize, character.isLetter {
                output.append(
                    String(character).uppercased(with: locale)
                )
                shouldCapitalize = false
            } else {
                output.append(character)
                if !character.isWhitespace {
                    shouldCapitalize = false
                }
            }
            if terminalPunctuation.contains(character) || character == "\n" {
                shouldCapitalize = true
            }
        }
        return output
    }

    private static func needsLeadingSpace(
        _ text: String,
        context: TextInsertionContext
    ) -> Bool {
        guard
            !context.isAtDocumentStart,
            let preceding = context.precedingCharacter,
            let first = text.first,
            !preceding.isWhitespace,
            !first.isWhitespace,
            !openingDelimiters.contains(preceding),
            !noLeadingSpace.contains(first)
        else { return false }
        return true
    }

    private static func needsTrailingSpace(
        _ text: String,
        context: TextInsertionContext
    ) -> Bool {
        guard
            !context.isAtDocumentEnd,
            let following = context.followingCharacter,
            let last = text.last,
            !following.isWhitespace,
            !last.isWhitespace,
            !noTrailingSpace.contains(following),
            !openingDelimiters.contains(last)
        else { return false }
        return true
    }
}
