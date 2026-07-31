import Foundation

public enum VoiceNotificationCategory:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case failures
    case recovery
    case modelReadiness = "model_readiness"
    case permissions
    case formatting
    case education
    case milestones
    case completion

    public var isOperational: Bool {
        switch self {
        case .failures, .recovery, .modelReadiness, .permissions:
            true
        case .formatting, .education, .milestones, .completion:
            false
        }
    }
}

public struct VoiceNotificationPreferences:
    Codable,
    Equatable,
    Sendable
{
    public var systemNotificationsEnabled: Bool
    public var mutedCategories: Set<VoiceNotificationCategory>

    public init(
        systemNotificationsEnabled: Bool = false,
        mutedCategories: Set<VoiceNotificationCategory> = [
            .education,
            .milestones,
        ]
    ) {
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.mutedCategories = mutedCategories
    }
}

public enum VoiceNotificationAction:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case copyLast = "copy_last"
    case recover
    case openSettings = "open_settings"
    case openHistory = "open_history"
}

public struct VoiceNotificationEvent:
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let category: VoiceNotificationCategory
    public let title: String
    public let body: String
    public let deduplicationKey: String
    public let deepLink: String?
    public let actions: [VoiceNotificationAction]
    public let occurredAt: Date
    public let requiresInAppSurface: Bool

    public init(
        id: UUID = UUID(),
        category: VoiceNotificationCategory,
        title: String,
        body: String,
        deduplicationKey: String,
        deepLink: String? = nil,
        actions: [VoiceNotificationAction] = [],
        occurredAt: Date = Date(),
        requiresInAppSurface: Bool? = nil
    ) {
        self.id = id
        self.category = category
        self.title = String(title.prefix(120))
        self.body = String(body.prefix(500))
        self.deduplicationKey = String(deduplicationKey.prefix(128))
        self.deepLink = deepLink.map { String($0.prefix(500)) }
        var seen = Set<VoiceNotificationAction>()
        self.actions = actions.filter {
            seen.insert($0).inserted
        }
        self.occurredAt = occurredAt
        self.requiresInAppSurface =
            requiresInAppSurface ?? category.isOperational
    }
}

public struct SystemVoiceNotification:
    Equatable,
    Sendable
{
    public let identifier: String
    public let category: VoiceNotificationCategory
    public let title: String
    public let body: String
    public let deepLink: String?
    public let actions: [VoiceNotificationAction]
}

public enum NotificationDisposition: Equatable, Sendable {
    case system(SystemVoiceNotification, alsoInApp: Bool)
    case inAppOnly
    case muted
    case duplicate
}

public actor NotificationPolicy {
    public static let defaultCoalescingWindow: TimeInterval = 60
    private let coalescingWindow: TimeInterval
    private var lastDeliveryByKey: [String: Date] = [:]
    private var acknowledgedActions: Set<String> = []

    public init(
        coalescingWindow: TimeInterval =
            NotificationPolicy.defaultCoalescingWindow
    ) {
        self.coalescingWindow = min(
            max(coalescingWindow, 1),
            10 * 60
        )
    }

    public func handle(
        _ event: VoiceNotificationEvent,
        preferences: VoiceNotificationPreferences
    ) -> NotificationDisposition {
        prune(now: event.occurredAt)
        if let last = lastDeliveryByKey[event.deduplicationKey],
           event.occurredAt.timeIntervalSince(last) < coalescingWindow {
            return .duplicate
        }
        lastDeliveryByKey[event.deduplicationKey] = event.occurredAt
        let isMuted = preferences.mutedCategories.contains(event.category)
        if isMuted {
            return event.requiresInAppSurface ? .inAppOnly : .muted
        }
        guard preferences.systemNotificationsEnabled else {
            return event.requiresInAppSurface ? .inAppOnly : .muted
        }
        return .system(
            SystemVoiceNotification(
                identifier: event.id.uuidString,
                category: event.category,
                title: event.title,
                body: event.body,
                deepLink: event.deepLink,
                actions: event.actions
            ),
            alsoInApp: event.requiresInAppSurface
        )
    }

    public func acknowledge(
        notificationID: String,
        action: VoiceNotificationAction
    ) -> Bool {
        let key = String(
            "\(notificationID):\(action.rawValue)".prefix(256)
        )
        guard acknowledgedActions.insert(key).inserted else {
            return false
        }
        if acknowledgedActions.count > 256 {
            acknowledgedActions.removeAll(keepingCapacity: true)
            acknowledgedActions.insert(key)
        }
        return true
    }

    private func prune(now: Date) {
        lastDeliveryByKey = lastDeliveryByKey.filter {
            now.timeIntervalSince($0.value) < coalescingWindow
                && now >= $0.value
        }
        if lastDeliveryByKey.count > 128 {
            lastDeliveryByKey = Dictionary(
                uniqueKeysWithValues: lastDeliveryByKey
                    .sorted { $0.value > $1.value }
                    .prefix(128)
                    .map { ($0.key, $0.value) }
            )
        }
    }
}

public enum VoiceDeepLinkTarget: Equatable, Sendable {
    case history(UUID)
    case recovery(UUID)
    case expired
    case invalid
}

public enum VoiceDeepLinkResolver {
    public static func resolve(
        _ value: String,
        existingHistoryIDs: Set<UUID>,
        existingRecoveryIDs: Set<UUID>
    ) -> VoiceDeepLinkTarget {
        guard
            let components = URLComponents(string: value),
            components.scheme == "autohand-voice",
            let host = components.host,
            let idString = components.path.split(separator: "/").first,
            let id = UUID(uuidString: String(idString))
        else {
            return .invalid
        }
        switch host {
        case "history":
            return existingHistoryIDs.contains(id) ? .history(id) : .expired
        case "recovery":
            return existingRecoveryIDs.contains(id) ? .recovery(id) : .expired
        default:
            return .invalid
        }
    }
}
