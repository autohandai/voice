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
    public var isStarred: Bool
    public var usageCount: Int
    public var lastUsedAt: Date?

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        isStarred: Bool = false,
        usageCount: Int = 0,
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.replacement = replacement
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.isStarred = isStarred
        self.usageCount = min(max(usageCount, 0), 1_000_000_000)
        self.lastUsedAt = lastUsedAt
    }

    public var isValid: Bool {
        !source.isEmpty
            && !replacement.isEmpty
            && source.count <= VocabularyLimits.maximumSourceCharacters
            && replacement.count <= VocabularyLimits.maximumReplacementCharacters
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case source
        case replacement
        case isStarred
        case usageCount
        case lastUsedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            source: try container.decode(String.self, forKey: .source),
            replacement: try container.decode(
                String.self,
                forKey: .replacement
            ),
            isStarred: try container.decodeIfPresent(
                Bool.self,
                forKey: .isStarred
            ) ?? false,
            usageCount: try container.decodeIfPresent(
                Int.self,
                forKey: .usageCount
            ) ?? 0,
            lastUsedAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastUsedAt
            )
        )
    }
}

public struct VocabularyApplicationResult: Equatable, Sendable {
    public let text: String
    public let matchedRuleIDs: [UUID]
}

public struct VocabularySuggestion:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public let source: String
    public let replacement: String
    public let createdAt: Date
    public var observationCount: Int

    public init(
        id: UUID = UUID(),
        source: String,
        replacement: String,
        createdAt: Date = Date(),
        observationCount: Int = 1
    ) {
        self.id = id
        self.source = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.replacement = replacement.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.createdAt = createdAt
        self.observationCount = min(
            max(observationCount, 1),
            1_000_000
        )
    }

    public var isValid: Bool {
        let sourceKey = VocabularySuggestionPolicy.normalizedKey(source)
        let replacementKey =
            VocabularySuggestionPolicy.normalizedKey(replacement)
        return !sourceKey.isEmpty
            && sourceKey != replacementKey
            && source.count <= VocabularyLimits.maximumSourceCharacters
            && replacement.count
                <= VocabularyLimits.maximumReplacementCharacters
    }
}

public enum VocabularySuggestionPolicy {
    public static let maximumSuggestions = 100
    public static let maximumFileBytes = 256 * 1_024

    public static func normalizedKey(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "ʼ", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
    }

    public static func merge(
        _ suggestion: VocabularySuggestion,
        into existing: [VocabularySuggestion]
    ) -> [VocabularySuggestion] {
        guard suggestion.isValid else { return existing }
        var result = existing.filter(\.isValid)
        let sourceKey = normalizedKey(suggestion.source)
        let replacementKey = normalizedKey(suggestion.replacement)
        if let index = result.firstIndex(where: {
            normalizedKey($0.source) == sourceKey
                && normalizedKey($0.replacement) == replacementKey
        }) {
            result[index].observationCount = min(
                1_000_000,
                result[index].observationCount
                    + suggestion.observationCount
            )
        } else {
            result.append(suggestion)
        }
        return Array(
            result.sorted {
                if $0.observationCount != $1.observationCount {
                    return $0.observationCount > $1.observationCount
                }
                if $0.createdAt != $1.createdAt {
                    return $0.createdAt > $1.createdAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
            .prefix(maximumSuggestions)
        )
    }
}

public struct VocabularySuggestionStore: Sendable {
    public let url: URL

    public init(url: URL = Brand.vocabularySuggestionsURL) {
        self.url = url
    }

    public func load() throws -> [VocabularySuggestion] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0)
            <= VocabularySuggestionPolicy.maximumFileBytes
        else {
            throw VocabularyError.fileTooLarge
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            [VocabularySuggestion].self,
            from: Data(contentsOf: url)
        )
        return decoded.reduce(into: [VocabularySuggestion]()) {
            $0 = VocabularySuggestionPolicy.merge($1, into: $0)
        }
    }

