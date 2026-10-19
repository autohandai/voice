import CryptoKit
import Foundation
import Security

public enum RecoveryVaultError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case emptyAudio
    case audioTooLong
    case corrupt
    case keyUnavailable
    case notFound
    case storageUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyAudio:
            "There is no captured audio to recover."
        case .audioTooLong:
            "The recovery audio exceeds the local duration limit."
        case .corrupt:
            "The encrypted recovery artifact is corrupt."
        case .keyUnavailable:
            "The local recovery encryption key is unavailable."
        case .notFound:
            "That recovery artifact no longer exists."
        case .storageUnavailable:
            "Encrypted recovery storage is unavailable."
        }
    }
}

public struct RecoveryMetadata: Codable, Equatable, Sendable {
    public let sessionID: UUID
    public let createdAt: Date
    public let sampleRate: Double
    public let languageCode: String
    public let modelVersion: String
    public let audioRouteSegments: [AudioRouteSegment]

    public init(
        sessionID: UUID,
        createdAt: Date = Date(),
        sampleRate: Double,
        languageCode: String,
        modelVersion: String,
        audioRouteSegments: [AudioRouteSegment] = []
    ) {
        self.sessionID = sessionID
        self.createdAt = createdAt
        self.sampleRate = min(max(sampleRate, 8_000), 192_000)
        self.languageCode = String(languageCode.prefix(32))
        self.modelVersion = String(modelVersion.prefix(64))
        self.audioRouteSegments = Array(
            audioRouteSegments.suffix(AudioRouteTimeline.maximumSegments)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID
        case createdAt
        case sampleRate
        case languageCode
        case modelVersion
        case audioRouteSegments
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            sessionID: try container.decode(UUID.self, forKey: .sessionID),
            createdAt: try container.decode(
                Date.self,
                forKey: .createdAt
            ),
            sampleRate: try container.decode(
                Double.self,
                forKey: .sampleRate
            ),
            languageCode: try container.decode(
                String.self,
                forKey: .languageCode
            ),
            modelVersion: try container.decode(
                String.self,
                forKey: .modelVersion
            ),
            audioRouteSegments: try container.decodeIfPresent(
                [AudioRouteSegment].self,
                forKey: .audioRouteSegments
            ) ?? []
        )
    }
}

public enum RecoveryArtifactState: String, Codable, Equatable, Sendable {
    case ready
    case corrupt
    case keyUnavailable
}

public struct RecoverySummary: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let duration: TimeInterval?
    public let state: RecoveryArtifactState
}

public struct RecoveredAudioArtifact: Equatable, Sendable {
    public let id: UUID
    public let samples: [Float]
    public let metadata: RecoveryMetadata
}

public enum RecoveryResolution: String, Codable, Sendable {
    case recovered
    case discarded
}

public protocol RecoveryKeyProviding: Sendable {
    func keyData(createIfMissing: Bool) throws -> Data?
    func deleteKey() throws
}

