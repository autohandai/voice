import Foundation

public enum UsageAppCategory:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case communication
    case productivity
    case development
    case terminal
    case other
}

public struct UsageMetricEvent: Equatable, Sendable {
    public let wordCount: Int
    public let recordingDuration: TimeInterval
    public let processingDuration: TimeInterval
    public let insertionSucceeded: Bool
    public let cleanupChangeCount: Int
    public let vocabularyMatchCount: Int
    public let appCategory: UsageAppCategory

    public init(
        wordCount: Int,
        recordingDuration: TimeInterval,
        processingDuration: TimeInterval,
        insertionSucceeded: Bool,
        cleanupChangeCount: Int = 0,
        vocabularyMatchCount: Int = 0,
        appCategory: UsageAppCategory = .other
    ) {
        self.wordCount = wordCount
        self.recordingDuration = recordingDuration
        self.processingDuration = processingDuration
        self.insertionSucceeded = insertionSucceeded
        self.cleanupChangeCount = min(max(cleanupChangeCount, 0), 10_000)
        self.vocabularyMatchCount = min(
            max(vocabularyMatchCount, 0),
            10_000
        )
        self.appCategory = appCategory
    }
}

public struct UsageInsightDay: Codable, Equatable, Identifiable, Sendable {
    public var id: Date { day }
    public let day: Date
    public var dictationCount: Int
    public var wordCount: Int
    public var recordingDuration: TimeInterval
    public var processingDuration: TimeInterval
    public var insertionSuccessCount: Int
    public var insertionFailureCount: Int
    public var cleanupChangeCount: Int
    public var vocabularyMatchCount: Int
    public var appCategoryCounts: [UsageAppCategory: Int]

    public init(
        day: Date,
        dictationCount: Int = 0,
        wordCount: Int = 0,
        recordingDuration: TimeInterval = 0,
        processingDuration: TimeInterval = 0,
        insertionSuccessCount: Int = 0,
        insertionFailureCount: Int = 0,
        cleanupChangeCount: Int = 0,
        vocabularyMatchCount: Int = 0,
        appCategoryCounts: [UsageAppCategory: Int] = [:]
    ) {
        self.day = day
        self.dictationCount = dictationCount
        self.wordCount = wordCount
        self.recordingDuration = recordingDuration
        self.processingDuration = processingDuration
        self.insertionSuccessCount = insertionSuccessCount
        self.insertionFailureCount = insertionFailureCount
        self.cleanupChangeCount = cleanupChangeCount
        self.vocabularyMatchCount = vocabularyMatchCount
        self.appCategoryCounts = appCategoryCounts
    }

    private enum CodingKeys: String, CodingKey {
        case day
        case dictationCount
        case wordCount
        case recordingDuration
        case processingDuration
        case insertionSuccessCount
        case insertionFailureCount
        case cleanupChangeCount
        case vocabularyMatchCount
        case appCategoryCounts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            day: try container.decode(Date.self, forKey: .day),
            dictationCount: try container.decode(
                Int.self,
                forKey: .dictationCount
            ),
            wordCount: try container.decode(Int.self, forKey: .wordCount),
            recordingDuration: try container.decode(
                TimeInterval.self,
                forKey: .recordingDuration
            ),
            processingDuration: try container.decode(
                TimeInterval.self,
                forKey: .processingDuration
            ),
            insertionSuccessCount: try container.decode(
                Int.self,
                forKey: .insertionSuccessCount
            ),
            insertionFailureCount: try container.decode(
                Int.self,
                forKey: .insertionFailureCount
            ),
            cleanupChangeCount: try container.decodeIfPresent(
                Int.self,
                forKey: .cleanupChangeCount
            ) ?? 0,
            vocabularyMatchCount: try container.decodeIfPresent(
                Int.self,
                forKey: .vocabularyMatchCount
            ) ?? 0,
            appCategoryCounts: try container.decodeIfPresent(
                [UsageAppCategory: Int].self,
                forKey: .appCategoryCounts
            ) ?? [:]
        )
    }
}

