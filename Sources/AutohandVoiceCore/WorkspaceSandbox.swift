import Foundation

/// The folder Talk may read and write when it uses tools. Every path is
/// resolved inside it (symlinks included); anything that would leave it is
/// refused, and file sizes are bounded.
public struct WorkspaceSandbox: Sendable {
    public static let maximumReadBytes = 256 * 1_024
    public static let maximumWriteBytes = 1_024 * 1_024
    public static let maximumListedEntries = 200

    public enum Failure: Error, Equatable, LocalizedError {
        case outsideWorkspace
        case notFound
        case notAFile
        case tooLarge
        case notText

        public var errorDescription: String? {
            switch self {
            case .outsideWorkspace: "That path is outside the workspace folder."
            case .notFound: "There's no file or folder at that path."
            case .notAFile: "That path is a folder, not a file."
            case .tooLarge: "That file is too large for Talk to handle."
            case .notText: "That file isn't plain text."
            }
        }
    }

    public struct Entry: Equatable, Sendable {
        public let name: String
        public let isDirectory: Bool
        public let size: Int64
    }

    public static var defaultRoot: URL {
        FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Resolves a workspace-relative path, following symlinks, and refuses
    /// anything outside the workspace.
    public func resolve(_ path: String) throws -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else {
            throw Failure.outsideWorkspace
        }
        let candidate = root.appendingPathComponent(trimmed)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path == root.path || candidate.path.hasPrefix(rootPath) else {
            throw Failure.outsideWorkspace
        }
        return candidate
    }

    public func list(_ path: String) throws -> [Entry] {
        let url = try resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        else { throw Failure.notFound }
        guard isDirectory.boolValue else { throw Failure.notAFile }
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .prefix(Self.maximumListedEntries)
        return names.map { name in
            let child = url.appendingPathComponent(name)
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return Entry(
                name: name,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0)
            )
        }
    }

    public func read(_ path: String) throws -> String {
        let url = try resolve(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        else { throw Failure.notFound }
        guard !isDirectory.boolValue else { throw Failure.notAFile }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= Self.maximumReadBytes else { throw Failure.tooLarge }
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw Failure.notText
        }
        return text
    }

    /// Creates or replaces a text file, making folders as needed.
    public func write(_ path: String, contents: String) throws {
        guard contents.utf8.count <= Self.maximumWriteBytes else { throw Failure.tooLarge }
        let url = try resolve(path)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            throw Failure.notAFile
        }
        let folder = url.deletingLastPathComponent()
        // Re-check the parent after resolving, in case it is a symlink out.
        _ = try resolve(
            String(folder.path.dropFirst(root.path.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
    }

    public func exists(_ path: String) -> Bool {
        guard let url = try? resolve(path) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
