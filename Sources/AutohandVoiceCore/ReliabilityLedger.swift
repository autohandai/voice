import Foundation

public enum ReliabilityEventCategory: String, Codable, CaseIterable, Sendable {
    case recordingStart = "recording_start"
    case transcription
    case insertion
    case sessionInterruption = "session_interruption"
    case sessionCrash = "session_crash"
    case modelValidation = "model_validation"
    case revision
    case recovery
}

public enum ReliabilityOutcome: String, Codable, CaseIterable, Sendable {
    case success
    case failure
    case interrupted
}

public enum ReliabilityLatencyMetric: String, Codable, CaseIterable, Sendable {
    case recordingStart = "recording_start"
    case stopToFinal = "stop_to_final"
    case insertion
}

public enum ReliabilityLatencyBucket: String, Codable, CaseIterable, Sendable {
    case under100ms = "under_100_ms"
    case under250ms = "under_250_ms"
    case under500ms = "under_500_ms"
    case under1s = "under_1_s"
    case under2s = "under_2_s"
    case under5s = "under_5_s"
    case over5s = "over_5_s"

    public init(seconds: TimeInterval) {
        let boundedSeconds = max(0, seconds.isFinite ? seconds : 5)
        switch boundedSeconds {
        case ..<0.1:
            self = .under100ms
        case ..<0.25:
            self = .under250ms
        case ..<0.5:
            self = .under500ms
        case ..<1:
            self = .under1s
        case ..<2:
            self = .under2s
        case ..<5:
            self = .under5s
        default:
            self = .over5s
        }
    }
}

public struct ReliabilityLatency: Codable, Equatable, Sendable {
    public let metric: ReliabilityLatencyMetric
    public let bucket: ReliabilityLatencyBucket

    public init(metric: ReliabilityLatencyMetric, seconds: TimeInterval) {
        self.metric = metric
        bucket = ReliabilityLatencyBucket(seconds: seconds)
    }
}

public struct ReliabilityEvent: Equatable, Sendable {
    public let category: ReliabilityEventCategory
    public let outcome: ReliabilityOutcome
    public let latency: ReliabilityLatency?
    public let modelVersion: SpeechModelVariant?
    public let supported: Bool

    public init(
        category: ReliabilityEventCategory,
        outcome: ReliabilityOutcome,
        latency: ReliabilityLatency? = nil,
        modelVersion: SpeechModelVariant? = nil,
        supported: Bool
    ) {
        self.category = category
        self.outcome = outcome
        self.latency = latency
        self.modelVersion = modelVersion
        self.supported = supported
    }
}

public enum ReliabilityPlatform: String, Codable, CaseIterable, Sendable {
    case macOSAppleSilicon = "macos_apple_silicon"
    case unsupportedMac = "unsupported_mac"
}

public struct ReliabilityCounter: Codable, Equatable, Sendable {
    public let category: ReliabilityEventCategory
    public let outcome: ReliabilityOutcome
    public var count: Int

    public init(
        category: ReliabilityEventCategory,
        outcome: ReliabilityOutcome,
        count: Int
    ) {
        self.category = category
        self.outcome = outcome
        self.count = count
    }
}

public struct ReliabilityLatencyCounter: Codable, Equatable, Sendable {
    public let metric: ReliabilityLatencyMetric
    public let bucket: ReliabilityLatencyBucket
    public var count: Int

    public init(
        metric: ReliabilityLatencyMetric,
        bucket: ReliabilityLatencyBucket,
        count: Int
    ) {
        self.metric = metric
        self.bucket = bucket
        self.count = count
    }
}

public struct ReliabilityDailyRow: Codable, Equatable, Sendable {
    public var day: Date
    public let appVersion: String
    public let modelVersion: SpeechModelVariant?
    public let policySchemaVersion: Int
    public let platform: ReliabilityPlatform
    public let supported: Bool
    public var counters: [ReliabilityCounter]
    public var latencyBuckets: [ReliabilityLatencyCounter]

    public init(
        day: Date,
        appVersion: String,
        modelVersion: SpeechModelVariant?,
        policySchemaVersion: Int,
        platform: ReliabilityPlatform,
        supported: Bool,
        counters: [ReliabilityCounter],
        latencyBuckets: [ReliabilityLatencyCounter]
    ) {
        self.day = day
        self.appVersion = appVersion
        self.modelVersion = modelVersion
        self.policySchemaVersion = policySchemaVersion
        self.platform = platform
        self.supported = supported
        self.counters = counters
        self.latencyBuckets = latencyBuckets
    }
}

