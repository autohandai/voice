import CryptoKit
import Foundation

public enum SyncDataClass:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case notes
    case history
    case vocabulary
    case transformTemplates = "transform_templates"
}

public struct SyncPolicy: Codable, Equatable, Sendable {
    public var enabledClasses: Set<SyncDataClass>

    public init(enabledClasses: Set<SyncDataClass> = []) {
        self.enabledClasses = enabledClasses
    }

    public func permits(_ dataClass: SyncDataClass) -> Bool {
        enabledClasses.contains(dataClass)
    }
}

public struct SyncVersionStamp:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    public let deviceID: UUID
    public let counter: UInt64

    public init(deviceID: UUID, counter: UInt64) {
        self.deviceID = deviceID
        self.counter = counter
    }
}

public struct SyncChange: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let objectID: UUID
    public let dataClass: SyncDataClass
    public let version: SyncVersionStamp
    public let payload: Data
    public let tombstone: Bool

    public init(
        id: UUID = UUID(),
        objectID: UUID,
        dataClass: SyncDataClass,
        version: SyncVersionStamp,
        payload: Data,
        tombstone: Bool = false
    ) {
        self.id = id
        self.objectID = objectID
        self.dataClass = dataClass
        self.version = version
        self.payload = payload
        self.tombstone = tombstone
    }
}

public struct OpaqueSyncObject:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public static let legacyKeyID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000000"
    )!

    public let id: UUID
    public let objectID: UUID
    public let dataClass: SyncDataClass
    public let version: SyncVersionStamp
    public let tombstone: Bool
    public let keyID: UUID
    public let sealedPayload: Data

    public init(
        id: UUID,
        objectID: UUID,
        dataClass: SyncDataClass,
        version: SyncVersionStamp,
        tombstone: Bool,
        keyID: UUID = OpaqueSyncObject.legacyKeyID,
        sealedPayload: Data
    ) {
        self.id = id
        self.objectID = objectID
        self.dataClass = dataClass
        self.version = version
        self.tombstone = tombstone
        self.keyID = keyID
        self.sealedPayload = sealedPayload
    }
}

public struct SyncEncryptionKey: Equatable, Sendable {
    public let id: UUID
    public let material: Data

    public init(id: UUID = UUID(), material: Data) throws {
        guard material.count == 32 else {
            throw SyncFailureError(.missingKey)
        }
        self.id = id
        self.material = material
    }
}

public struct SyncKeyRing: Equatable, Sendable {
    public static let maximumReadableKeys = 4

    public let active: SyncEncryptionKey
    public let readable: [SyncEncryptionKey]

    public init(
        active: SyncEncryptionKey,
        readable: [SyncEncryptionKey] = []
    ) {
        var seen = Set<UUID>([active.id])
        self.active = active
        self.readable = readable.filter {
            seen.insert($0.id).inserted
        }
        .prefix(Self.maximumReadableKeys - 1)
        .map { $0 }
    }

    public func key(id: UUID) -> SyncEncryptionKey? {
        id == active.id
            ? active
            : readable.first { $0.id == id }
    }
}

public enum ConnectedSyncFailure:
    String,
    Codable,
    Equatable,
    Sendable
{
    case disabled
    case missingCredential = "missing_credential"
    case missingKey = "missing_key"
    case quota
    case transport
    case corruptCiphertext = "corrupt_ciphertext"
    case revoked
}

public struct SyncConflictBranch: Equatable, Sendable {
    public let objectID: UUID
    public let local: SyncChange
    public let remote: SyncChange
}

public struct SyncReport: Equatable, Sendable {
    public let uploaded: Int
    public let downloaded: [SyncChange]
    public let conflicts: [SyncConflictBranch]
    public let failure: ConnectedSyncFailure?

    public init(
        uploaded: Int = 0,
        downloaded: [SyncChange] = [],
        conflicts: [SyncConflictBranch] = [],
        failure: ConnectedSyncFailure? = nil
    ) {
        self.uploaded = uploaded
        self.downloaded = downloaded
        self.conflicts = conflicts
        self.failure = failure
    }
}

public protocol OpaqueSyncTransport: Sendable {
    func exchange(
        _ objects: [OpaqueSyncObject]
    ) async throws -> [OpaqueSyncObject]
}