public struct UsageInsightsSummary: Equatable, Sendable {
    public static let estimatedTypingWordsPerMinute = 40.0

    public let dictationCount: Int
    public let wordCount: Int
    public let recordingDuration: TimeInterval
    public let processingDuration: TimeInterval
    public let insertionSuccessCount: Int
    public let insertionFailureCount: Int
    public let cleanupChangeCount: Int
    public let vocabularyMatchCount: Int
    public let appCategoryCounts: [UsageAppCategory: Int]

    public init(days: [UsageInsightDay]) {
        dictationCount = days.reduce(0) { $0 + $1.dictationCount }
        wordCount = days.reduce(0) { $0 + $1.wordCount }
        recordingDuration = days.reduce(0) {
            $0 + $1.recordingDuration
        }
        processingDuration = days.reduce(0) {
            $0 + $1.processingDuration
        }
        insertionSuccessCount = days.reduce(0) {
            $0 + $1.insertionSuccessCount
        }
        insertionFailureCount = days.reduce(0) {
            $0 + $1.insertionFailureCount
        }
        cleanupChangeCount = days.reduce(0) {
            $0 + $1.cleanupChangeCount
        }
        vocabularyMatchCount = days.reduce(0) {
            $0 + $1.vocabularyMatchCount
        }
        appCategoryCounts = days.reduce(into: [:]) { result, day in
            for (category, count) in day.appCategoryCounts {
                result[category, default: 0] += count
            }
        }
    }

    public var averageProcessingLatency: TimeInterval {
        guard dictationCount > 0 else { return 0 }
        return processingDuration / Double(dictationCount)
    }

    public var insertionSuccessRate: Double {
        let attempts = insertionSuccessCount + insertionFailureCount
        guard attempts > 0 else { return 0 }
        return Double(insertionSuccessCount) / Double(attempts)
    }

    public var estimatedTypingTimeSaved: TimeInterval {
        let typingDuration =
            (Double(wordCount) / Self.estimatedTypingWordsPerMinute) * 60
        return max(
            0,
            typingDuration - recordingDuration - processingDuration
        )
    }

    public var wordsPerMinute: Double {
        guard recordingDuration > 0 else { return 0 }
        return Double(wordCount) / (recordingDuration / 60)
    }
}

public struct UsageInsightsStore: Sendable {
    public static let maximumDays = 366
    public static let maximumWordsPerEvent = 100_000
    public static let maximumDurationPerEvent: TimeInterval = 3_600
    private static let maximumCountPerDay = 10_000
    private static let maximumWordsPerDay = 1_000_000
    private static let maximumDurationPerDay: TimeInterval = 86_400

    public let url: URL

    public init(url: URL = Brand.usageInsightsURL) {
        self.url = url
    }

    public func load(
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> [UsageInsightDay] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let decoded = try JSONDecoder.usageInsights.decode(
            [UsageInsightDay].self,
            from: Data(contentsOf: url)
        )
        let today = calendar.startOfDay(for: now)
        let oldest = calendar.date(
            byAdding: .day,
            value: -(Self.maximumDays - 1),
            to: today
        ) ?? today
        let pruned = decoded
            .map(Self.sanitize)
            .filter { $0.day >= oldest }
            .sorted { $0.day > $1.day }
            .prefix(Self.maximumDays)
            .map { $0 }
        if pruned != decoded {
            try save(pruned)
        }
        return pruned
    }

