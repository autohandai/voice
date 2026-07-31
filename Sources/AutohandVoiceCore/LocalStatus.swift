import Foundation

public enum LocalStatusDomain:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case capture
    case model
    case shortcut
    case microphone
    case insertion
    case storage
    case sync
}

public enum LocalStatusState:
    String,
    Codable,
    Comparable,
    Sendable
{
    case healthy
    case checking
    case notEnabled = "not_enabled"
    case degraded
    case unavailable

    private var severity: Int {
        switch self {
        case .healthy: 0
        case .notEnabled: 1
        case .checking: 2
        case .degraded: 3
        case .unavailable: 4
        }
    }

    public static func < (
        lhs: LocalStatusState,
        rhs: LocalStatusState
    ) -> Bool {
        lhs.severity < rhs.severity
    }
}

public struct LocalStatusItem:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public var id: LocalStatusDomain { domain }
    public let domain: LocalStatusDomain
    public let state: LocalStatusState
    public let detail: String

    public init(
        domain: LocalStatusDomain,
        state: LocalStatusState,
        detail: String
    ) {
        self.domain = domain
        self.state = state
        self.detail = String(detail.prefix(200))
    }
}

public struct LocalStatusSnapshot:
    Codable,
    Equatable,
    Sendable
{
    public let generatedAt: Date
    public let items: [LocalStatusItem]

    public init(
        generatedAt: Date = Date(),
        items: [LocalStatusItem]
    ) {
        self.generatedAt = generatedAt
        let byDomain = Dictionary(
            grouping: items,
            by: \.domain
        ).compactMapValues(\.first)
        self.items = LocalStatusDomain.allCases.map { domain in
            byDomain[domain] ?? LocalStatusItem(
                domain: domain,
                state: .checking,
                detail: "Not checked"
            )
        }
    }

    public var overall: LocalStatusState {
        items.map(\.state).max() ?? .checking
    }
}
