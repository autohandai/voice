import Foundation

public enum OperationalIssueKind: String, Codable, CaseIterable, Sendable {
    case microphone
    case accessibility
    case shortcut
    case model
    case transcription
    case insertion
    case storage
    case settings
    case lifecycle
    case runtime

    public var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .shortcut: "Keyboard shortcut"
        case .model: "Local speech model"
        case .transcription: "Local transcription"
        case .insertion: "Text insertion"
        case .storage: "Local storage"
        case .settings: "Settings"
        case .lifecycle: "Sleep or wake"
        case .runtime: "App runtime"
        }
    }
}

public struct OperationalIssue: Codable, Equatable, Identifiable, Sendable {
    public var id: OperationalIssueKind { kind }
    public let kind: OperationalIssueKind
    public var firstSeenAt: Date
    public var lastSeenAt: Date
    public var count: Int

    public init(
        kind: OperationalIssueKind,
        firstSeenAt: Date,
        lastSeenAt: Date,
        count: Int
    ) {
        self.kind = kind
        self.firstSeenAt = firstSeenAt
        self.lastSeenAt = lastSeenAt
        self.count = count
    }
}

public struct OperationalIssueStore: Sendable {
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
    public static let maximumCount = 9_999
    static let maximumFileBytes: UInt64 = 64 * 1_024

    public let url: URL

    public init(url: URL = Brand.operationalIssuesURL) {
        self.url = url
    }

    public func load(now: Date = Date()) throws -> [OperationalIssue] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        if let size = attributes[.size] as? NSNumber,
           size.uint64Value > Self.maximumFileBytes {
            try save([])
            return []
        }
        let decoded: [OperationalIssue]
        do {
            decoded = try JSONDecoder.operationalIssues.decode(
                [OperationalIssue].self,
                from: Data(contentsOf: url)
            )
        } catch {
            try save([])
            return []
        }
        let sanitized = Self.sanitize(decoded, now: now)
        if sanitized != decoded {
            try save(sanitized)
        }
        return sanitized
    }

    public func record(
        _ kind: OperationalIssueKind,
        at date: Date = Date()
    ) throws {
        var issues = try load(now: date)
        if let index = issues.firstIndex(where: { $0.kind == kind }) {
            issues[index].firstSeenAt = min(
                issues[index].firstSeenAt,
                date
            )
            issues[index].lastSeenAt = date
            issues[index].count = min(
                Self.maximumCount,
                issues[index].count + 1
            )
        } else {
            issues.append(
                OperationalIssue(
                    kind: kind,
                    firstSeenAt: date,
                    lastSeenAt: date,
                    count: 1
                )
            )
        }
        try save(Self.sanitize(issues, now: date))
    }

    public func reset() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func sanitize(
        _ issues: [OperationalIssue],
        now: Date
    ) -> [OperationalIssue] {
        let oldestAllowed = now.addingTimeInterval(-maximumAge)
        var byKind: [OperationalIssueKind: OperationalIssue] = [:]
        for issue in issues {
            let lastSeen = min(issue.lastSeenAt, now)
            guard lastSeen >= oldestAllowed else { continue }
            let firstSeen = min(
                max(issue.firstSeenAt, oldestAllowed),
                lastSeen
            )
            let normalized = OperationalIssue(
                kind: issue.kind,
                firstSeenAt: firstSeen,
                lastSeenAt: lastSeen,
                count: min(max(issue.count, 1), maximumCount)
            )
            if let existing = byKind[issue.kind] {
                byKind[issue.kind] = OperationalIssue(
                    kind: issue.kind,
                    firstSeenAt: min(existing.firstSeenAt, firstSeen),
                    lastSeenAt: max(existing.lastSeenAt, lastSeen),
                    count: min(
                        maximumCount,
                        existing.count + normalized.count
                    )
                )
            } else {
                byKind[issue.kind] = normalized
            }
        }
        return byKind.values.sorted { left, right in
            if left.lastSeenAt != right.lastSeenAt {
                return left.lastSeenAt > right.lastSeenAt
            }
            return left.kind.rawValue < right.kind.rawValue
        }
    }

    private func save(_ issues: [OperationalIssue]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(issues).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

private extension JSONDecoder {
    static var operationalIssues: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
