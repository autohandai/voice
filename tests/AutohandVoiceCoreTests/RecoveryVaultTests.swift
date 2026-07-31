import CryptoKit
import Foundation
import XCTest
@testable import AutohandVoiceCore

final class RecoveryVaultTests: XCTestCase {
    func testEncryptedArtifactRoundTripsAndIsOwnerOnly() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let vault = fixture.vault
        let metadata = RecoveryMetadata(
            sessionID: UUID(),
            createdAt: Date(timeIntervalSince1970: 1_000),
            sampleRate: 16_000,
            languageCode: "en",
            modelVersion: "v3"
        )

        let id = try await vault.stage(
            samples: [0.25, -0.5, 0.75],
            metadata: metadata
        )
        let recovered = try await vault.open(id)

        XCTAssertEqual(recovered.samples, [0.25, -0.5, 0.75])
        XCTAssertEqual(recovered.metadata, metadata)
        let url = fixture.directory
            .appendingPathComponent("\(id.uuidString).avr")
        let data = try Data(contentsOf: url)
        XCTAssertFalse(data.starts(with: Data("AVR1".utf8)))
        let permissions = try FileManager.default.attributesOfItem(
            atPath: url.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testQuotaKeepsNewestBoundedArtifacts() async throws {
        let fixture = try RecoveryFixture(maximumArtifacts: 2)
        defer { fixture.cleanup() }

        for timestamp in [100.0, 200.0, 300.0] {
            _ = try await fixture.vault.stage(
                samples: [Float(timestamp)],
                metadata: RecoveryMetadata(
                    sessionID: UUID(),
                    createdAt: Date(timeIntervalSince1970: timestamp),
                    sampleRate: 16_000,
                    languageCode: "en",
                    modelVersion: "v3"
                )
            )
        }

        let summaries = try await fixture.vault.list()
        XCTAssertEqual(summaries.count, 2)
        XCTAssertEqual(
            summaries.map(\.createdAt),
            [
                Date(timeIntervalSince1970: 300),
                Date(timeIntervalSince1970: 200),
            ]
        )
    }

    func testCorruptionAndKeyLossAreExplicit() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let id = try await fixture.vault.stage(
            samples: [0.1, 0.2],
            metadata: fixture.metadata
        )
        let url = fixture.directory
            .appendingPathComponent("\(id.uuidString).avr")
        try Data("corrupt".utf8).write(to: url, options: .atomic)

        let corruptSummaries = try await fixture.vault.list()
        XCTAssertEqual(corruptSummaries.first?.state, .corrupt)
        await XCTAssertThrowsRecoveryError(
            try await fixture.vault.open(id),
            expected: .corrupt
        )

        try fixture.keys.deleteKey()
        let keylessSummaries = try await fixture.vault.list()
        XCTAssertEqual(keylessSummaries.first?.state, .keyUnavailable)
        await XCTAssertThrowsRecoveryError(
            try await fixture.vault.open(id),
            expected: .keyUnavailable
        )
    }

    func testExpiryAndResolutionRemoveOnlyTargetArtifacts() async throws {
        let fixture = try RecoveryFixture(expiration: 60)
        defer { fixture.cleanup() }
        let oldID = try await fixture.vault.stage(
            samples: [0.1],
            metadata: RecoveryMetadata(
                sessionID: UUID(),
                createdAt: Date(timeIntervalSince1970: 100),
                sampleRate: 16_000,
                languageCode: "en",
                modelVersion: "v3"
            )
        )
        let currentID = try await fixture.vault.stage(
            samples: [0.2],
            metadata: RecoveryMetadata(
                sessionID: UUID(),
                createdAt: Date(timeIntervalSince1970: 200),
                sampleRate: 16_000,
                languageCode: "en",
                modelVersion: "v3"
            )
        )

        try await fixture.vault.purgeExpired(
            now: Date(timeIntervalSince1970: 250)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.directory
                    .appendingPathComponent("\(oldID.uuidString).avr").path
            )
        )
        let currentSummaries = try await fixture.vault.list()
        XCTAssertEqual(currentSummaries.map(\.id), [currentID])

