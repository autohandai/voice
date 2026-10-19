import Foundation
import Security

/// Facts about this app's own code signature.
enum CodeSignature {
    /// True for ad-hoc signed (or unsigned) builds, whose signature changes
    /// with every build.
    static let isAdHoc: Bool = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return true }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode
        else { return true }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let dictionary = information as? [String: Any]
        else { return true }
        let flags = (dictionary[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        return isAdHoc || dictionary[kSecCodeInfoIdentifier as String] == nil
    }()
}