public final class KeychainRecoveryKeyProvider:
    RecoveryKeyProviding,
    @unchecked Sendable
{
    private let service = Brand.bundleIdentifier + ".recovery"
    private let account = "recovery-v1"

    public init() {}

    public func keyData(createIfMissing: Bool) throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess {
            guard let data = result as? Data, data.count == 32 else {
                throw RecoveryVaultError.keyUnavailable
            }
            return data
        }
        guard status == errSecItemNotFound else {
            throw RecoveryVaultError.keyUnavailable
        }
        guard createIfMissing else { return nil }

        let data = SymmetricKey(size: .bits256).withUnsafeBytes {
            Data($0)
        }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else {
            throw RecoveryVaultError.keyUnavailable
        }
        return data
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw RecoveryVaultError.keyUnavailable
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

public actor RecoveryVault {
    public static let maximumSamples = 19_200_000
    public static let maximumFileBytes = 100 * 1_024 * 1_024

    private let directory: URL
    private let keyProvider: any RecoveryKeyProviding
    private let maximumArtifacts: Int
    private let expiration: TimeInterval
    private var liveSpoolNextChunk: [UUID: Int] = [:]
    private var fileManager: FileManager { .default }

    public init(
        directory: URL = Brand.recoveryDirectory,
        keyProvider: any RecoveryKeyProviding =
            KeychainRecoveryKeyProvider(),
        maximumArtifacts: Int = 3,
        expiration: TimeInterval = 24 * 60 * 60
    ) {
        self.directory = directory
        self.keyProvider = keyProvider
        self.maximumArtifacts = min(max(maximumArtifacts, 1), 8)
        self.expiration = min(
            max(expiration, 60),
            24 * 60 * 60
        )
    }

    @discardableResult
    public func stage(
        samples: [Float],
        metadata: RecoveryMetadata
    ) throws -> UUID {
        guard !samples.isEmpty else {
            throw RecoveryVaultError.emptyAudio
        }
        guard samples.count <= Self.maximumSamples else {
            throw RecoveryVaultError.audioTooLong
        }
        let id = UUID()
        try writeFinalArtifact(
            id: id,
            samples: samples,
            metadata: metadata
        )
        try enforceQuota()
        return id
    }

    public func beginLiveSpool(
        metadata: RecoveryMetadata
    ) throws -> UUID {
        guard
            let keyData = try keyProvider.keyData(createIfMissing: true),
            keyData.count == 32
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        try prepareDirectory()
        let id = UUID()
        let spool = spoolURL(for: id)
        do {
            try fileManager.createDirectory(
                at: spool,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700]
            )
            let header = try JSONEncoder.recovery.encode(metadata)
            let encrypted = try seal(header, keyData: keyData)
            let headerURL = spool.appendingPathComponent("header.avh")
            try encrypted.write(to: headerURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: headerURL.path
            )
            excludeFromBackup(spool)
            liveSpoolNextChunk[id] = 0
            try enforceQuota()
            return id
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            try? fileManager.removeItem(at: spool)
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func appendLiveSpool(
        _ id: UUID,
        samples: [Float]
    ) throws {
        guard !samples.isEmpty else { return }
        guard samples.count <= 1_000_000 else {
            throw RecoveryVaultError.audioTooLong
        }
        let spool = spoolURL(for: id)
        guard fileManager.fileExists(atPath: spool.path) else {
            throw RecoveryVaultError.notFound
        }
        guard
            let keyData = try keyProvider.keyData(createIfMissing: false)
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        let next: Int
        if let remembered = liveSpoolNextChunk[id] {
            next = remembered
        } else {
            next = try chunkURLs(in: spool).count
        }
        let existingSamples = try estimatedSampleCount(
            in: spool,
            keyData: keyData
        )
        guard existingSamples + samples.count <= Self.maximumSamples else {
            throw RecoveryVaultError.audioTooLong
        }
        let encoded = RecoveryChunkCodec.encode(samples)
        let encrypted = try seal(encoded, keyData: keyData)
        let chunkURL = spool.appendingPathComponent(
            String(format: "%08d.avc", next)
        )
        do {
            try encrypted.write(to: chunkURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: chunkURL.path
            )
            liveSpoolNextChunk[id] = next + 1
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func finalizeLiveSpool(
        _ id: UUID,
        metadata: RecoveryMetadata? = nil
    ) throws {
        let artifact = try openLiveSpool(id)
        try writeFinalArtifact(
            id: id,
            samples: artifact.samples,
            metadata: metadata ?? artifact.metadata
        )
        do {
            try fileManager.removeItem(at: spoolURL(for: id))
            liveSpoolNextChunk[id] = nil
            try enforceQuota()
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func discardLiveSpool(_ id: UUID) throws {
        let url = spoolURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.removeItem(at: url)
            liveSpoolNextChunk[id] = nil
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func updateLiveSpoolMetadata(
        _ id: UUID,
        metadata: RecoveryMetadata
    ) throws {
        let spool = spoolURL(for: id)
        guard fileManager.fileExists(atPath: spool.path) else {
            throw RecoveryVaultError.notFound
        }
        guard
            let keyData = try keyProvider.keyData(createIfMissing: false),
            keyData.count == 32
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        do {
            let header = try JSONEncoder.recovery.encode(metadata)
            guard header.count <= 12_000 else {
                throw RecoveryVaultError.corrupt
            }
            let encrypted = try seal(header, keyData: keyData)
            let headerURL = spool.appendingPathComponent("header.avh")
            try encrypted.write(to: headerURL, options: [.atomic])
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: headerURL.path
            )
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    private func writeFinalArtifact(
        id: UUID,
        samples: [Float],
        metadata: RecoveryMetadata
    ) throws {
        guard !samples.isEmpty else {
            throw RecoveryVaultError.emptyAudio
        }
        guard samples.count <= Self.maximumSamples else {
            throw RecoveryVaultError.audioTooLong
        }
        guard
            let keyData = try keyProvider.keyData(createIfMissing: true),
            keyData.count == 32
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        try prepareDirectory()
        let plaintext = try RecoveryArtifactCodec.encode(
            samples: samples,
            metadata: metadata
        )
        let combined = try seal(plaintext, keyData: keyData)
        guard combined.count <= Self.maximumFileBytes else {
            throw RecoveryVaultError.audioTooLong
        }
        let url = fileURL(for: id)
        do {
            try combined.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
            excludeFromBackup(url)
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func list() throws -> [RecoverySummary] {
        let urls = try artifactURLs()
        // Nothing to recover: leave the Keychain alone (see DeferredCredential).
        guard !urls.isEmpty else { return [] }
        let keyData = try keyProvider.keyData(createIfMissing: false)
        let summaries = urls.compactMap { url -> RecoverySummary? in
            guard let id = UUID(uuidString: url.deletingPathExtension()
                .lastPathComponent) else { return nil }
            let fallbackDate = modificationDate(for: url)
            guard let keyData else {
                return RecoverySummary(
                    id: id,
                    createdAt: fallbackDate,
                    duration: nil,
                    state: .keyUnavailable
                )
            }
            do {
                let artifact = url.pathExtension == "avspool"
                    ? try openLiveSpool(
                        id,
                        url: url,
                        keyData: keyData
                    )
                    : try decrypt(
                        id: id,
                        url: url,
                        keyData: keyData
                    )
                return RecoverySummary(
                    id: id,
                    createdAt: artifact.metadata.createdAt,
                    duration: TimeInterval(artifact.samples.count)
                        / artifact.metadata.sampleRate,
                    state: .ready
                )
            } catch {
                return RecoverySummary(
                    id: id,
                    createdAt: fallbackDate,
                    duration: nil,
                    state: .corrupt
                )
            }
        }
        return summaries.sorted { $0.createdAt > $1.createdAt }
    }

    public func open(_ id: UUID) throws -> RecoveredAudioArtifact {
        let url = fileURL(for: id)
        guard
            let keyData = try keyProvider.keyData(createIfMissing: false)
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        if fileManager.fileExists(atPath: url.path) {
            return try decrypt(id: id, url: url, keyData: keyData)
        }
        let spool = spoolURL(for: id)
        guard fileManager.fileExists(atPath: spool.path) else {
            throw RecoveryVaultError.notFound
        }
        return try openLiveSpool(id, url: spool, keyData: keyData)
    }

    public func resolve(
        _ id: UUID,
        as resolution: RecoveryResolution
    ) throws {
        _ = resolution
        let urls = [fileURL(for: id), spoolURL(for: id)]
        let existing = urls.filter {
            fileManager.fileExists(atPath: $0.path)
        }
        guard !existing.isEmpty else {
            throw RecoveryVaultError.notFound
        }
        do {
            for url in existing {
                try fileManager.removeItem(at: url)
            }
            liveSpoolNextChunk[id] = nil
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    public func purgeExpired(now: Date = Date()) throws {
        for summary in try list() {
            if summary.createdAt.addingTimeInterval(expiration) <= now {
                try? fileManager.removeItem(at: fileURL(for: summary.id))
                try? fileManager.removeItem(at: spoolURL(for: summary.id))
                liveSpoolNextChunk[summary.id] = nil
            }
        }
    }

    public func reset() throws {
        if fileManager.fileExists(atPath: directory.path) {
            do {
                try fileManager.removeItem(at: directory)
            } catch {
                throw RecoveryVaultError.storageUnavailable
            }
        }
        liveSpoolNextChunk.removeAll(keepingCapacity: false)
        try keyProvider.deleteKey()
    }

    private func openLiveSpool(_ id: UUID) throws
        -> RecoveredAudioArtifact
    {
        let url = spoolURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RecoveryVaultError.notFound
        }
        guard
            let keyData = try keyProvider.keyData(createIfMissing: false)
        else {
            throw RecoveryVaultError.keyUnavailable
        }
        return try openLiveSpool(id, url: url, keyData: keyData)
    }

    private func openLiveSpool(
        _ id: UUID,
        url: URL,
        keyData: Data
    ) throws -> RecoveredAudioArtifact {
        do {
            guard keyData.count == 32 else {
                throw RecoveryVaultError.keyUnavailable
            }
            let headerURL = url.appendingPathComponent(
                "header.avh",
                isDirectory: false
            )
            let encryptedHeader = try boundedData(
                at: headerURL,
                maximumBytes: 16_384
            )
            let header = try open(
                encryptedHeader,
                keyData: keyData
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let metadata = try decoder.decode(
                RecoveryMetadata.self,
                from: header
            )
            var samples: [Float] = []
            for chunkURL in try chunkURLs(in: url) {
                let encrypted = try boundedData(
                    at: chunkURL,
                    maximumBytes:
                        4 * MemoryLayout<UInt32>.size * 1_000_000
                            + 128
                )
                let plaintext = try open(
                    encrypted,
                    keyData: keyData
                )
                let chunk = try RecoveryChunkCodec.decode(plaintext)
                guard samples.count + chunk.count <= Self.maximumSamples else {
                    throw RecoveryVaultError.corrupt
                }
                samples.append(contentsOf: chunk)
            }
            return RecoveredAudioArtifact(
                id: id,
                samples: samples,
                metadata: metadata
            )
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.corrupt
        }
    }

    private func decrypt(
        id: UUID,
        url: URL,
        keyData: Data
    ) throws -> RecoveredAudioArtifact {
        do {
            let encrypted = try Data(
                contentsOf: url,
                options: [.mappedIfSafe]
            )
            guard encrypted.count <= Self.maximumFileBytes else {
                throw RecoveryVaultError.corrupt
            }
            let box = try AES.GCM.SealedBox(combined: encrypted)
            let plaintext = try AES.GCM.open(
                box,
                using: SymmetricKey(data: keyData)
            )
            let decoded = try RecoveryArtifactCodec.decode(plaintext)
            return RecoveredAudioArtifact(
                id: id,
                samples: decoded.samples,
                metadata: decoded.metadata
            )
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.corrupt
        }
    }

    private func prepareDirectory() throws {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectory = directory
            try? mutableDirectory.setResourceValues(values)
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    private func enforceQuota() throws {
        let summaries = try list()
        for summary in summaries.dropFirst(maximumArtifacts) {
            try? fileManager.removeItem(at: fileURL(for: summary.id))
            try? fileManager.removeItem(at: spoolURL(for: summary.id))
            liveSpoolNextChunk[summary.id] = nil
        }
    }

    private func artifactURLs() throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        do {
            return try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            )
            .filter {
                $0.pathExtension == "avr"
                    || $0.pathExtension == "avspool"
            }
            .prefix(64)
            .map { $0 }
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    private func fileURL(for id: UUID) -> URL {
        directory.appendingPathComponent(
            "\(id.uuidString).avr",
            isDirectory: false
        )
    }

    private func spoolURL(for id: UUID) -> URL {
        directory.appendingPathComponent(
            "\(id.uuidString).avspool",
            isDirectory: true
        )
    }

    private func chunkURLs(in spool: URL) throws -> [URL] {
        do {
            let urls = try fileManager.contentsOfDirectory(
                at: spool,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            let chunks = urls
                .filter { $0.pathExtension == "avc" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            guard chunks.count <= 4_096 else {
                throw RecoveryVaultError.corrupt
            }
            for (index, url) in chunks.enumerated() {
                guard url.lastPathComponent
                    == String(format: "%08d.avc", index)
                else {
                    throw RecoveryVaultError.corrupt
                }
            }
            return chunks
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    private func estimatedSampleCount(
        in spool: URL,
        keyData: Data
    ) throws -> Int {
        var total = 0
        for url in try chunkURLs(in: spool) {
            do {
                let encrypted = try boundedData(
                    at: url,
                    maximumBytes:
                        4 * MemoryLayout<UInt32>.size * 1_000_000
                            + 128
                )
                let plaintext = try open(
                    encrypted,
                    keyData: keyData
                )
                total += try RecoveryChunkCodec.sampleCount(plaintext)
                guard total <= Self.maximumSamples else {
                    throw RecoveryVaultError.audioTooLong
                }
            } catch let error as RecoveryVaultError {
                throw error
            } catch {
                throw RecoveryVaultError.corrupt
            }
        }
        return total
    }

    private func boundedData(
        at url: URL,
        maximumBytes: Int
    ) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard
            let size = values.fileSize,
            size >= 0,
            size <= maximumBytes
        else {
            throw RecoveryVaultError.corrupt
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func seal(_ plaintext: Data, keyData: Data) throws -> Data {
        do {
            let sealed = try AES.GCM.seal(
                plaintext,
                using: SymmetricKey(data: keyData)
            )
            guard let combined = sealed.combined else {
                throw RecoveryVaultError.storageUnavailable
            }
            return combined
        } catch let error as RecoveryVaultError {
            throw error
        } catch {
            throw RecoveryVaultError.storageUnavailable
        }
    }

    private func open(_ encrypted: Data, keyData: Data) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: encrypted)
            return try AES.GCM.open(
                box,
                using: SymmetricKey(data: keyData)
            )
        } catch {
            throw RecoveryVaultError.corrupt
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate) ?? .distantPast
    }
}

private enum RecoveryChunkCodec {
    private static let magic = Data("AVC1".utf8)

    static func encode(_ samples: [Float]) -> Data {
        var data = Data()
        data.reserveCapacity(
            magic.count + MemoryLayout<UInt32>.size
                + samples.count * MemoryLayout<UInt32>.size
        )
        data.append(magic)
        appendUInt32(UInt32(samples.count), to: &data)
        for sample in samples {
            appendUInt32(sample.bitPattern, to: &data)
        }
        return data
    }

    static func decode(_ data: Data) throws -> [Float] {
        var offset = 0
        guard try readData(
            count: magic.count,
            from: data,
            offset: &offset
        ) == magic else {
            throw RecoveryVaultError.corrupt
        }
        let count = Int(try readUInt32(from: data, offset: &offset))
        guard
            count <= 1_000_000,
            data.count - offset == count * MemoryLayout<UInt32>.size
        else {
            throw RecoveryVaultError.corrupt
        }
        var samples: [Float] = []
        samples.reserveCapacity(count)
        for _ in 0 ..< count {
            samples.append(
                Float(
                    bitPattern: try readUInt32(
                        from: data,
                        offset: &offset
                    )
                )
            )
        }
        return samples
    }

    static func sampleCount(_ data: Data) throws -> Int {
        var offset = 0
        guard try readData(
            count: magic.count,
            from: data,
            offset: &offset
        ) == magic else {
            throw RecoveryVaultError.corrupt
        }
        let count = Int(try readUInt32(from: data, offset: &offset))
        guard
            count <= 1_000_000,
            data.count - offset == count * MemoryLayout<UInt32>.size
        else {
            throw RecoveryVaultError.corrupt
        }
        return count
    }

    private static func appendUInt32(
        _ value: UInt32,
        to data: inout Data
    ) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(
        from data: Data,
        offset: inout Int
    ) throws -> UInt32 {
        let bytes = try readData(
            count: MemoryLayout<UInt32>.size,
            from: data,
            offset: &offset
        )
        return bytes.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
    }

    private static func readData(
        count: Int,
        from data: Data,
        offset: inout Int
    ) throws -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw RecoveryVaultError.corrupt
        }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }
}

private enum RecoveryArtifactCodec {
    private static let magic = Data("AVR1".utf8)

    static func encode(
        samples: [Float],
        metadata: RecoveryMetadata
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let metadataData = try encoder.encode(metadata)
        guard metadataData.count <= 16_384 else {
            throw RecoveryVaultError.corrupt
        }
        var data = Data()
        data.reserveCapacity(
            magic.count + 8 + metadataData.count
                + samples.count * MemoryLayout<UInt32>.size
        )
        data.append(magic)
        appendUInt32(UInt32(metadataData.count), to: &data)
        data.append(metadataData)
        appendUInt32(UInt32(samples.count), to: &data)
        for sample in samples {
            appendUInt32(sample.bitPattern, to: &data)
        }
        return data
    }

    static func decode(
        _ data: Data
    ) throws -> (samples: [Float], metadata: RecoveryMetadata) {
        var offset = 0
        guard try readData(count: magic.count, from: data, offset: &offset)
            == magic else {
            throw RecoveryVaultError.corrupt
        }
        let metadataLength = Int(
            try readUInt32(from: data, offset: &offset)
        )
        guard metadataLength <= 16_384 else {
            throw RecoveryVaultError.corrupt
        }
        let metadataData = try readData(
            count: metadataLength,
            from: data,
            offset: &offset
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let metadata = try decoder.decode(
            RecoveryMetadata.self,
            from: metadataData
        )
        let sampleCount = Int(try readUInt32(from: data, offset: &offset))
        guard
            sampleCount <= RecoveryVault.maximumSamples,
            data.count - offset == sampleCount * MemoryLayout<UInt32>.size
        else {
            throw RecoveryVaultError.corrupt
        }
        var samples: [Float] = []
        samples.reserveCapacity(sampleCount)
        for _ in 0 ..< sampleCount {
            samples.append(
                Float(
                    bitPattern: try readUInt32(
                        from: data,
                        offset: &offset
                    )
                )
            )
        }
        return (samples, metadata)
    }

    private static func appendUInt32(
        _ value: UInt32,
        to data: inout Data
    ) {
        var bigEndian = value.bigEndian
        withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
    }

    private static func readUInt32(
        from data: Data,
        offset: inout Int
    ) throws -> UInt32 {
        let bytes = try readData(
            count: MemoryLayout<UInt32>.size,
            from: data,
            offset: &offset
        )
        return bytes.reduce(UInt32(0)) {
            ($0 << 8) | UInt32($1)
        }
    }

    private static func readData(
        count: Int,
        from data: Data,
        offset: inout Int
    ) throws -> Data {
        guard count >= 0, offset >= 0, offset + count <= data.count else {
            throw RecoveryVaultError.corrupt
        }
        defer { offset += count }
        return data.subdata(in: offset ..< offset + count)
    }
}

private extension JSONEncoder {
    static var recovery: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
