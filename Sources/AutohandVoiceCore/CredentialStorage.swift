import Foundation

/// Where the Talk sign-in key is kept. Keychain ties an item to the exact
/// code signature that created it, and ad-hoc signed builds get a new
/// signature on every update, so macOS would ask for the login password each
/// time. Those builds keep the key in an owner-only file instead, the same
/// way the Autohand CLI stores its token; builds signed with a stable
/// identity use Keychain.
public enum CredentialStorage: Equatable, Sendable {
    case keychain
    case ownerOnlyFile

    public static func choose(isAdHocSigned: Bool) -> CredentialStorage {
        isAdHocSigned ? .ownerOnlyFile : .keychain
    }
}

/// Stores an account credential in a file readable only by its owner
/// (0600), written atomically and excluded from backups.
public struct FileAccountCredentialVault: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func store(_ credential: AccountCredential) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(credential)
        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fileManager.createFile(
            atPath: temporary.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var installed = url
        try? installed.setResourceValues(values)
    }

    public func load() throws -> AccountCredential? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(
            AccountCredential.self,
            from: Data(contentsOf: url)
        )
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
