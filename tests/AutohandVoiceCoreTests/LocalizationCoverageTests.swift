import Foundation
import XCTest

final class LocalizationCoverageTests: XCTestCase {
    private let requiredLocales = ["en", "de", "es", "it", "pt"]

    func testEveryCatalogEntryHasAllShippingLocales() throws {
        let strings = try catalogStrings()

        for (key, rawEntry) in strings {
            let entry = try XCTUnwrap(rawEntry as? [String: Any])
            let localizations = try XCTUnwrap(
                entry["localizations"] as? [String: Any]
            )
            for locale in requiredLocales {
                let localization = try XCTUnwrap(
                    localizations[locale] as? [String: Any],
                    "Missing \(locale) localization for \(key)"
                )
                let unit = try XCTUnwrap(
                    localization["stringUnit"] as? [String: Any]
                )
                XCTAssertEqual(
                    unit["state"] as? String,
                    "translated",
                    "\(locale) is not translated for \(key)"
                )
                let value = try XCTUnwrap(unit["value"] as? String)
                XCTAssertFalse(
                    value.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty,
                    "Empty \(locale) localization for \(key)"
                )
                XCTAssertEqual(
                    placeholderTokens(in: value),
                    placeholderTokens(in: key),
                    "Placeholder mismatch for \(locale): \(key)"
                )
            }
        }
    }

    func testCatalogCoversEveryStaticSwiftUIStringLiteral() throws {
        let catalogKeys = Set(try catalogStrings().keys)
        let sourceDirectory = repositoryRoot
            .appendingPathComponent("Sources/AutohandVoice")
        let files = try FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "swift" }
        let expression = try NSRegularExpression(
            pattern:
                #"(?:Text|Label|Button|Section|Picker|Toggle|GroupBox|navigationTitle|confirmationDialog|help|accessibilityLabel)\(\s*"((?:[^"\\]|\\.)*)""#,
            options: [.dotMatchesLineSeparators]
        )
        var missing: Set<String> = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let fullRange = NSRange(source.startIndex..., in: source)
            for match in expression.matches(
                in: source,
                range: fullRange
            ) {
                guard
                    match.numberOfRanges > 1,
                    let range = Range(match.range(at: 1), in: source)
                else { continue }
                let raw = String(source[range])
                guard !raw.contains(#"\("#) else { continue }
                let key = decodedSwiftLiteral(raw)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                if !key.isEmpty, !catalogKeys.contains(key) {
                    missing.insert(key)
                }
            }
        }

        XCTAssertTrue(
            missing.isEmpty,
            "Static SwiftUI strings missing from catalog: "
                + missing.sorted().joined(separator: " | ")
        )
    }

    func testPseudolocalizationExpandsAndPreservesPlaceholders() {
        let source = "Recover %@ in %lld seconds"
        let pseudo = pseudolocalized(source)

        XCTAssertGreaterThan(pseudo.count, source.count)
        XCTAssertEqual(
            placeholderTokens(in: pseudo),
            placeholderTokens(in: source)
        )
        XCTAssertTrue(pseudo.hasPrefix("⟦"))
        XCTAssertTrue(pseudo.hasSuffix("⟧"))
    }

    private func catalogStrings() throws -> [String: Any] {
        let data = try Data(
            contentsOf: repositoryRoot
                .appendingPathComponent("Resources/Localizable.xcstrings")
        )
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        )
        return try XCTUnwrap(catalog["strings"] as? [String: Any])
    }

    private func placeholderTokens(in value: String) -> [String] {
        let expression = try! NSRegularExpression(
            pattern: #"%(\d+\$)?[-+# 0']*(\d+|\*)?(\.(\d+|\*))?[hlLjztq]*[@A-Za-z%]"#
        )
        let range = NSRange(value.startIndex..., in: value)
        return expression.matches(in: value, range: range).compactMap {
            Range($0.range, in: value).map { String(value[$0]) }
        }
    }

    private func decodedSwiftLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"\""#, with: #"""#)
            .replacingOccurrences(of: #"\n"#, with: "\n")
            .replacingOccurrences(of: #"\t"#, with: "\t")
            .replacingOccurrences(of: #"\\"#, with: #"\"#)
    }

    private func pseudolocalized(_ value: String) -> String {
        let placeholders = placeholderTokens(in: value)
        var protected = value
        for (index, placeholder) in placeholders.enumerated() {
            protected = protected.replacingOccurrences(
                of: placeholder,
                with: "___PLACEHOLDER_\(index)___"
            )
        }
        let map: [Character: Character] = [
            "a": "à", "e": "ë", "i": "ï", "o": "ô", "u": "ü",
            "A": "Å", "E": "Ë", "I": "Ï", "O": "Ö", "U": "Û",
        ]
        var result = String(protected.map { map[$0] ?? $0 })
        for (index, placeholder) in placeholders.enumerated() {
            result = result.replacingOccurrences(
                of: "___PLÅCËHÖLDËR_\(index)___",
                with: placeholder
            )
        }
        return "⟦\(result) ···⟧"
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
