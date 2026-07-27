import Foundation

public enum AudioImportError: LocalizedError, Equatable {
    case notAFileURL
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .notAFileURL:
            "Choose a local audio file."
        case let .unsupportedFormat(fileExtension):
            "“.\(fileExtension)” is not a supported audio format."
        }
    }
}

public enum AudioImportValidator {
    public static let supportedExtensions: Set<String> = [
        "aac", "aif", "aiff", "caf", "flac", "m4a", "mp3", "wav", "wave",
    ]

    public static func validate(_ url: URL) throws {
        guard url.isFileURL else {
            throw AudioImportError.notAFileURL
        }
        let fileExtension = url.pathExtension.lowercased()
        guard supportedExtensions.contains(fileExtension) else {
            throw AudioImportError.unsupportedFormat(
                fileExtension.isEmpty ? "unknown" : fileExtension
            )
        }
    }
}

public final class SecurityScopedResourceLease: @unchecked Sendable {
    private let lock = NSLock()
    private let stopHandler: @Sendable () -> Void
    private var shouldStop: Bool

    public var isActive: Bool {
        lock.withLock { shouldStop }
    }

    public init(
        start: @Sendable () -> Bool,
        stop: @escaping @Sendable () -> Void
    ) {
        stopHandler = stop
        shouldStop = start()
    }

    public convenience init(url: URL) {
        self.init(
            start: { url.startAccessingSecurityScopedResource() },
            stop: { url.stopAccessingSecurityScopedResource() }
        )
    }

    public func close() {
        let needsStop = lock.withLock {
            guard shouldStop else { return false }
            shouldStop = false
            return true
        }
        if needsStop {
            stopHandler()
        }
    }

    deinit {
        close()
    }
}
