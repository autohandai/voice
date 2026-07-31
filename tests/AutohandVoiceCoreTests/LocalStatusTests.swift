import Foundation
import XCTest
@testable import AutohandVoiceCore

final class LocalStatusTests: XCTestCase {
    func testSnapshotHasEveryFiniteDomainAndWorstOverallState() {
        let snapshot = LocalStatusSnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_000),
            items: [
                LocalStatusItem(
                    domain: .capture,
                    state: .healthy,
                    detail: "Ready"
                ),
                LocalStatusItem(
                    domain: .model,
                    state: .unavailable,
                    detail: "Missing"
                ),
            ]
        )

        XCTAssertEqual(snapshot.items.count, LocalStatusDomain.allCases.count)
        XCTAssertEqual(snapshot.overall, .unavailable)
        XCTAssertEqual(
            snapshot.items.first(where: { $0.domain == .sync })?.state,
            .checking
        )
    }
}