public enum SyncEnvelope {
    public static func seal(
        _ change: SyncChange,
        keyRing: SyncKeyRing
    ) throws -> OpaqueSyncObject {
        try seal(change, key: keyRing.active)
    }

    public static func seal(
        _ change: SyncChange,
        keyData: Data
    ) throws -> OpaqueSyncObject {
        let key = try SyncEncryptionKey(
            id: OpaqueSyncObject.legacyKeyID,
            material: keyData
        )
        return try seal(change, key: key)
    }

    private static func seal(
        _ change: SyncChange,
        key: SyncEncryptionKey
    ) throws -> OpaqueSyncObject {
        let aad = try metadata(
            id: change.id,
            objectID: change.objectID,
            dataClass: change.dataClass,
            version: change.version,
            tombstone: change.tombstone,
            keyID: key.id
        )
        let box = try AES.GCM.seal(
            change.payload,
            using: SymmetricKey(data: key.material),
            authenticating: aad
        )
        guard let combined = box.combined else {
            throw SyncFailureError(.corruptCiphertext)
        }
        return OpaqueSyncObject(
            id: change.id,
            objectID: change.objectID,
            dataClass: change.dataClass,
            version: change.version,
            tombstone: change.tombstone,
            keyID: key.id,
            sealedPayload: combined
        )
    }

    public static func open(
        _ object: OpaqueSyncObject,
        keyRing: SyncKeyRing
    ) throws -> SyncChange {
        guard let key = keyRing.key(id: object.keyID) else {
            throw SyncFailureError(.missingKey)
        }
        return try open(object, key: key)
    }

    public static func open(
        _ object: OpaqueSyncObject,
        keyData: Data
    ) throws -> SyncChange {
        let key = try SyncEncryptionKey(
            id: object.keyID,
            material: keyData
        )
        return try open(object, key: key)
    }

    private static func open(
        _ object: OpaqueSyncObject,
        key: SyncEncryptionKey
    ) throws -> SyncChange {
        guard key.id == object.keyID else {
            throw SyncFailureError(.missingKey)
        }
        do {
            let aad = try metadata(
                id: object.id,
                objectID: object.objectID,
                dataClass: object.dataClass,
                version: object.version,
                tombstone: object.tombstone,
                keyID: object.keyID
            )
            let box = try AES.GCM.SealedBox(
                combined: object.sealedPayload
            )
            let payload = try AES.GCM.open(
                box,
                using: SymmetricKey(data: key.material),
                authenticating: aad
            )
            return SyncChange(
                id: object.id,
                objectID: object.objectID,
                dataClass: object.dataClass,
                version: object.version,
                payload: payload,
                tombstone: object.tombstone
            )
        } catch let error as SyncFailureError {
            throw error
        } catch {
            throw SyncFailureError(.corruptCiphertext)
        }
    }

