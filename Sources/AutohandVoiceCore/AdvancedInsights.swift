import Foundation

public enum UsageAppCategoryClassifier {
    public static func classify(
        bundleIdentifier: String?
    ) -> UsageAppCategory {
        guard let identifier = bundleIdentifier?.lowercased() else {
            return .other
        }
        if [
            "com.apple.terminal",
            "com.googlecode.iterm2",
            "dev.warp.warp-stable",
        ].contains(identifier) {
            return .terminal
        }
        if identifier.contains("xcode")
            || identifier.contains("visualstudio")
            || identifier.contains("zed")
            || identifier.contains("cursor") {
            return .development
        }
        if identifier.contains("slack")
            || identifier.contains("mail")
            || identifier.contains("messages")
            || identifier.contains("discord")
            || identifier.contains("teams") {
            return .communication
        }
        if identifier.contains("notes")
            || identifier.contains("notion")
            || identifier.contains("obsidian")
            || identifier.contains("pages") {
            return .productivity
        }
        return .other
    }
}

public struct UsageStreak: Equatable, Sendable {
    public let currentDays: Int
    public let longestDays: Int
    public let activeDays: Set<Date>

    public init(
        days: [UsageInsightDay],
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) {
        let normalized = Set(days.filter {
            $0.dictationCount > 0
        }.map {
            calendar.startOfDay(for: $0.day)
        })
        activeDays = normalized
        let ordered = normalized.sorted()
        var longest = 0
        var run = 0
        var previous: Date?
        for day in ordered {
            if let previous,
               calendar.date(byAdding: .day, value: 1, to: previous) == day {
                run += 1
            } else {
                run = 1
            }
            longest = max(longest, run)
            previous = day
        }
        longestDays = longest
        let today = calendar.startOfDay(for: now)
        let start = normalized.contains(today)
            ? today
            : calendar.date(byAdding: .day, value: -1, to: today) ?? today
        var current = 0
        var cursor = start
        while normalized.contains(cursor) {
            current += 1
            guard let prior = calendar.date(
                byAdding: .day,
                value: -1,
                to: cursor
            ) else { break }
            cursor = prior
        }
        currentDays = current
    }
}

public struct LocalVoiceProfile: Equatable, Sendable {
    public let retainedWordCount: Int
    public let mostCorrectedTerms: [String]
    public let activeHours: [Int]
    public let methodDescription: String
}

public enum LocalVoiceProfileResult: Equatable, Sendable {
    case insufficientWords(current: Int, required: Int)
    case available(LocalVoiceProfile)
}

public enum LocalVoiceProfileAnalyzer {
    public static let minimumRetainedWords = 2_000

    public static func analyze(
        _ entries: [HistoryEntry],
        calendar: Calendar = .autoupdatingCurrent
    ) -> LocalVoiceProfileResult {
        let words = entries.reduce(0) {
            $0 + $1.text.split(whereSeparator: \.isWhitespace).count
        }
        guard words >= minimumRetainedWords else {
            return .insufficientWords(
                current: words,
                required: minimumRetainedWords
            )
        }
        var corrections: [String: Int] = [:]
        for entry in entries {
            guard
                let raw = entry.rawFinal?.text,
                let revised = entry.revision?.text
            else { continue }
            let revisedTokens = Set(tokens(revised))
            for token in tokens(raw) where !revisedTokens.contains(token) {
                corrections[token, default: 0] += 1
            }
        }
        let corrected = corrections.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }.prefix(8).map(\.key)
        let hourCounts = Dictionary(
            grouping: entries.map {
                calendar.component(.hour, from: $0.createdAt)
            },
            by: { $0 }
        ).mapValues(\.count)
        let hours = hourCounts.sorted {
            if $0.value != $1.value {
                return $0.value > $1.value
            }
            return $0.key < $1.key
        }.prefix(4).map(\.key)
        return .available(
            LocalVoiceProfile(
                retainedWordCount: words,
                mostCorrectedTerms: corrected,
                activeHours: hours,
                methodDescription:
                    "Deterministic local counts from retained final and raw revision text."
            )
        )
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

public struct InsightsShareCard:
    Codable,
    Equatable,
    Sendable
{
    public let wordCount: Int
    public let dictationCount: Int
    public let wordsPerMinute: Double
    public let currentStreakDays: Int
    public let generatedAt: Date

    public init(
        summary: UsageInsightsSummary,
        streak: UsageStreak,
        generatedAt: Date = Date()
    ) {
        wordCount = summary.wordCount
        dictationCount = summary.dictationCount
        wordsPerMinute = min(max(summary.wordsPerMinute, 0), 1_000)
        currentStreakDays = streak.currentDays
        self.generatedAt = generatedAt
    }
}
