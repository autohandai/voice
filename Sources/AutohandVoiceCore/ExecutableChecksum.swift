import CryptoKit
import Foundation

public enum ExecutableChecksum {
    private static let bufferSize = 64 * 1024

    public static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var digest = SHA256()
        while let data = try handle.read(upToCount: bufferSize),
              !data.isEmpty
        {
            digest.update(data: data)
        }

        return digest.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