    private static func metadata(
        id: UUID,
        objectID: UUID,
        dataClass: SyncDataClass,
        version: SyncVersionStamp,
        tombstone: Bool,
        keyID: UUID
    ) throws -> Data {
        let value = SyncAuthenticatedMetadata(
            id: id,
            objectID: objectID,
            dataClass: dataClass,
            version: version,
            tombstone: tombstone,
            keyID: keyID
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
}

public struct SyncFailureError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    public let failure: ConnectedSyncFailure

    public init(_ failure: ConnectedSyncFailure) {
        self.failure = failure
    }

    public var errorDescription: String? {
        "Encrypted sync failed: \(failure.rawValue). Local data remains available."
    }
}

public actor OptionalSyncClient {
    public static let maximumQueuedChanges = 10_000
    public static let maximumQueuedBytes = 10 * 1_024 * 1_024

    private let transport: any OpaqueSyncTransport
    private var policy: SyncPolicy
    private var keyData: Data?
    private var queue: [SyncChange] = []
    private var latestByObject: [UUID: SyncChange] = [:]

    public init(
        transport: any OpaqueSyncTransport,
        policy: SyncPolicy = SyncPolicy(),
        keyData: Data? = nil
    ) {
        self.transport = transport
        self.policy = policy
        self.keyData = keyData
    }

    public func configure(
        policy: SyncPolicy,
        keyData: Data?
    ) {
        self.policy = policy
        self.keyData = keyData
    }

    public func enqueue(_ changes: [SyncChange]) throws {
        let permitted = changes.filter {
            policy.permits($0.dataClass)
        }
        guard !permitted.isEmpty else { return }
        let candidate = queue + permitted
        let bytes = candidate.reduce(0) {
            $0 + $1.payload.count
        }
        guard
            candidate.count <= Self.maximumQueuedChanges,
            bytes <= Self.maximumQueuedBytes
        else {
            throw SyncFailureError(.quota)
        }
        queue = candidate
        for change in permitted {
            latestByObject[change.objectID] = change
        }
    }

    public func reconcile() async -> SyncReport {
        guard !policy.enabledClasses.isEmpty else {
            return SyncReport(failure: .disabled)
        }
        guard let keyData, keyData.count == 32 else {
            return SyncReport(failure: .missingKey)
        }
        do {
            let outgoing = try queue.map {
                try SyncEnvelope.seal($0, keyData: keyData)
            }
            let remoteObjects = try await transport.exchange(outgoing)
            var downloaded: [SyncChange] = []
            var conflicts: [SyncConflictBranch] = []
            for object in remoteObjects
                where policy.permits(object.dataClass)
            {
                let remote = try SyncEnvelope.open(
                    object,
                    keyData: keyData
                )
                if let local = latestByObject[remote.objectID],
                   local.version != remote.version
                {
                    conflicts.append(
                        SyncConflictBranch(
                            objectID: remote.objectID,
                            local: local,
                            remote: remote
                        )
                    )
                } else {
                    downloaded.append(remote)
                    latestByObject[remote.objectID] = remote
                }
            }
            queue.removeAll(keepingCapacity: true)
            return SyncReport(
                uploaded: outgoing.count,
                downloaded: downloaded,
                conflicts: conflicts
            )
        } catch let error as SyncFailureError {
            return SyncReport(failure: error.failure)
        } catch {
            return SyncReport(failure: .transport)
        }
    }
}

public struct ConnectedReleaseEvidence:
    Codable,
    Equatable,
    Sendable
{
    public var authenticatedControlPlane: Bool
    public var secondFirstPartyClient: Bool
    public var packetCapture: Bool
    public var revocation: Bool
    public var billingAndEmail: Bool
    public var legalSecurityApproval: Bool

    public init(
        authenticatedControlPlane: Bool = false,
        secondFirstPartyClient: Bool = false,
        packetCapture: Bool = false,
        revocation: Bool = false,
        billingAndEmail: Bool = false,
        legalSecurityApproval: Bool = false
    ) {
        self.authenticatedControlPlane = authenticatedControlPlane
        self.secondFirstPartyClient = secondFirstPartyClient
        self.packetCapture = packetCapture
        self.revocation = revocation
        self.billingAndEmail = billingAndEmail
        self.legalSecurityApproval = legalSecurityApproval
    }

    public var allowsSyncUI: Bool {
        authenticatedControlPlane
            && secondFirstPartyClient
            && packetCapture
            && revocation
            && legalSecurityApproval
    }

    public var allowsAccountUI: Bool {
        authenticatedControlPlane
            && revocation
            && billingAndEmail
            && legalSecurityApproval
    }
}

public struct AccountSnapshot: Codable, Equatable, Sendable {
    public let accountID: UUID
    public let entitlementIDs: Set<String>
    public let expiresAt: Date?

    public init(
        accountID: UUID,
        entitlementIDs: Set<String>,
        expiresAt: Date?
    ) {
        self.accountID = accountID
        self.entitlementIDs = entitlementIDs
        self.expiresAt = expiresAt
    }
}

public protocol AccountCapability: Sendable {
    func signIn() async throws -> AccountSnapshot
    func refreshEntitlements() async throws -> AccountSnapshot
    func signOut(deleteLocalData: Bool) async throws
}

private struct SyncAuthenticatedMetadata: Codable {
    let id: UUID
    let objectID: UUID
    let dataClass: SyncDataClass
    let version: SyncVersionStamp
    let tombstone: Bool
    let keyID: UUID
}
