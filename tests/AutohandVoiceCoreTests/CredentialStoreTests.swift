import XCTest
@testable import AutohandVoiceCore

final class CredentialStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func credential(_ token: String) -> AccountCredential {
        try! AccountCredential(accessToken: token, refreshToken: nil, expiresAt: .distantFuture)
    }

    func testAStoredKeyRoundTripsAndOnlyItsOwnerCanReadIt() throws {
        let vault = FileAccountCredentialVault(
            url: directory.appendingPathComponent("talk-credential.json")
        )
        XCTAssertNil(try vault.load())
        try vault.store(credential("ahc_one"))
        XCTAssertEqual(try vault.load()?.accessToken, "ahc_one")
        try vault.store(credential("ahc_two"))
        XCTAssertEqual(try vault.load()?.accessToken, "ahc_two")

        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("talk-credential.json").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testDeletingForgetsTheKey() throws {
        let vault = FileAccountCredentialVault(
            url: directory.appendingPathComponent("talk-credential.json")
        )
        try vault.store(credential("ahc_one"))
        try vault.delete()
        XCTAssertNil(try vault.load())
        try vault.delete()
    }

    func testOnlyAStableSignatureUsesKeychain() {
        // Ad-hoc builds get a new signature on every update, so Keychain
        // would ask for the login password each time.
        XCTAssertEqual(CredentialStorage.choose(isAdHocSigned: true), .ownerOnlyFile)
        XCTAssertEqual(CredentialStorage.choose(isAdHocSigned: false), .keychain)
    }
}
