import Foundation
import XCTest
@testable import AutohandVoiceCore

final class NotificationPolicyTests: XCTestCase {
    func testEventDeduplicatesActionsWithoutChangingOrder() {
        let event = VoiceNotificationEvent(
            category: .completion,
            title: "Done",
            body: "Ready",
            deduplicationKey: "done",
            actions: [.openHistory, .copyLast, .openHistory]
        )

        XCTAssertEqual(event.actions, [.openHistory, .copyLast])
    }

    func testOperationalFailureRemainsInAppWhenSystemIsMuted() async {
        let policy = NotificationPolicy()
        let disposition = await policy.handle(
            VoiceNotificationEvent(
                category: .failures,
                title: "Insertion failed",
                body: "Copy or retry the final transcript.",
                deduplicationKey: "insertion.failed"
            ),
            preferences: VoiceNotificationPreferences(
                systemNotificationsEnabled: false,
                mutedCategories: [.failures]
            )
        )

        XCTAssertEqual(disposition, .inAppOnly)
    }

    func testNonOperationalMutedEventIsNotDelivered() async {
        let policy = NotificationPolicy()
        let disposition = await policy.handle(
            VoiceNotificationEvent(
                category: .education,
                title: "Tip",
                body: "Try a local style.",
                deduplicationKey: "education.style"
            ),
            preferences: VoiceNotificationPreferences(
                systemNotificationsEnabled: true,
                mutedCategories: [.education]
            )
        )

        XCTAssertEqual(disposition, .muted)
    }

    func testDuplicateEventsCoalesceWithinBoundedWindow() async {
        let policy = NotificationPolicy(coalescingWindow: 60)
        let date = Date(timeIntervalSince1970: 1_000)
        let event = VoiceNotificationEvent(
            category: .recovery,
            title: "Recovery ready",
            body: "Captured audio can be recovered locally.",
            deduplicationKey: "recovery.ready",
            occurredAt: date
        )
        let preferences = VoiceNotificationPreferences(
            systemNotificationsEnabled: true,
            mutedCategories: []
        )

        _ = await policy.handle(event, preferences: preferences)
        let duplicate = await policy.handle(
            VoiceNotificationEvent(
                category: .recovery,
                title: event.title,
                body: event.body,
                deduplicationKey: event.deduplicationKey,
                occurredAt: date.addingTimeInterval(5)
            ),
            preferences: preferences
        )

        XCTAssertEqual(duplicate, .duplicate)
    }

    func testNotificationActionAcknowledgementIsIdempotent() async {
        let policy = NotificationPolicy()

        let first = await policy.acknowledge(
            notificationID: "event",
            action: .copyLast
        )
        let second = await policy.acknowledge(
            notificationID: "event",
            action: .copyLast
        )

        XCTAssertTrue(first)
        XCTAssertFalse(second)
    }

    func testDeepLinksResolveExistingOrExpiredItems() {
        let historyID = UUID()
        let recoveryID = UUID()

        XCTAssertEqual(
            VoiceDeepLinkResolver.resolve(
                "autohand-voice://history/\(historyID.uuidString)",
                existingHistoryIDs: [historyID],
                existingRecoveryIDs: []
            ),
            .history(historyID)
        )
        XCTAssertEqual(
            VoiceDeepLinkResolver.resolve(
                "autohand-voice://recovery/\(recoveryID.uuidString)",
                existingHistoryIDs: [],
                existingRecoveryIDs: []
            ),
            .expired
        )
        XCTAssertEqual(
            VoiceDeepLinkResolver.resolve(
                "https://example.com/\(historyID.uuidString)",
                existingHistoryIDs: [historyID],
                existingRecoveryIDs: []
            ),
            .invalid
        )
    }
}
