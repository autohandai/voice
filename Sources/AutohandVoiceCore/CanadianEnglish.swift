import Foundation

public enum EnglishSpellingPolicy:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case automatic
    case canadian

    public var displayName: String {
        switch self {
        case .automatic: "System Default"
        case .canadian: "Canadian English"
        }
    }
}

public enum CanadianEnglishRecommendationResponse:
    String,
    Codable,
    Sendable
{
    case notPresented = "not_presented"
    case dismissed
    case accepted
}

public enum CanadianEnglishRecommendation {
    public static func shouldPresent(
        locale: Locale,
        dictationLanguageCode: String,
        modelSupportsEnglish: Bool,
        response: CanadianEnglishRecommendationResponse
    ) -> Bool {
        response == .notPresented
            && modelSupportsEnglish
            && dictationLanguageCode == "en"
            && locale.language.languageCode?.identifier == "en"
            && locale.region?.identifier == "CA"
    }
}

public enum CanadianEnglishFormatter {
    private static let replacements: [String: String] = [
        "behavior": "behaviour",
        "behaviors": "behaviours",
        "canceled": "cancelled",
        "canceling": "cancelling",
        "center": "centre",
        "centered": "centred",
        "centering": "centring",
        "centers": "centres",
        "color": "colour",
        "colored": "coloured",
        "coloring": "colouring",
        "colors": "colours",
        "defense": "defence",
        "favorite": "favourite",
        "favorites": "favourites",
        "honor": "honour",
        "honored": "honoured",
        "honoring": "honouring",
        "honors": "honours",
        "neighbor": "neighbour",
        "neighborhood": "neighbourhood",
        "neighborhoods": "neighbourhoods",
        "neighbors": "neighbours",
        "offense": "offence",
        "theater": "theatre",
        "theaters": "theatres",
        "traveled": "travelled",
        "traveler": "traveller",
        "travelers": "travellers",
        "traveling": "travelling",
    ]

    public static func apply(
        to text: String,
        policy: EnglishSpellingPolicy,
        languageCode: String
    ) -> String {
        guard policy == .canadian, languageCode == "en" else {
            return text
        }
        let alternation = replacements.keys
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern)
            .joined(separator: "|")
        guard let expression = try? NSRegularExpression(
            pattern: #"\b("# + alternation + #")\b"#,
            options: [.caseInsensitive]
        ) else {
            return text
        }
        var result = text
        let matches = expression.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        )
        for match in matches.reversed() {
            guard
                let range = Range(match.range, in: result)
            else { continue }
            let source = String(result[range])
            guard let replacement = replacements[source.lowercased()] else {
                continue
            }
            result.replaceSubrange(
                range,
                with: preservingCase(replacement, source: source)
            )
        }
        return result
    }

    private static func preservingCase(
        _ replacement: String,
        source: String
    ) -> String {
        if source == source.uppercased() {
            return replacement.uppercased()
        }
        if source.first?.isUppercase == true {
            return replacement.prefix(1).uppercased()
                + replacement.dropFirst()
        }
        return replacement
    }
}