    @discardableResult
    public func record(
        _ event: UsageMetricEvent,
        at date: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) throws -> Date {
        let day = calendar.startOfDay(for: date)
        var days = try load(now: date, calendar: calendar)
        let index: Int
        if let existing = days.firstIndex(where: { $0.day == day }) {
            index = existing
        } else {
            days.append(UsageInsightDay(day: day))
            index = days.count - 1
        }

        days[index].dictationCount = Self.adding(
            days[index].dictationCount,
            1,
            limit: Self.maximumCountPerDay
        )
        days[index].wordCount = Self.adding(
            days[index].wordCount,
            min(max(0, event.wordCount), Self.maximumWordsPerEvent),
            limit: Self.maximumWordsPerDay
        )
        days[index].recordingDuration = Self.adding(
            days[index].recordingDuration,
            Self.duration(event.recordingDuration),
            limit: Self.maximumDurationPerDay
        )
        days[index].processingDuration = Self.adding(
            days[index].processingDuration,
            Self.duration(event.processingDuration),
            limit: Self.maximumDurationPerDay
        )
        if event.insertionSucceeded {
            days[index].insertionSuccessCount = Self.adding(
                days[index].insertionSuccessCount,
                1,
                limit: Self.maximumCountPerDay
            )
        } else {
            days[index].insertionFailureCount = Self.adding(
                days[index].insertionFailureCount,
                1,
                limit: Self.maximumCountPerDay
            )
        }
        days[index].cleanupChangeCount = Self.adding(
            days[index].cleanupChangeCount,
            event.cleanupChangeCount,
            limit: Self.maximumWordsPerDay
        )
        days[index].vocabularyMatchCount = Self.adding(
            days[index].vocabularyMatchCount,
            event.vocabularyMatchCount,
            limit: Self.maximumWordsPerDay
        )
        days[index].appCategoryCounts[event.appCategory] = Self.adding(
            days[index].appCategoryCounts[event.appCategory] ?? 0,
            1,
            limit: Self.maximumCountPerDay
        )
        try save(
            days.sorted { $0.day > $1.day }
                .prefix(Self.maximumDays)
                .map { $0 }
        )
        return day
    }

    public func markInsertionSucceeded(on day: Date) throws {
        var days = try load()
        guard let index = days.firstIndex(where: { $0.day == day }) else {
            return
        }
        if days[index].insertionFailureCount > 0 {
            days[index].insertionFailureCount -= 1
        }
        days[index].insertionSuccessCount = Self.adding(
            days[index].insertionSuccessCount,
            1,
            limit: Self.maximumCountPerDay
        )
        try save(days)
    }

    public func reset() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func save(_ days: [UsageInsightDay]) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.usageInsights.encode(days)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func sanitize(_ day: UsageInsightDay) -> UsageInsightDay {
        UsageInsightDay(
            day: day.day,
            dictationCount: min(
                max(0, day.dictationCount),
                maximumCountPerDay
            ),
            wordCount: min(max(0, day.wordCount), maximumWordsPerDay),
            recordingDuration: min(
                max(0, day.recordingDuration.isFinite
                    ? day.recordingDuration : 0),
                maximumDurationPerDay
            ),
            processingDuration: min(
                max(0, day.processingDuration.isFinite
                    ? day.processingDuration : 0),
                maximumDurationPerDay
            ),
            insertionSuccessCount: min(
                max(0, day.insertionSuccessCount),
                maximumCountPerDay
            ),
            insertionFailureCount: min(
                max(0, day.insertionFailureCount),
                maximumCountPerDay
            ),
            cleanupChangeCount: min(
                max(0, day.cleanupChangeCount),
                maximumWordsPerDay
            ),
            vocabularyMatchCount: min(
                max(0, day.vocabularyMatchCount),
                maximumWordsPerDay
            ),
            appCategoryCounts: day.appCategoryCounts.reduce(into: [:]) {
                result, pair in
                result[pair.key] = min(
                    max(0, pair.value),
                    maximumCountPerDay
                )
            }
        )
    }

    private static func duration(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else { return maximumDurationPerEvent }
        return min(max(0, value), maximumDurationPerEvent)
    }

    private static func adding(
        _ lhs: Int,
        _ rhs: Int,
        limit: Int
    ) -> Int {
        let left = min(max(0, lhs), limit)
        let right = min(max(0, rhs), limit)
        return left > limit - right ? limit : left + right
    }

    private static func adding(
        _ lhs: TimeInterval,
        _ rhs: TimeInterval,
        limit: TimeInterval
    ) -> TimeInterval {
        min(limit, max(0, lhs) + max(0, rhs))
    }
}

private extension JSONEncoder {
    static var usageInsights: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var usageInsights: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