    public func observeCorrection(
        source: String,
        replacement: String,
        enabled: Bool,
        at date: Date = Date()
    ) throws {
        guard enabled else { return }
        let suggestion = VocabularySuggestion(
            source: source,
            replacement: replacement,
            createdAt: date
        )
        guard suggestion.isValid else { return }
        try save(
            VocabularySuggestionPolicy.merge(
                suggestion,
                into: try load()
            )
        )
    }

    public func remove(_ id: UUID) throws {
        try save(try load().filter { $0.id != id })
    }

    public func save(_ suggestions: [VocabularySuggestion]) throws {
        let normalized = suggestions.reduce(
            into: [VocabularySuggestion]()
        ) {
            $0 = VocabularySuggestionPolicy.merge($1, into: $0)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(normalized)
        guard data.count <= VocabularySuggestionPolicy.maximumFileBytes else {
            throw VocabularyError.fileTooLarge
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if normalized.isEmpty {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            return
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

public enum VocabularyRanking {
    public static func normalized(
        _ rules: [ReplacementRule]
    ) -> [ReplacementRule] {
        var preferred: [String: ReplacementRule] = [:]
        for rule in rules.prefix(VocabularyLimits.maximumRules)
            where rule.isValid
        {
            let key = rule.source.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            guard let existing = preferred[key] else {
                preferred[key] = rule
                continue
            }
            if ranksBefore(rule, existing) {
                preferred[key] = rule
            }
        }
        return preferred.values.sorted(by: ranksBefore)
    }

    public static func recordUsage(
        ruleIDs: [UUID],
        in rules: [ReplacementRule],
        at date: Date = Date()
    ) -> [ReplacementRule] {
        let counts = Dictionary(
            grouping: ruleIDs,
            by: { $0 }
        ).mapValues(\.count)
        return rules.map { rule in
            guard let increment = counts[rule.id] else { return rule }
            var updated = rule
            updated.usageCount = min(
                1_000_000_000,
                updated.usageCount + increment
            )
            updated.lastUsedAt = date
            return updated
        }
    }

    public static func ranksBefore(
        _ lhs: ReplacementRule,
        _ rhs: ReplacementRule
    ) -> Bool {
        if lhs.isStarred != rhs.isStarred {
            return lhs.isStarred && !rhs.isStarred
        }
        if lhs.usageCount != rhs.usageCount {
            return lhs.usageCount > rhs.usageCount
        }
        if lhs.source.count != rhs.source.count {
            return lhs.source.count > rhs.source.count
        }
        let comparison = lhs.source.localizedStandardCompare(rhs.source)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public enum VocabularyProcessor {
    public static func apply(
        to text: String,
        rules: [ReplacementRule],
        locale: Locale = .current
    ) -> String {
        applyWithUsage(to: text, rules: rules, locale: locale).text
    }

    public static func applyWithUsage(
        to text: String,
        rules: [ReplacementRule],
        locale: Locale = .current
    ) -> VocabularyApplicationResult {
        let ordered = VocabularyRanking.normalized(rules).sorted {
            if $0.source.count != $1.source.count {
                return $0.source.count > $1.source.count
            }
            return VocabularyRanking.ranksBefore($0, $1)
        }
        guard !ordered.isEmpty else {
            return VocabularyApplicationResult(
                text: text,
                matchedRuleIDs: []
            )
        }

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
            return VocabularyApplicationResult(
                text: text,
                matchedRuleIDs: []
            )
        }

        let original = text as NSString
        let matches = expression.matches(
            in: text,
            range: NSRange(location: 0, length: original.length)
        )
        let output = NSMutableString(string: text)
        var matchedRuleIDs: [UUID] = []
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
            matchedRuleIDs.append(rule.id)
            output.replaceCharacters(
                in: match.range,
                with: preserveCase(
                    from: matched,
                    replacement: rule.replacement,
                    locale: locale
                )
            )
        }
        return VocabularyApplicationResult(
            text: output as String,
            matchedRuleIDs: Array(matchedRuleIDs.reversed())
        )
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
        return VocabularyRanking.normalized(rules)
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
        try VocabularyExporter.json(VocabularyRanking.normalized(rules))
            .write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
