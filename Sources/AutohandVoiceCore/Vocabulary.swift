import Foundation

public enum VocabularyLimits {
    public static let maximumRules = 2_000
    public static let maximumSourceCharacters = 256
    public static let maximumReplacementCharacters = 4_000
    public static let maximumFileBytes = 2 * 1_024 * 1_024
}

public enum VocabularyError: LocalizedError, Equatable {
    case tooManyRules
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .tooManyRules:
            "Vocabulary is limited to \(VocabularyLimits.maximumRules) replacements."
        case .fileTooLarge:
            "Vocabulary files must be smaller than 2 MB."
        }
    }
}

public struct ReplacementRule: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var source: String
    public var replacement: String

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String
    ) {
        self.id = id
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.replacement = replacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        !source.isEmpty
            && !replacement.isEmpty
            && source.count <= VocabularyLimits.maximumSourceCharacters
            && replacement.count <= VocabularyLimits.maximumReplacementCharacters
    }
}

public enum VocabularyProcessor {
    public static func apply(
        to text: String,
        rules: [ReplacementRule],
        locale: Locale = .current
    ) -> String {
        let ordered = rules
            .prefix(VocabularyLimits.maximumRules)
            .filter(\.isValid)
            .sorted {
                if $0.source.count != $1.source.count {
                    return $0.source.count > $1.source.count
                }
                let comparison = $0.source.localizedStandardCompare($1.source)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        guard !ordered.isEmpty else { return text }

        let alternatives = ordered.map {
            NSRegularExpression.escapedPattern(for: $0.source)
        }
        let pattern = "(?<![\\p{L}\\p{N}_])(?:"
            + alternatives.joined(separator: "|")
            + ")(?![\\p{L}\\p{N}_])"
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return text
        }

        let original = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: original.length)
        )
        let output = NSMutableString(string: text)
        for match in matches.reversed() {
            let matched = original.substring(with: match.range)
            guard let rule = ordered.first(where: {
                $0.source.compare(
                    matched,
                    options: [.caseInsensitive],
                    range: nil,
                    locale: locale
                ) == .orderedSame
            }) else { continue }
            output.replaceCharacters(
                in: match.range,
                with: preserveCase(
                    from: matched,
                    replacement: rule.replacement,
                    locale: locale
                )
            )
        }
        return output as String
    }

    private static func preserveCase(
        from source: String,
        replacement: String,
        locale: Locale
    ) -> String {
        let letters = source.filter(\.isLetter)
        guard !letters.isEmpty else { return replacement }
        if source == source.uppercased(with: locale) {
            return replacement.uppercased(with: locale)
        }
        if source == source.lowercased(with: locale) {
            return replacement
        }
        let lower = source.lowercased(with: locale)
        let capitalized = lower.prefix(1).uppercased(with: locale)
            + lower.dropFirst()
        if source == capitalized {
            return replacement.prefix(1).uppercased(with: locale)
                + replacement.dropFirst()
        }
        return replacement
    }
}

public struct VocabularyImportError: Equatable, Sendable {
    public let row: Int
    public let message: String
}

public struct VocabularyImportResult: Equatable, Sendable {
    public let rules: [ReplacementRule]
    public let errors: [VocabularyImportError]
}

public enum VocabularyImporter {
    public static func csv(_ text: String) -> VocabularyImportResult {
        var rules: [ReplacementRule] = []
        var errors: [VocabularyImportError] = []
        for parsed in parseCSV(text) {
            let row = parsed.row
            if let error = parsed.error {
                errors.append(.init(row: row, message: error))
                continue
            }
            let columns = parsed.columns
            guard !columns.allSatisfy({
                $0.trimmingCharacters(in: .whitespaces).isEmpty
            }) else { continue }
            if row == 1,
               columns.first?.lowercased() == "source",
               columns.dropFirst().first?.lowercased() == "replacement" {
                continue
            }
            guard columns.count == 2 else {
                errors.append(
                    .init(row: row, message: "Expected source and replacement")
                )
                continue
            }
            let rule = ReplacementRule(
                source: columns[0],
                replacement: columns[1]
            )
            if rule.isValid {
                rules.append(rule)
            } else {
                errors.append(
                    .init(row: row, message: "Both values are required")
                )
            }
        }
        return .init(rules: rules, errors: errors)
    }

    public static func json(_ data: Data) throws -> [ReplacementRule] {
        guard data.count <= VocabularyLimits.maximumFileBytes else {
            throw VocabularyError.fileTooLarge
        }
        return try JSONDecoder().decode([ReplacementRule].self, from: data)
            .filter(\.isValid)
    }

    private struct ParsedCSVRow {
        let row: Int
        let columns: [String]
        let error: String?
    }

    private static func parseCSV(_ text: String) -> [ParsedCSVRow] {
        var rows: [ParsedCSVRow] = []
        var fields: [String] = []
        var field = ""
        var quoted = false
        var error: String?
        var physicalRow = 1
        var recordRow = 1
        var index = text.startIndex

        func finishRecord() {
            fields.append(field)
            rows.append(
                .init(row: recordRow, columns: fields, error: error)
            )
            fields = []
            field = ""
            error = nil
            recordRow = physicalRow
        }

        while index < text.endIndex {
            let character = text[index]
            if character == "\"" {
                let next = text.index(after: index)
                if quoted, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else if quoted {
                    quoted = false
                } else if field.isEmpty {
                    quoted = true
                } else {
                    error = error ?? "Unexpected quote"
                }
            } else if character == ",", !quoted {
                fields.append(field)
                field = ""
            } else if character.isNewline {
                physicalRow += 1
                if quoted {
                    field.append("\n")
                } else {
                    finishRecord()
                    recordRow = physicalRow
                }
            } else {
                field.append(character)
            }
            index = text.index(after: index)
        }

        if quoted {
            error = error ?? "Unterminated quoted field"
        }
        if !field.isEmpty || !fields.isEmpty || error != nil {
            finishRecord()
        }
        return rows
    }
}

public enum VocabularyExporter {
    public static func json(_ rules: [ReplacementRule]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(rules.filter(\.isValid))
    }

    public static func csv(_ rules: [ReplacementRule]) -> String {
        let rows = rules.filter(\.isValid).map {
            "\(escapeCSV($0.source)),\(escapeCSV($0.replacement))"
        }
        return (["source,replacement"] + rows).joined(separator: "\n") + "\n"
    }

    private static func escapeCSV(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
        else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

public struct VocabularyStore: Sendable {
    public let url: URL

    public init(url: URL = Brand.vocabularyURL) {
        self.url = url
    }

    public func load() throws -> [ReplacementRule] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize <= VocabularyLimits.maximumFileBytes else {
            throw VocabularyError.fileTooLarge
        }
        let rules = try JSONDecoder().decode(
            [ReplacementRule].self,
            from: Data(contentsOf: url)
        )
        guard rules.count <= VocabularyLimits.maximumRules else {
            throw VocabularyError.tooManyRules
        }
        return rules.filter(\.isValid)
    }

    public func save(_ rules: [ReplacementRule]) throws {
        guard rules.count <= VocabularyLimits.maximumRules else {
            throw VocabularyError.tooManyRules
        }
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        try VocabularyExporter.json(rules)
            .write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
