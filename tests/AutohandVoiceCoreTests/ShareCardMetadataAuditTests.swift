import Foundation
import XCTest
@testable import AutohandVoiceCore

final class ShareCardMetadataAuditTests: XCTestCase {
    func testRejectsTextMetadataAndAcceptsMinimalPNG() {
        let minimal = png(chunks: [
            ("IHDR", Data(repeating: 0, count: 13)),
            ("IDAT", Data()),
            ("IEND", Data()),
        ])
        let withText = png(chunks: [
            ("IHDR", Data(repeating: 0, count: 13)),
            ("tEXt", Data("transcript=secret".utf8)),
            ("IEND", Data()),
        ])

        XCTAssertTrue(
            ShareCardMetadataAudit.hasNoHiddenTextMetadata(
                pngData: minimal
            )
        )
        XCTAssertFalse(
            ShareCardMetadataAudit.hasNoHiddenTextMetadata(
                pngData: withText
            )
        )
    }

    private func png(chunks: [(String, Data)]) -> Data {
        var data = Data([
            0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A,
        ])
        for (type, payload) in chunks {
            let length = UInt32(payload.count).bigEndian
            withUnsafeBytes(of: length) { data.append(contentsOf: $0) }
            data.append(Data(type.utf8))
            data.append(payload)
            data.append(Data(repeating: 0, count: 4))
        }
        return data
    }
}
