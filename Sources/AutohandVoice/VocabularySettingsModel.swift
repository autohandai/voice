import AutohandVoiceCore
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class VocabularySettingsModel {
    private(set) var rules: [ReplacementRule] = []
    var source = ""
    var replacement = ""
    var testInput = ""
    private(set) var message: String?
    @ObservationIgnored private let store: VocabularyStore

    init(store: VocabularyStore = VocabularyStore()) {
        self.store = store
        reload()
    }

    var testOutput: String {
        VocabularyProcessor.apply(to: testInput, rules: rules)
    }

    var canAdd: Bool {
        let candidate = ReplacementRule(
            source: source,
            replacement: replacement
        )
        return rules.count < VocabularyLimits.maximumRules
            && candidate.isValid
            && !containsSource(candidate.source)
    }

    func exportDocument() -> VocabularyDocument {
        VocabularyDocument(rules: rules)
    }

    func add() {
        guard rules.count < VocabularyLimits.maximumRules else {
            message = VocabularyError.tooManyRules.localizedDescription
            return
        }
        let rule = ReplacementRule(source: source, replacement: replacement)
        guard rule.isValid else {
            message = "Enter both the spoken phrase and its replacement."
            return
        }
        guard !containsSource(rule.source) else {
            message = "A replacement for “\(rule.source)” already exists."
            return
        }
        rules.append(rule)
        rules.sort(by: Self.sortRules)
        source = ""
        replacement = ""
        save(message: "Replacement added.")
    }

    func delete(at offsets: IndexSet) {
        rules.remove(atOffsets: offsets)
        save(message: "Replacement deleted.")
    }

    func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? 0) <= VocabularyLimits.maximumFileBytes
            else {
                throw VocabularyError.fileTooLarge
            }
            let data = try Data(contentsOf: url)
            let imported: [ReplacementRule]
            var rowErrors: [VocabularyImportError] = []
            if url.pathExtension.lowercased() == "csv" {
                guard let text = String(data: data, encoding: .utf8) else {
                    throw VocabularySettingsError.invalidUTF8
                }
                let result = VocabularyImporter.csv(text)
                imported = result.rules
                rowErrors = result.errors
            } else {
                imported = try VocabularyImporter.json(data)
            }

            var additions = 0
            var duplicates = 0
            var merged = rules
            for rule in imported {
                if Self.containsSource(rule.source, in: merged) {
                    duplicates += 1
                } else {
                    guard merged.count < VocabularyLimits.maximumRules else {
                        throw VocabularyError.tooManyRules
                    }
                    merged.append(rule)
                    additions += 1
                }
            }
            merged.sort(by: Self.sortRules)
            try store.save(merged)
            rules = merged

            var parts = ["Imported \(additions) replacement\(additions == 1 ? "" : "s")."]
            if duplicates > 0 {
                parts.append("\(duplicates) duplicate\(duplicates == 1 ? "" : "s") skipped.")
            }
            if !rowErrors.isEmpty {
                let rows = rowErrors.map { String($0.row) }.joined(separator: ", ")
                parts.append("Invalid CSV rows: \(rows).")
            }
            message = parts.joined(separator: " ")
        } catch {
            message = "Import failed: \(error.localizedDescription)"
        }
    }

    func reportExport(_ result: Result<URL, Error>) {
        switch result {
        case .success:
            message = "Vocabulary exported."
        case let .failure(error):
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    func reportImportError(_ error: Error) {
        message = "Import failed: \(error.localizedDescription)"
    }

    private func reload() {
        do {
            rules = try store.load().sorted(by: Self.sortRules)
            message = nil
        } catch {
            rules = []
            message = "Vocabulary could not be loaded: \(error.localizedDescription)"
        }
    }

    private func save(message successMessage: String) {
        do {
            try store.save(rules)
            message = successMessage
        } catch {
            message = "Vocabulary could not be saved: \(error.localizedDescription)"
            reload()
        }
    }

    private func containsSource(_ value: String) -> Bool {
        Self.containsSource(value, in: rules)
    }

    private static func containsSource(
        _ value: String,
        in rules: [ReplacementRule]
    ) -> Bool {
        rules.contains {
            $0.source.compare(
                value,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    private static func sortRules(
        _ lhs: ReplacementRule,
        _ rhs: ReplacementRule
    ) -> Bool {
        lhs.source.localizedStandardCompare(rhs.source) == .orderedAscending
    }
}

private enum VocabularySettingsError: LocalizedError {
    case invalidUTF8

    var errorDescription: String? {
        "The CSV file is not valid UTF-8."
    }
}

struct VocabularyDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let rules: [ReplacementRule]

    init(rules: [ReplacementRule]) {
        self.rules = rules
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        if configuration.contentType == .commaSeparatedText {
            guard let text = String(data: data, encoding: .utf8) else {
                throw VocabularySettingsError.invalidUTF8
            }
            rules = VocabularyImporter.csv(text).rules
        } else {
            rules = try VocabularyImporter.json(data)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data: Data
        if configuration.contentType == .commaSeparatedText {
            data = Data(VocabularyExporter.csv(rules).utf8)
        } else {
            data = try VocabularyExporter.json(rules)
        }
        return FileWrapper(regularFileWithContents: data)
    }
}
