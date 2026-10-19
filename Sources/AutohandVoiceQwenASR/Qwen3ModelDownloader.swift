import CryptoKit
import Foundation

public struct Qwen3DownloadProgress: Sendable, Equatable {
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let completedFiles: Int
    public let totalFiles: Int

    public init(
        completedBytes: Int64,
        totalBytes: Int64,
        completedFiles: Int,
        totalFiles: Int
    ) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedFiles = completedFiles
        self.totalFiles = totalFiles
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 1 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

public enum Qwen3ModelDownloadError: LocalizedError, Equatable {
    case unpinnedManifest
    case insecureRedirect(file: String)
    case httpStatus(file: String, status: Int)
    case sizeMismatch(file: String)
    case checksumMismatch(file: String)
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case transport(file: String, reason: String)
    case storage(String)

    public var errorDescription: String? {
        switch self {
        case .unpinnedManifest:
            return "The Qwen3-ASR model manifest is not pinned to a commit and checksums."
        case let .insecureRedirect(file):
            return "The download of \(file) was redirected to a non-HTTPS address and was stopped."
        case let .httpStatus(file, status):
            return "The download of \(file) failed with HTTP status \(status)."
        case let .sizeMismatch(file):
            return "The downloaded \(file) has an unexpected size and was discarded."
        case let .checksumMismatch(file):
            return "The downloaded \(file) failed SHA-256 validation and was discarded."
        case let .insufficientDiskSpace(required, available):
            let formatter = ByteCountFormatter()
            return "Not enough disk space to download Qwen3-ASR: \(formatter.string(fromByteCount: required)) needed, \(formatter.string(fromByteCount: available)) available."
        case let .transport(file, reason):
            return "The download of \(file) failed: \(reason)"
        case let .storage(reason):
            return "The Qwen3-ASR model could not be stored: \(reason)"
        }
    }
}

/// Downloads the pinned Qwen3-ASR files over HTTPS into the local model
/// cache. Each file streams into a staging folder inside the cache, is
/// bounded to its pinned size, is hashed while it downloads, and is renamed
/// into place only after its SHA-256 matches. A `.verified` marker records
/// the revision once every file is in place.
public final class Qwen3ModelDownloader: @unchecked Sendable {
    public static let stagingDirectoryName = ".downloads"
    static let markerName = ".verified"
    /// Free space kept beyond the download itself.
    static let diskSpaceMargin: Int64 = 256 * 1024 * 1024
    /// Progress is reported at most once per this many bytes, per file.
    static let progressGranularity: Int64 = 1024 * 1024

    public let manifest: Qwen3ModelManifest
    private let sessionConfiguration: URLSessionConfiguration

    public init(
        manifest: Qwen3ModelManifest = .default,
        sessionConfiguration: URLSessionConfiguration = Qwen3ModelDownloader.makeSessionConfiguration()
    ) {
        self.manifest = manifest
        self.sessionConfiguration = sessionConfiguration
    }

    /// Ephemeral, uncached, no cookies: the model is fetched anonymously and
    /// never duplicated into a URL cache.
    public static func makeSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.httpMaximumConnectionsPerHost = 1
        return configuration
    }

    /// Fast check used before loading: the marker names the pinned revision
    /// and every file has its pinned size. `verify(in:)` hashes the files.
    public func isInstalled(in directory: URL) -> Bool {
        let marker = directory.appendingPathComponent(Self.markerName)
        guard
            let data = try? Data(contentsOf: marker),
            String(decoding: data, as: UTF8.self) == manifest.revision
        else { return false }
        return manifest.files.allSatisfy {
            Self.fileSize(directory.appendingPathComponent($0.name)) == $0.size
        }
    }

    /// Hashes every pinned file. Returns false when any file is missing,
    /// has the wrong size, or has the wrong SHA-256.
    public func verify(in directory: URL) throws -> Bool {
        for file in manifest.files {
            let url = directory.appendingPathComponent(file.name)
            guard Self.fileSize(url) == file.size else { return false }
            guard try Self.sha256(of: url) == file.sha256 else { return false }
        }
        return true
    }

    /// Re-hashes every file and downloads any that are missing or corrupt.
    public func repair(
        in directory: URL,
        onProgress: (@Sendable (Qwen3DownloadProgress) -> Void)?
    ) async throws {
        try? FileManager.default.removeItem(
            at: directory.appendingPathComponent(Self.markerName)
        )
        try await install(into: directory, onProgress: onProgress)
    }