public struct ReliabilitySnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: Date
    public let intervalStart: Date
    public let intervalEnd: Date
    public let rows: [ReliabilityDailyRow]

    public init(
        schemaVersion: Int,
        generatedAt: Date,
        intervalStart: Date,
        intervalEnd: Date,
        rows: [ReliabilityDailyRow]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.intervalStart = intervalStart
        self.intervalEnd = intervalEnd
        self.rows = rows
    }

    public func count(
        category: ReliabilityEventCategory,
        outcome: ReliabilityOutcome
    ) -> Int {
        rows.reduce(0) { total, row in
            total + row.counters
                .filter {
                    $0.category == category && $0.outcome == outcome
                }
                .reduce(0) { $0 + $1.count }
        }
    }

    public func latencyCount(
        metric: ReliabilityLatencyMetric,
        bucket: ReliabilityLatencyBucket
    ) -> Int {
        rows.reduce(0) { total, row in
            total + row.latencyBuckets
                .filter { $0.metric == metric && $0.bucket == bucket }
                .reduce(0) { $0 + $1.count }
        }
    }
}

public actor ReliabilityLedger {
    public static let schemaVersion = 1
    public static let policySchemaVersion = 1
    public static let maximumRows = 366
    public static let maximumCountPerBucket = 10_000
    public static let maximumAge: TimeInterval = 366 * 24 * 60 * 60
    static let maximumFileBytes: UInt64 = 512 * 1_024

    public let url: URL

    private let appVersion: String
    private let platform: ReliabilityPlatform
    private var cachedRows: [ReliabilityDailyRow]?

    public init(
        url: URL = Brand.reliabilityLedgerURL,
        appVersion: String = Brand.version,
        platform: ReliabilityPlatform = .macOSAppleSilicon
    ) {
        self.url = url
        self.appVersion = Self.sanitizeAppVersion(appVersion)
        self.platform = platform
    }

    public func record(
        _ event: ReliabilityEvent,
        at date: Date = Date()
    ) throws {
        var rows = try load(now: date)
        let day = Self.startOfDay(date)
        let rowIndex = rows.firstIndex {
            $0.day == day
                && $0.appVersion == appVersion
                && $0.modelVersion == event.modelVersion
                && $0.policySchemaVersion == Self.policySchemaVersion
                && $0.platform == platform
                && $0.supported == event.supported
        }

        if let rowIndex {
            Self.incrementCounter(
                category: event.category,
                outcome: event.outcome,
                in: &rows[rowIndex]
            )
            if let latency = event.latency {
                Self.incrementLatency(latency, in: &rows[rowIndex])
            }
        } else {
            rows.append(
                ReliabilityDailyRow(
                    day: day,
                    appVersion: appVersion,
                    modelVersion: event.modelVersion,
                    policySchemaVersion: Self.policySchemaVersion,
                    platform: platform,
                    supported: event.supported,
                    counters: [
                        ReliabilityCounter(
                            category: event.category,
                            outcome: event.outcome,
                            count: 1
                        ),
                    ],
                    latencyBuckets: event.latency.map {
                        [
                            ReliabilityLatencyCounter(
                                metric: $0.metric,
                                bucket: $0.bucket,
                                count: 1
                            ),
                        ]
                    } ?? []
                )
            )
        }

        rows = Self.sanitize(rows, now: date)
        try save(rows)
        cachedRows = rows
    }

    public func snapshot(
        _ interval: DateInterval,
        now: Date = Date()
    ) throws -> ReliabilitySnapshot {
        let rows = try load(now: now)
        let intervalStart = min(interval.start, interval.end)
        let intervalEnd = max(interval.start, interval.end)
        let startDay = Self.startOfDay(intervalStart)
        let endDay = Self.startOfDay(min(intervalEnd, now))
        let selectedRows = rows.filter {
            $0.day >= startDay && $0.day <= endDay
        }

        return ReliabilitySnapshot(
            schemaVersion: Self.schemaVersion,
            generatedAt: now,
            intervalStart: intervalStart,
            intervalEnd: intervalEnd,
            rows: selectedRows
        )
    }

    public func exportRedacted(now: Date = Date()) throws -> Data {
        let snapshot = try snapshot(
            DateInterval(
                start: now.addingTimeInterval(-Self.maximumAge),
                end: now
            ),
            now: now
        )
        return try Self.encoder.encode(snapshot)
    }

    public func reset() throws {
        cachedRows = []
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }

    private func load(now: Date) throws -> [ReliabilityDailyRow] {
        if let cachedRows {
            let sanitized = Self.sanitize(cachedRows, now: now)
            if sanitized != cachedRows {
                try save(sanitized)
                self.cachedRows = sanitized
            }
            return sanitized
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            cachedRows = []
            return []
        }

        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        if let size = attributes[.size] as? NSNumber,
           size.uint64Value > Self.maximumFileBytes {
            try save([])
            cachedRows = []
            return []
        }

        let file: ReliabilityLedgerFile
        do {
            file = try Self.decoder.decode(
                ReliabilityLedgerFile.self,
                from: Data(contentsOf: url)
            )
        } catch {
            try save([])
            cachedRows = []
            return []
        }

        guard file.schemaVersion == Self.schemaVersion else {
            try save([])
            cachedRows = []
            return []
        }

        let sanitized = Self.sanitize(file.rows, now: now)
        if sanitized != file.rows {
            try save(sanitized)
        }
        cachedRows = sanitized
        return sanitized
    }

    private func save(_ rows: [ReliabilityDailyRow]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let file = ReliabilityLedgerFile(
            schemaVersion: Self.schemaVersion,
            rows: rows
        )
        try Self.encoder.encode(file).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    private static func sanitize(
        _ rows: [ReliabilityDailyRow],
        now: Date
    ) -> [ReliabilityDailyRow] {
        let today = startOfDay(now)
        let oldestAllowed = startOfDay(
            now.addingTimeInterval(-maximumAge)
        )
        var merged: [ReliabilityRowKey: ReliabilityDailyRow] = [:]

        for row in rows {
            let day = min(startOfDay(row.day), today)
            guard day >= oldestAllowed else {
                continue
            }

            let key = ReliabilityRowKey(
                day: day,
                appVersion: sanitizeAppVersion(row.appVersion),
                modelVersion: row.modelVersion,
                policySchemaVersion: min(
                    max(row.policySchemaVersion, 1),
                    policySchemaVersion
                ),
                platform: row.platform,
                supported: row.supported
            )
            var normalized = ReliabilityDailyRow(
                day: key.day,
                appVersion: key.appVersion,
                modelVersion: key.modelVersion,
                policySchemaVersion: key.policySchemaVersion,
                platform: key.platform,
                supported: key.supported,
                counters: sanitizeCounters(row.counters),
                latencyBuckets: sanitizeLatencyCounters(row.latencyBuckets)
            )
            guard
                !normalized.counters.isEmpty
                    || !normalized.latencyBuckets.isEmpty
            else {
                continue
            }

            if var existing = merged[key] {
                for counter in normalized.counters {
                    merge(counter, into: &existing)
                }
                for latency in normalized.latencyBuckets {
                    merge(latency, into: &existing)
                }
                normalized = existing
            }
            merged[key] = normalized
        }

        return merged.values
            .sorted(by: rowSort)
            .prefix(maximumRows)
            .map { $0 }
    }

    private static func sanitizeCounters(
        _ counters: [ReliabilityCounter]
    ) -> [ReliabilityCounter] {
        var result: [ReliabilityCounterKey: Int] = [:]
        for counter in counters {
            let key = ReliabilityCounterKey(
                category: counter.category,
                outcome: counter.outcome
            )
            result[key] = min(
                maximumCountPerBucket,
                (result[key] ?? 0)
                    + min(max(counter.count, 1), maximumCountPerBucket)
            )
        }
        return result.map {
            ReliabilityCounter(
                category: $0.key.category,
                outcome: $0.key.outcome,
                count: $0.value
            )
        }.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.outcome.rawValue < $1.outcome.rawValue
        }
    }

    private static func sanitizeLatencyCounters(
        _ counters: [ReliabilityLatencyCounter]
    ) -> [ReliabilityLatencyCounter] {
        var result: [ReliabilityLatencyCounterKey: Int] = [:]
        for counter in counters {
            let key = ReliabilityLatencyCounterKey(
                metric: counter.metric,
                bucket: counter.bucket
            )
            result[key] = min(
                maximumCountPerBucket,
                (result[key] ?? 0)
                    + min(max(counter.count, 1), maximumCountPerBucket)
            )
        }
        return result.map {
            ReliabilityLatencyCounter(
                metric: $0.key.metric,
                bucket: $0.key.bucket,
                count: $0.value
            )
        }.sorted {
            if $0.metric != $1.metric {
                return $0.metric.rawValue < $1.metric.rawValue
            }
            return $0.bucket.rawValue < $1.bucket.rawValue
        }
    }

    private static func incrementCounter(
        category: ReliabilityEventCategory,
        outcome: ReliabilityOutcome,
        in row: inout ReliabilityDailyRow
    ) {
        if let index = row.counters.firstIndex(where: {
            $0.category == category && $0.outcome == outcome
        }) {
            row.counters[index].count = min(
                maximumCountPerBucket,
                row.counters[index].count + 1
            )
        } else {
            row.counters.append(
                ReliabilityCounter(
                    category: category,
                    outcome: outcome,
                    count: 1
                )
            )
        }
    }

    private static func incrementLatency(
        _ latency: ReliabilityLatency,
        in row: inout ReliabilityDailyRow
    ) {
        if let index = row.latencyBuckets.firstIndex(where: {
            $0.metric == latency.metric && $0.bucket == latency.bucket
        }) {
            row.latencyBuckets[index].count = min(
                maximumCountPerBucket,
                row.latencyBuckets[index].count + 1
            )
        } else {
            row.latencyBuckets.append(
                ReliabilityLatencyCounter(
                    metric: latency.metric,
                    bucket: latency.bucket,
                    count: 1
                )
            )
        }
    }

    private static func merge(
        _ counter: ReliabilityCounter,
        into row: inout ReliabilityDailyRow
    ) {
        if let index = row.counters.firstIndex(where: {
            $0.category == counter.category && $0.outcome == counter.outcome
        }) {
            row.counters[index].count = min(
                maximumCountPerBucket,
                row.counters[index].count + counter.count
            )
        } else {
            row.counters.append(counter)
        }
    }

    private static func merge(
        _ counter: ReliabilityLatencyCounter,
        into row: inout ReliabilityDailyRow
    ) {
        if let index = row.latencyBuckets.firstIndex(where: {
            $0.metric == counter.metric && $0.bucket == counter.bucket
        }) {
            row.latencyBuckets[index].count = min(
                maximumCountPerBucket,
                row.latencyBuckets[index].count + counter.count
            )
        } else {
            row.latencyBuckets.append(counter)
        }
    }

    private static func rowSort(
        _ left: ReliabilityDailyRow,
        _ right: ReliabilityDailyRow
    ) -> Bool {
        if left.day != right.day {
            return left.day > right.day
        }
        if left.appVersion != right.appVersion {
            return left.appVersion < right.appVersion
        }
        if left.modelVersion != right.modelVersion {
            return (left.modelVersion?.rawValue ?? "")
                < (right.modelVersion?.rawValue ?? "")
        }
        if left.platform != right.platform {
            return left.platform.rawValue < right.platform.rawValue
        }
        return left.supported && !right.supported
    }

    private static func startOfDay(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.startOfDay(for: date)
    }

    private static func sanitizeAppVersion(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: ".-+_")
        )
        let scalars = value.unicodeScalars
            .filter { allowed.contains($0) }
            .prefix(32)
        let sanitized = String(String.UnicodeScalarView(scalars))
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ReliabilityLedgerFile: Codable {
    let schemaVersion: Int
    let rows: [ReliabilityDailyRow]
}

private struct ReliabilityRowKey: Hashable {
    let day: Date
    let appVersion: String
    let modelVersion: SpeechModelVariant?
    let policySchemaVersion: Int
    let platform: ReliabilityPlatform
    let supported: Bool
}

private struct ReliabilityCounterKey: Hashable {
    let category: ReliabilityEventCategory
    let outcome: ReliabilityOutcome
}

private struct ReliabilityLatencyCounterKey: Hashable {
    let metric: ReliabilityLatencyMetric
    let bucket: ReliabilityLatencyBucket
}