        try await fixture.vault.resolve(currentID, as: .discarded)
        let finalSummaries = try await fixture.vault.list()
        XCTAssertTrue(finalSummaries.isEmpty)
    }

    func testLiveSpoolSurvivesActorRestartAndFinalizesAtomically()
        async throws
    {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let id = try await fixture.vault.beginLiveSpool(
            metadata: fixture.metadata
        )
        try await fixture.vault.appendLiveSpool(
            id,
            samples: [0.1, 0.2]
        )
        try await fixture.vault.appendLiveSpool(
            id,
            samples: [-0.3, 0.4]
        )
        let routedMetadata = RecoveryMetadata(
            sessionID: fixture.metadata.sessionID,
            createdAt: fixture.metadata.createdAt,
            sampleRate: fixture.metadata.sampleRate,
            languageCode: fixture.metadata.languageCode,
            modelVersion: fixture.metadata.modelVersion,
            audioRouteSegments: [
                AudioRouteSegment(
                    deviceUID: "built-in",
                    startedAtUptime: 10,
                    endedAtUptime: 20,
                    outcome: .handedOff
                ),
                AudioRouteSegment(
                    deviceUID: "usb",
                    startedAtUptime: 20
                ),
            ]
        )
        try await fixture.vault.updateLiveSpoolMetadata(
            id,
            metadata: routedMetadata
        )

        let restarted = RecoveryVault(
            directory: fixture.directory,
            keyProvider: fixture.keys
        )
        let recovered = try await restarted.open(id)
        XCTAssertEqual(recovered.samples, [0.1, 0.2, -0.3, 0.4])
        XCTAssertEqual(recovered.metadata, routedMetadata)
        let restartedSummaries = try await restarted.list()
        XCTAssertEqual(restartedSummaries.first?.state, .ready)

        try await restarted.finalizeLiveSpool(id)
        let finalURL = fixture.directory
            .appendingPathComponent("\(id.uuidString).avr")
        let spoolURL = fixture.directory
            .appendingPathComponent(
                "\(id.uuidString).avspool",
                isDirectory: true
            )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: finalURL.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: spoolURL.path)
        )
        let finalized = try await restarted.open(id)
        XCTAssertEqual(finalized.samples, [0.1, 0.2, -0.3, 0.4])
    }

    func testLiveSpoolCorruptionAndKeyLossAreExplicit() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let id = try await fixture.vault.beginLiveSpool(
            metadata: fixture.metadata
        )
        try await fixture.vault.appendLiveSpool(id, samples: [0.5])
        let chunkURL = fixture.directory
            .appendingPathComponent(
                "\(id.uuidString).avspool",
                isDirectory: true
            )
            .appendingPathComponent("00000000.avc")
        try Data("partial".utf8).write(to: chunkURL, options: .atomic)

        let corruptSummaries = try await fixture.vault.list()
        XCTAssertEqual(corruptSummaries.first?.state, .corrupt)
        await XCTAssertThrowsRecoveryError(
            try await fixture.vault.open(id),
            expected: .corrupt
        )

        try fixture.keys.deleteKey()
        let keylessSummaries = try await fixture.vault.list()
        XCTAssertEqual(keylessSummaries.first?.state, .keyUnavailable)
        await XCTAssertThrowsRecoveryError(
            try await fixture.vault.open(id),
            expected: .keyUnavailable
        )
    }

    func testLiveSpoolsParticipateInExpiryQuotaAndResolution()
        async throws
    {
        let fixture = try RecoveryFixture(
            maximumArtifacts: 2,
            expiration: 60
        )
        defer { fixture.cleanup() }
        var ids: [UUID] = []
        for timestamp in [100.0, 200.0, 300.0] {
            let id = try await fixture.vault.beginLiveSpool(
                metadata: RecoveryMetadata(
                    sessionID: UUID(),
                    createdAt: Date(timeIntervalSince1970: timestamp),
                    sampleRate: 16_000,
                    languageCode: "en",
                    modelVersion: "v3"
                )
            )
            try await fixture.vault.appendLiveSpool(
                id,
                samples: [Float(timestamp)]
            )
            ids.append(id)
        }

        let summaries = try await fixture.vault.list()
        XCTAssertEqual(
            summaries.map(\.createdAt),
            [
                Date(timeIntervalSince1970: 300),
                Date(timeIntervalSince1970: 200),
            ]
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: fixture.directory
                    .appendingPathComponent(
                        "\(ids[0].uuidString).avspool"
                    ).path
            )
        )

        try await fixture.vault.purgeExpired(
            now: Date(timeIntervalSince1970: 350)
        )
        let currentSummaries = try await fixture.vault.list()
        XCTAssertEqual(currentSummaries.map(\.id), [ids[2]])
        try await fixture.vault.resolve(ids[2], as: .discarded)
        let finalSummaries = try await fixture.vault.list()
        XCTAssertTrue(finalSummaries.isEmpty)
    }
}

private final class TestRecoveryKeyProvider:
    RecoveryKeyProviding,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var data: Data? = Data(repeating: 7, count: 32)

    func keyData(createIfMissing: Bool) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        if data == nil, createIfMissing {
            data = Data(repeating: 9, count: 32)
        }
        return data
    }

    func deleteKey() throws {
        lock.lock()
        data = nil
        lock.unlock()
    }
}

private struct RecoveryFixture {
    let directory: URL
    let keys = TestRecoveryKeyProvider()
    let vault: RecoveryVault
    let metadata = RecoveryMetadata(
        sessionID: UUID(),
        createdAt: Date(timeIntervalSince1970: 1_000),
        sampleRate: 16_000,
        languageCode: "en",
        modelVersion: "v3"
    )

    init(
        maximumArtifacts: Int = 3,
        expiration: TimeInterval = 86_400
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        vault = RecoveryVault(
            directory: directory,
            keyProvider: keys,
            maximumArtifacts: maximumArtifacts,
            expiration: expiration
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private func XCTAssertThrowsRecoveryError<T>(
    _ expression: @autoclosure () async throws -> T,
    expected: RecoveryVaultError,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected recovery error", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? RecoveryVaultError, expected)
    }
}