    public func install(
        into directory: URL,
        onProgress: (@Sendable (Qwen3DownloadProgress) -> Void)?
    ) async throws {
        guard manifest.isPinned else {
            throw Qwen3ModelDownloadError.unpinnedManifest
        }
        let total = manifest.totalBytes
        let fileCount = manifest.files.count
        // Already installed: report nothing, so callers never surface a
        // download UI for a model that is already on disk.
        if isInstalled(in: directory) { return }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw Qwen3ModelDownloadError.storage(error.localizedDescription)
        }
        let marker = directory.appendingPathComponent(Self.markerName)
        try? fileManager.removeItem(at: marker)

        // Keep already valid files; anything else is downloaded again.
        var pending: [Qwen3ModelFile] = []
        var completedBytes: Int64 = 0
        var completedFiles = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent(file.name)
            if Self.fileSize(url) == file.size,
               (try? Self.sha256(of: url)) == file.sha256 {
                completedBytes += file.size
                completedFiles += 1
            } else {
                pending.append(file)
            }
        }

        if !pending.isEmpty {
            let required = pending.reduce(0) { $0 + $1.size } + Self.diskSpaceMargin
            if let available = Self.availableCapacity(at: directory),
               available < required {
                throw Qwen3ModelDownloadError.insufficientDiskSpace(
                    requiredBytes: required,
                    availableBytes: available
                )
            }
        }

        if !pending.isEmpty {
            onProgress?(.init(
                completedBytes: completedBytes,
                totalBytes: total,
                completedFiles: completedFiles,
                totalFiles: fileCount
            ))
        }

        let staging = directory.appendingPathComponent(
            Self.stagingDirectoryName,
            isDirectory: true
        )
        try? fileManager.removeItem(at: staging)
        defer { try? fileManager.removeItem(at: staging) }
        if !pending.isEmpty {
            do {
                try fileManager.createDirectory(
                    at: staging,
                    withIntermediateDirectories: true
                )
            } catch {
                throw Qwen3ModelDownloadError.storage(error.localizedDescription)
            }
        }

        for file in pending {
            try Task.checkCancellation()
            let partial = staging.appendingPathComponent(file.name + ".partial")
            let base = completedBytes
            let doneFiles = completedFiles
            try await download(
                file,
                to: partial,
                onBytes: { received in
                    onProgress?(.init(
                        completedBytes: base + received,
                        totalBytes: total,
                        completedFiles: doneFiles,
                        totalFiles: fileCount
                    ))
                }
            )
            let destination = directory.appendingPathComponent(file.name)
            // rename(2) atomically replaces any previous file on the same
            // volume, so readers never see a partially written model.
            guard rename(partial.path, destination.path) == 0 else {
                let reason = String(cString: strerror(errno))
                throw Qwen3ModelDownloadError.storage(reason)
            }
            completedBytes += file.size
            completedFiles += 1
            onProgress?(.init(
                completedBytes: completedBytes,
                totalBytes: total,
                completedFiles: completedFiles,
                totalFiles: fileCount
            ))
        }

        do {
            try Data(manifest.revision.utf8).write(to: marker, options: .atomic)
        } catch {
            throw Qwen3ModelDownloadError.storage(error.localizedDescription)
        }
    }

    private func download(
        _ file: Qwen3ModelFile,
        to partial: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        guard FileManager.default.createFile(
            atPath: partial.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw Qwen3ModelDownloadError.storage("could not create \(partial.lastPathComponent)")
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: partial)
        } catch {
            throw Qwen3ModelDownloadError.storage(error.localizedDescription)
        }

        let delegate = Qwen3FileDownloadDelegate(
            file: file,
            handle: handle,
            granularity: Self.progressGranularity,
            onBytes: onBytes
        )
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        var request = URLRequest(url: manifest.remoteURL(for: file))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let task = session.dataTask(with: request)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    delegate.start(task: task, continuation: continuation)
                }
            } onCancel: {
                delegate.cancel()
            }
        } catch {
            try? FileManager.default.removeItem(at: partial)
            throw error
        }
    }

    static func fileSize(_ url: URL) -> Int64? {
        guard
            let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
            ]),
            values.isRegularFile == true,
            let size = values.fileSize
        else { return nil }
        return Int64(size)
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try autoreleasepool {
                try handle.read(upToCount: 4 * 1024 * 1024)
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return Self.hex(hasher.finalize())
    }

    static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    static func availableCapacity(at directory: URL) -> Int64? {
        var probe = directory
        while !FileManager.default.fileExists(atPath: probe.path),
              probe.pathComponents.count > 1 {
            probe.deleteLastPathComponent()
        }
        guard
            let values = try? probe.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
            ]),
            let capacity = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return capacity
    }
}

