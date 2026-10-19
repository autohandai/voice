import CryptoKit
import Foundation

/// One downloadable model file, pinned to an exact revision and checksum.
public struct LocalModelFile: Equatable, Sendable {
    public let name: String
    public let url: URL
    public let size: Int64
    /// Lowercase hex SHA-256 of the whole file.
    public let sha256: String

    public init(name: String, url: URL, size: Int64, sha256: String) {
        self.name = name
        self.url = url
        self.size = size
        self.sha256 = sha256.lowercased()
    }
}

/// Models Talk can run on this Mac.
public struct LocalModelManifest: Equatable, Sendable {
    public let displayName: String
    public let directoryName: String
    public let file: LocalModelFile

    /// PrismML Ternary Bonsai 2 (2B, Qwen3.5 base, Apache-2.0), Q2_0 GGUF.
    public static let bonsai2B = LocalModelManifest(
        displayName: "Ternary Bonsai 2 (2B)",
        directoryName: "ternary-bonsai-2-2b",
        file: LocalModelFile(
            name: "Ternary-Bonsai-2-2B-Q2_0.gguf",
            url: URL(
                string: "https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf/resolve/683f7be2629342a50987627b40881e54761a2430/Ternary-Bonsai-2-2B-Q2_0.gguf"
            )!,
            size: 546_689_504,
            sha256: "c2893fa6f951daee8b7263d5f49b455e57989ef56417a22125b03566dc560650"
        )
    )

    public var directory: URL {
        Brand.localModelsDirectory.appendingPathComponent(
            directoryName,
            isDirectory: true
        )
    }
}

/// Downloads a model file once, verifies its size and SHA-256 before it is
/// used, and installs it atomically. A file that fails verification is
/// deleted, never loaded.
public enum VerifiedModelDownload {
    public enum Failure: Error, LocalizedError, Equatable {
        case badResponse(Int)
        case sizeMismatch
        case checksumMismatch

        public var errorDescription: String? {
            switch self {
            case let .badResponse(status):
                "The model download failed (HTTP \(status))."
            case .sizeMismatch:
                "The downloaded model has the wrong size."
            case .checksumMismatch:
                "The downloaded model didn't match its checksum, so it was deleted."
            }
        }
    }

    public static func isInstalled(
        _ file: LocalModelFile,
        in directory: URL
    ) -> Bool {
        let url = directory.appendingPathComponent(file.name)
        guard
            let size = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? NSNumber,
            size.int64Value == file.size,
            let marker = try? String(
                contentsOf: markerURL(for: file, in: directory),
                encoding: .utf8
            )
        else { return false }
        return marker == file.sha256
    }

