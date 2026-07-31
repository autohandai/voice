import Foundation
import XCTest
@testable import AutohandVoiceCore

final class ConnectedCapabilitiesTests: XCTestCase {
    func testAllConnectedDataClassesDefaultOffAndMakeNoRequest()
        async
    {
        let transport = SyncTransportSpy()
        let client = OptionalSyncClient(
            transport: transport,
            keyData: Data(repeating: 1, count: 32)
        )
        try? await client.enqueue([fixtureChange()])

        let report = await client.reconcile()
        let callCount = await transport.callCount

        XCTAssertEqual(report.failure, .disabled)
        XCTAssertEqual(callCount, 0)
    }

    func testOpaqueEnvelopeAuthenticatesMetadataAndPayload() throws {
        let key = Data(repeating: 3, count: 32)
        let change = fixtureChange(payload: Data("private note".utf8))
        let sealed = try SyncEnvelope.seal(change, keyData: key)

        XCTAssertNil(
            sealed.sealedPayload.range(of: Data("private note".utf8))
        )
        XCTAssertEqual(try SyncEnvelope.open(sealed, keyData: key), change)

        let tampered = OpaqueSyncObject(
            id: sealed.id,
            objectID: sealed.objectID,
            dataClass: .history,
            version: sealed.version,
            tombstone: sealed.tombstone,
            sealedPayload: sealed.sealedPayload
        )
        XCTAssertThrowsError(
            try SyncEnvelope.open(tampered, keyData: key)
        ) { error in
            XCTAssertEqual(
                (error as? SyncFailureError)?.failure,
                .corruptCiphertext
            )
        }
    }

    func testConcurrentRemoteVersionRetainsBothConflictBranches()
        async throws
    {
        let key = Data(repeating: 5, count: 32)
        let local = fixtureChange()
        let remote = SyncChange(
            objectID: local.objectID,
            dataClass: .notes,
            version: SyncVersionStamp(
                deviceID: UUID(),
                counter: 1
            ),
            payload: Data("remote".utf8)
        )
        let transport = SyncTransportSpy(
            response: [try SyncEnvelope.seal(remote, keyData: key)]
        )
        let client = OptionalSyncClient(
            transport: transport,
            policy: SyncPolicy(enabledClasses: [.notes]),
            keyData: key
        )
        try await client.enqueue([local])

        let report = await client.reconcile()

        XCTAssertNil(report.failure)
        XCTAssertEqual(report.uploaded, 1)
        XCTAssertTrue(report.downloaded.isEmpty)
        XCTAssertEqual(report.conflicts.count, 1)
        XCTAssertEqual(report.conflicts[0].local, local)
        XCTAssertEqual(report.conflicts[0].remote, remote)
    }

    func testReleaseEvidenceFailsClosedUntilEveryExternalGatePasses() {
        var evidence = ConnectedReleaseEvidence(
            authenticatedControlPlane: true,
            secondFirstPartyClient: true,
            packetCapture: true,
            revocation: true,
            billingAndEmail: true
        )

        XCTAssertFalse(evidence.allowsSyncUI)
        XCTAssertFalse(evidence.allowsAccountUI)

        evidence.legalSecurityApproval = true
        XCTAssertTrue(evidence.allowsSyncUI)
        XCTAssertTrue(evidence.allowsAccountUI)
    }

    func testKeyRotationReadsOldCiphertextWithoutUsingOldKeyForWrites()
        throws
    {
        let old = try SyncEncryptionKey(
            id: UUID(),
            material: Data(repeating: 1, count: 32)
        )
        let current = try SyncEncryptionKey(
            id: UUID(),
            material: Data(repeating: 2, count: 32)
        )
        let oldObject = try SyncEnvelope.seal(
            fixtureChange(),
            keyRing: SyncKeyRing(active: old)
        )
        let rotated = SyncKeyRing(
            active: current,
            readable: [old]
        )

        XCTAssertNoThrow(
            try SyncEnvelope.open(oldObject, keyRing: rotated)
        )
        XCTAssertThrowsError(
            try SyncEnvelope.open(
                oldObject,
                keyRing: SyncKeyRing(active: current)
            )
        ) { error in
            XCTAssertEqual(
                (error as? SyncFailureError)?.failure,
                .missingKey
            )
        }
        let newObject = try SyncEnvelope.seal(
            fixtureChange(),
            keyRing: rotated
        )
        XCTAssertEqual(newObject.keyID, current.id)
    }

    private func fixtureChange(
        payload: Data = Data("local".utf8)
    ) -> SyncChange {
        SyncChange(
            objectID: UUID(),
            dataClass: .notes,
            version: SyncVersionStamp(
                deviceID: UUID(),
                counter: 1
            ),
            payload: payload
        )
    }
}

private actor SyncTransportSpy: OpaqueSyncTransport {
    private(set) var callCount = 0
    private let response: [OpaqueSyncObject]

    init(response: [OpaqueSyncObject] = []) {
        self.response = response
    }

    func exchange(
        _ objects: [OpaqueSyncObject]
    ) async throws -> [OpaqueSyncObject] {
        _ = objects
        callCount += 1
        return response
    }
}