/// Streams one response body to disk, bounded by the pinned size and hashed
/// as it arrives. Resumes its continuation exactly once.
private final class Qwen3FileDownloadDelegate: NSObject,
    URLSessionDataDelegate, @unchecked Sendable {
    private let file: Qwen3ModelFile
    private let handle: FileHandle
    private let granularity: Int64
    private let onBytes: @Sendable (Int64) -> Void

    private let lock = NSLock()
    private var task: URLSessionTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasher = SHA256()
    private var received: Int64 = 0
    private var lastReported: Int64 = 0
    private var failure: Error?
    private var cancelled = false
    private var finished = false

    init(
        file: Qwen3ModelFile,
        handle: FileHandle,
        granularity: Int64,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) {
        self.file = file
        self.handle = handle
        self.granularity = granularity
        self.onBytes = onBytes
    }

    func start(
        task: URLSessionTask,
        continuation: CheckedContinuation<Void, Error>
    ) {
        lock.lock()
        if cancelled {
            finished = true
            lock.unlock()
            try? handle.close()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.task = task
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    private func fail(_ error: Error, task: URLSessionTask) {
        lock.lock()
        if failure == nil { failure = error }
        lock.unlock()
        task.cancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let http = response as? HTTPURLResponse else {
            fail(Qwen3ModelDownloadError.transport(
                file: file.name,
                reason: "unexpected response"
            ), task: dataTask)
            completionHandler(.cancel)
            return
        }
        guard http.statusCode == 200 else {
            fail(Qwen3ModelDownloadError.httpStatus(
                file: file.name,
                status: http.statusCode
            ), task: dataTask)
            completionHandler(.cancel)
            return
        }
        if response.expectedContentLength > file.size {
            fail(Qwen3ModelDownloadError.sizeMismatch(file: file.name), task: dataTask)
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        lock.lock()
        guard failure == nil, !cancelled else {
            lock.unlock()
            return
        }
        guard received + Int64(data.count) <= file.size else {
            lock.unlock()
            fail(Qwen3ModelDownloadError.sizeMismatch(file: file.name), task: dataTask)
            return
        }
        do {
            try handle.write(contentsOf: data)
        } catch {
            lock.unlock()
            fail(Qwen3ModelDownloadError.storage(error.localizedDescription), task: dataTask)
            return
        }
        hasher.update(data: data)
        received += Int64(data.count)
        let value = received
        let shouldReport = value - lastReported >= granularity
        if shouldReport { lastReported = value }
        lock.unlock()
        if shouldReport { onBytes(value) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard request.url?.scheme?.lowercased() == "https" else {
            fail(Qwen3ModelDownloadError.insecureRedirect(file: file.name), task: task)
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        guard !finished, let continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil
        let failure = self.failure
        let cancelled = self.cancelled
        let received = self.received
        let digest = Qwen3ModelDownloader.hex(hasher.finalize())
        lock.unlock()

        var closeError: Error?
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            closeError = error
        }

        if let failure {
            continuation.resume(throwing: failure)
        } else if cancelled {
            continuation.resume(throwing: CancellationError())
        } else if let error {
            continuation.resume(throwing: Qwen3ModelDownloadError.transport(
                file: file.name,
                reason: error.localizedDescription
            ))
        } else if let closeError {
            continuation.resume(throwing: Qwen3ModelDownloadError.storage(
                closeError.localizedDescription
            ))
        } else if received != file.size {
            continuation.resume(throwing: Qwen3ModelDownloadError.sizeMismatch(file: file.name))
        } else if digest != file.sha256 {
            continuation.resume(throwing: Qwen3ModelDownloadError.checksumMismatch(file: file.name))
        } else {
            continuation.resume()
        }
    }
}
