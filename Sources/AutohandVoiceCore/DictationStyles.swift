import Foundation

public enum DictationStyleSource: String, Codable, Sendable {
    case global
    case appProfile = "app_profile"
    case temporary
}

public struct DictationStylePreset:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public var name: String
    public var cleanupLevel: CleanupLevel
    public var automaticTerminalPunctuation: Bool
    public var vocabularyEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        cleanupLevel: CleanupLevel,
        automaticTerminalPunctuation: Bool,
        vocabularyEnabled: Bool = true
    ) {
        self.id = id
        self.name = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(80)
        )
        self.cleanupLevel = cleanupLevel
        self.automaticTerminalPunctuation =
            automaticTerminalPunctuation
        self.vocabularyEnabled = vocabularyEnabled
    }

    public var isValid: Bool {
        !name.isEmpty && name.count <= 80
    }

    public static let literal = DictationStylePreset(
        id: UUID(uuidString: "A1100000-0000-4000-8000-000000000001")!,
        name: "Literal",
        cleanupLevel: .literal,
        automaticTerminalPunctuation: false
    )

    public static let light = DictationStylePreset(
        id: UUID(uuidString: "A1100000-0000-4000-8000-000000000002")!,
        name: "Light",
        cleanupLevel: .light,
        automaticTerminalPunctuation: false
    )

    public static let medium = DictationStylePreset(
        id: UUID(uuidString: "A1100000-0000-4000-8000-000000000003")!,
        name: "Medium",
        cleanupLevel: .medium,
        automaticTerminalPunctuation: true
    )

    public static let builtIns: [DictationStylePreset] = [
        .literal,
        .light,
        .medium,
    ]
}

public enum DictationStyleStoreError:
    Error,
    Equatable,
    LocalizedError
{
    case invalidStyle
    case duplicateIdentifier
    case tooManyStyles
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidStyle:
            "Every dictation style needs a valid name."
        case .duplicateIdentifier:
            "Dictation style identifiers must be unique."
        case .tooManyStyles:
            "Custom dictation styles are limited to 32."
        case .fileTooLarge:
            "The dictation style file exceeds its storage limit."
        }
    }
}

public struct DictationStyleStore: Sendable {
    public static let maximumStyles = 32
    public static let maximumFileBytes = 256 * 1_024
    public let url: URL

    public init(url: URL = Brand.dictationStylesURL) {
        self.url = url
    }

    public static func all(
        custom: [DictationStylePreset]
    ) -> [DictationStylePreset] {
        DictationStylePreset.builtIns + custom.filter { candidate in
            !DictationStylePreset.builtIns.contains {
                $0.id == candidate.id
            }
        }
    }

    public static func validate(
        _ styles: [DictationStylePreset]
    ) throws {
        guard styles.count <= maximumStyles else {
            throw DictationStyleStoreError.tooManyStyles
        }
        guard styles.allSatisfy(\.isValid) else {
            throw DictationStyleStoreError.invalidStyle
        }
        guard Set(styles.map(\.id)).count == styles.count else {
            throw DictationStyleStoreError.duplicateIdentifier
        }
        guard !styles.contains(where: { candidate in
            DictationStylePreset.builtIns.contains {
                $0.id == candidate.id
            }
        }) else {
            throw DictationStyleStoreError.duplicateIdentifier
        }
    }

    public func load() throws -> [DictationStylePreset] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let size = (
            try FileManager.default.attributesOfItem(
                atPath: url.path
            )[.size] as? NSNumber
        )?.intValue ?? 0
        guard size <= Self.maximumFileBytes else {
            throw DictationStyleStoreError.fileTooLarge
        }
        let styles = try JSONDecoder().decode(
            [DictationStylePreset].self,
            from: Data(contentsOf: url)
        )
        try Self.validate(styles)
        return styles
    }

    public func save(_ styles: [DictationStylePreset]) throws {
        try Self.validate(styles)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(styles)
        guard data.count <= Self.maximumFileBytes else {
            throw DictationStyleStoreError.fileTooLarge
        }
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

public enum TemporaryStylePolicy {
    public static let inactivityExpiration: TimeInterval = 15 * 60

    public static func isActive(
        expiresAtUptime: TimeInterval?,
        nowUptime: TimeInterval
    ) -> Bool {
        guard let expiresAtUptime else { return false }
        return expiresAtUptime > nowUptime
    }
}
