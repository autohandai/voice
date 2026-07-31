import Foundation

public enum LocalDataResetError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case unsafeLocation(String)
    case incomplete([String])

    public var errorDescription: String? {
        switch self {
        case let .unsafeLocation(path):
            "Reset refused an unsafe data location: \(path)"
        case let .incomplete(locations):
            "Local data could not be removed from: "
                + locations.joined(separator: ", ")
        }
    }
}

public struct LocalDataResetEntry:
    Equatable,
    Identifiable,
    Sendable
{
    public let id: String
    public let path: String
    public let existedBeforeReset: Bool
    public let verifiedAbsent: Bool
    public let failure: String?

    public init(
        id: String,
        path: String,
        existedBeforeReset: Bool,
        verifiedAbsent: Bool,
        failure: String?
    ) {
        self.id = id
        self.path = path
        self.existedBeforeReset = existedBeforeReset
        self.verifiedAbsent = verifiedAbsent
        self.failure = failure
    }
}

public struct LocalDataResetReport: Equatable, Sendable {
    public let entries: [LocalDataResetEntry]
    public let recoveryKeyDeleted: Bool
    public let recoveryKeyFailure: String?

    public var succeeded: Bool {
        recoveryKeyDeleted
            && recoveryKeyFailure == nil
            && entries.allSatisfy {
                $0.verifiedAbsent && $0.failure == nil
            }
    }

    public var removedLocationCount: Int {
        entries.filter {
            $0.existedBeforeReset && $0.verifiedAbsent
        }.count
    }
}

/// Deletes and then verifies the complete, explicit owner-only data ledger.
///
/// The recovery key is deleted even if an unrelated file removal fails. This
/// makes any remaining encrypted recovery artifact cryptographically
/// inaccessible while preserving a complete failure report for the UI.
public struct LocalDataResetter: Sendable {
    private let urls: [URL]
    private let keyProvider: any RecoveryKeyProviding

    public init(
        urls: [URL] = Brand.ownerOnlyDataURLs,
        keyProvider: any RecoveryKeyProviding =
            KeychainRecoveryKeyProvider()
    ) throws {
        let standardized = Self.unique(urls)
        for url in standardized {
            guard Self.isSafe(url) else {
                throw LocalDataResetError.unsafeLocation(url.path)
            }
        }
        self.urls = standardized
        self.keyProvider = keyProvider
    }

    public func reset() -> LocalDataResetReport {
        let manager = FileManager.default
        var entries: [LocalDataResetEntry] = []
        for url in urls {
            let existed = manager.fileExists(atPath: url.path)
            var failure: String?
            if existed {
                do {
                    try manager.removeItem(at: url)
                } catch {
                    failure = error.localizedDescription
                }
            }
            let absent = !manager.fileExists(atPath: url.path)
            if !absent, failure == nil {
                failure = "The location still exists after deletion."
            }
            entries.append(
                LocalDataResetEntry(
                    id: url.lastPathComponent,
                    path: url.path,
                    existedBeforeReset: existed,
                    verifiedAbsent: absent,
                    failure: failure
                )
            )
        }

        var keyDeleted = false
        var keyFailure: String?
        do {
            try keyProvider.deleteKey()
            keyDeleted = true
        } catch {
            keyFailure = error.localizedDescription
        }
        return LocalDataResetReport(
            entries: entries,
            recoveryKeyDeleted: keyDeleted,
            recoveryKeyFailure: keyFailure
        )
    }

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            return seen.insert(standardized.path).inserted
                ? standardized
                : nil
        }
    }

    private static func isSafe(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let path = url.standardizedFileURL.path
        guard
            path != "/",
            path != FileManager.default.homeDirectoryForCurrentUser.path,
            path.count > 8
        else { return false }
        return url.lastPathComponent != "."
            && url.lastPathComponent != ".."
    }
}
