import Foundation
import XCTest

final class WisprPlanCoverageTests: XCTestCase {
    private let expectedFamilyCount = 55

    func testPlanDocumentsCoverEverySourceFamilyExactlyWhereRequired() throws {
        let inventory = try sourceIDs(
            in: planURL("wispr-flow-source-inventory.md"),
            matchingLinesWithPrefix: "#### `WF-"
        )
        let product = try allSourceIDs(in: planURL("wispr-flow-parity-product-spec.md"))
        let delivery = try sourceIDs(
            in: planURL("wispr-flow-parity-delivery-plan.md"),
            matchingLinesWithPrefix: "| `WF-"
        )

        XCTAssertEqual(inventory.count, expectedFamilyCount)
        XCTAssertEqual(Set(inventory).count, inventory.count, "Inventory definitions must be unique")
        XCTAssertEqual(delivery.count, expectedFamilyCount)
        XCTAssertEqual(Set(delivery).count, delivery.count, "Delivery rows must be unique")
        XCTAssertEqual(Set(product), Set(inventory), "Product spec must reference every canonical ID")
        XCTAssertEqual(Set(delivery), Set(inventory), "Delivery plan must cover every canonical ID")
    }

    func testCoverageAuditRejectsDuplicateCanonicalIDs() {
        let violations = coverageViolations(
            inventory: ["WF-01", "WF-01"],
            product: ["WF-01"],
            delivery: ["WF-01"]
        )

        XCTAssertTrue(violations.contains("duplicate inventory IDs"))
    }

    func testCoverageAuditRejectsMissingProductIDs() {
        let violations = coverageViolations(
            inventory: ["WF-01", "WF-02"],
            product: ["WF-01"],
            delivery: ["WF-01", "WF-02"]
        )

        XCTAssertTrue(violations.contains("product coverage differs from inventory"))
    }

    private func coverageViolations(
        inventory: [String],
        product: [String],
        delivery: [String]
    ) -> Set<String> {
        var violations = Set<String>()

        if inventory.count != Set(inventory).count {
            violations.insert("duplicate inventory IDs")
        }
        if delivery.count != Set(delivery).count {
            violations.insert("duplicate delivery IDs")
        }
        if Set(product) != Set(inventory) {
            violations.insert("product coverage differs from inventory")
        }
        if Set(delivery) != Set(inventory) {
            violations.insert("delivery coverage differs from inventory")
        }

        return violations
    }

    private func planURL(_ name: String) -> URL {
        repositoryRoot()
            .appendingPathComponent("docs", isDirectory: true)
            .appendingPathComponent("plans", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceIDs(
        in url: URL,
        matchingLinesWithPrefix prefix: String
    ) throws -> [String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix(prefix) }
            .compactMap { firstSourceID(in: String($0)) }
    }

    private func allSourceIDs(in url: URL) throws -> [String] {
        let contents = try String(contentsOf: url, encoding: .utf8)
        let expression = try NSRegularExpression(
            pattern: #"\bWF-\d{8}-(?:DESKTOP|ANDROID|IOS)-\d{2}\b"#
        )
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)

        return expression.matches(in: contents, range: range).compactMap { match in
            guard let sourceRange = Range(match.range, in: contents) else {
                return nil
            }
            return String(contents[sourceRange])
        }
    }

    private func firstSourceID(in line: String) -> String? {
        let expression = try? NSRegularExpression(
            pattern: #"\bWF-\d{8}-(?:DESKTOP|ANDROID|IOS)-\d{2}\b"#
        )
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard
            let match = expression?.firstMatch(in: line, range: range),
            let sourceRange = Range(match.range, in: line)
        else {
            return nil
        }
        return String(line[sourceRange])
    }
}
