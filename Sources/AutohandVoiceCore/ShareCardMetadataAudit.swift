import Foundation

public enum ShareCardMetadataAudit {
    private static let prohibitedChunks: Set<String> = [
        "tEXt",
        "zTXt",
        "iTXt",
        "eXIf",
    ]

    public static func hasNoHiddenTextMetadata(
        pngData: Data
    ) -> Bool {
        let signature = Data([
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A,
        ])
        guard pngData.starts(with: signature) else { return false }
        var offset = signature.count
        while offset + 12 <= pngData.count {
            let length = pngData[offset ..< offset + 4].reduce(0) {
                ($0 << 8) | Int($1)
            }
            let typeRange = (offset + 4) ..< (offset + 8)
            guard
                let type = String(
                    data: pngData[typeRange],
                    encoding: .ascii
                ),
                length >= 0,
                offset + 12 + length <= pngData.count
            else { return false }
            if prohibitedChunks.contains(type) {
                return false
            }
            offset += 12 + length
            if type == "IEND" {
                return offset == pngData.count
            }
        }
        return false
    }
}