    public static func ensure(
        _ file: LocalModelFile,
        in directory: URL,
        session: URLSession = .shared,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = directory.appendingPathComponent(file.name)
        if isInstalled(file, in: directory) {
            onProgress(1)
            return destination
        }
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let partial = directory.appendingPathComponent(file.name + ".partial")
        try? fileManager.removeItem(at: partial)
        try? fileManager.removeItem(at: markerURL(for: file, in: directory))
        do {
            let (downloaded, response) = try await session.download(
                for: URLRequest(url: file.url),
                delegate: ProgressDelegate(
                    expected: file.size,
                    onProgress: onProgress
                )
            )
            if let http = response as? HTTPURLResponse,
               !(200..<300).contains(http.statusCode) {
                try? fileManager.removeItem(at: downloaded)
                throw Failure.badResponse(http.statusCode)
            }
            try fileManager.moveItem(at: downloaded, to: partial)
            try Task.checkCancellation()
            let size = (try fileManager.attributesOfItem(
                atPath: partial.path
            )[.size] as? NSNumber)?.int64Value
            guard size == file.size else { throw Failure.sizeMismatch }
            guard try sha256(of: partial) == file.sha256 else {
                throw Failure.checksumMismatch
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: partial, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var installed = destination
            try? installed.setResourceValues(values)
            try file.sha256.write(
                to: markerURL(for: file, in: directory),
                atomically: true,
                encoding: .utf8
            )
            onProgress(1)
            return destination
        } catch {
            try? fileManager.removeItem(at: partial)
            throw error
        }
    }

    public static func remove(_ file: LocalModelFile, in directory: URL) throws {
        let fileManager = FileManager.default
        for url in [
            directory.appendingPathComponent(file.name),
            markerURL(for: file, in: directory),
        ] where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func markerURL(
        for file: LocalModelFile,
        in directory: URL
    ) -> URL {
        directory.appendingPathComponent(file.name + ".sha256")
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1_024 * 1_024),
              !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate,
        @unchecked Sendable
    {
        let expected: Int64
        let onProgress: @Sendable (Double) -> Void

        init(expected: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
            self.expected = expected
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            let total = totalBytesExpectedToWrite > 0
                ? totalBytesExpectedToWrite : expected
            guard total > 0 else { return }
            // Leave the last step for verification.
            onProgress(min(0.99, Double(totalBytesWritten) / Double(total)))
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {}
    }
}

/// Builds the ChatML prompt Bonsai (Qwen3.5) expects, with thinking switched
/// off so spoken replies start straight away.
public enum BonsaiPrompt {
    public static func text(for messages: [TalkMessage]) -> String {
        var prompt = ""
        for message in messages {
            prompt += "<|im_start|>\(message.role.rawValue)\n"
            prompt += sanitized(message.content)
            prompt += "<|im_end|>\n"
        }
        prompt += "<|im_start|>assistant\n<think>\n\n</think>\n\n"
        return prompt
    }

    /// Text from the conversation must not be able to open or close a turn.
    private static func sanitized(_ text: String) -> String {
        text.replacingOccurrences(of: "<|im_start|>", with: "")
            .replacingOccurrences(of: "<|im_end|>", with: "")
            .replacingOccurrences(of: "<|endoftext|>", with: "")
    }
}

/// Removes any `<think>…</think>` reasoning from streamed model output, even
/// when the tags arrive split across pieces, so it is never shown or spoken.
public struct ThinkingFilter: Sendable {
    private static let open = "<think>"
    private static let close = "</think>"
    private var pending = ""
    private var thinking = false
    private var atStart = true

    public init() {}

    public mutating func append(_ piece: String) -> String {
        pending += piece
        var output = ""
        while true {
            if thinking {
                guard let end = pending.range(of: Self.close) else {
                    // Keep only a possible partial closing tag.
                    pending = String(pending.suffix(Self.close.count - 1))
                    return trimmedStart(output)
                }
                pending = String(pending[end.upperBound...])
                thinking = false
                atStart = true
                continue
            }
            if let start = pending.range(of: Self.open) {
                output += pending[..<start.lowerBound]
                pending = String(pending[start.upperBound...])
                thinking = true
                continue
            }
            // Hold back a tail that could be the start of "<think>".
            let hold = Self.partialPrefixLength(of: pending, tag: Self.open)
            output += pending.dropLast(hold)
            pending = String(pending.suffix(hold))
            return trimmedStart(output)
        }
    }

    public mutating func finish() -> String {
        defer { pending = "" }
        return thinking ? "" : trimmedStart(pending)
    }

    /// Drops the blank lines that follow a closed thinking block.
    private mutating func trimmedStart(_ text: String) -> String {
        guard atStart else { return text }
        let trimmed = String(text.drop(while: { $0.isNewline || $0 == " " }))
        if !trimmed.isEmpty { atStart = false }
        return trimmed
    }

    private static func partialPrefixLength(of text: String, tag: String) -> Int {
        let maximum = min(text.count, tag.count - 1)
        guard maximum > 0 else { return 0 }
        for length in stride(from: maximum, through: 1, by: -1)
            where tag.hasPrefix(String(text.suffix(length))) {
            return length
        }
        return 0
    }
}
