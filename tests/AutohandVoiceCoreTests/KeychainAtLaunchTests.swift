import XCTest
@testable import AutohandVoiceCore

/// macOS asks for the login password when an app reads a Keychain item it
/// did not create with the same code signature, which happens after every
/// ad-hoc signed update. Launch must therefore never read the Keychain.
final class KeychainAtLaunchTests: XCTestCase {
    func testListingAnEmptyRecoveryVaultDoesNotReadTheKey() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keys = CountingKeyProvider()
        let vault = RecoveryVault(directory: directory, keyProvider: keys)

        let summaries = try await vault.list()

        XCTAssertTrue(summaries.isEmpty)
        XCTAssertEqual(keys.reads, 0)
    }

    func testTheTalkKeyIsOnlyReadWhenFirstNeeded() throws {
        var reads = 0
        var cache = DeferredCredential { reads += 1; return "ahc_test" }
        XCTAssertEqual(reads, 0)

        XCTAssertEqual(try cache.value(), "ahc_test")
        XCTAssertEqual(try cache.value(), "ahc_test")
        XCTAssertEqual(reads, 1)
    }

    func testStoringOrClearingNeverReadsTheKeychain() throws {
        var reads = 0
        var cache = DeferredCredential { reads += 1; return "stale" }
        cache.store("ahc_new")
        XCTAssertEqual(try cache.value(), "ahc_new")
        cache.clear()
        XCTAssertNil(try cache.value())
        XCTAssertEqual(reads, 0)
    }

    func testAMissingKeyIsRememberedAsMissing() throws {
        var reads = 0
        var cache = DeferredCredential<String> { reads += 1; return nil }
        XCTAssertNil(try cache.value())
        XCTAssertNil(try cache.value())
        XCTAssertEqual(reads, 1)
    }

    func testAFailedReadCanBeRetried() {
        var reads = 0
        var cache = DeferredCredential<String> {
            reads += 1
            throw NSError(domain: "keychain", code: -128)
        }
        XCTAssertThrowsError(try cache.value())
        XCTAssertThrowsError(try cache.value())
        XCTAssertEqual(reads, 2)
    }
}

final class LaunchAtLoginReconciliationTests: XCTestCase {
    func testAnUpdateThatDroppedTheLoginItemIsRegisteredAgain() {
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: true, status: .notRegistered),
            .register
        )
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: true, status: .notFound),
            .register
        )
    }

    func testApprovalInSystemSettingsIsSurfacedNotForced() {
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: true, status: .requiresApproval),
            .askForApproval
        )
    }

    func testNothingChangesWhenTheSystemAlreadyMatches() {
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: true, status: .enabled),
            .none
        )
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: false, status: .notRegistered),
            .none
        )
    }

    func testTurningItOnInSystemSettingsIsRespected() {
        // The person enabled it in System Settings; adopt that choice.
        XCTAssertEqual(
            LaunchAtLoginReconciliation.action(wanted: false, status: .enabled),
            .adoptEnabled
        )
    }
}

private final class CountingKeyProvider: RecoveryKeyProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var reads: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func keyData(createIfMissing: Bool) throws -> Data? {
        lock.lock()
        count += 1
        lock.unlock()
        return Data(repeating: 7, count: 32)
    }

    func deleteKey() throws {}
}
