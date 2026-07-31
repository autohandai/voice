import AppKit
import AutohandVoiceCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class HistoryModel {
    let session: VoiceSession
    var entries: [HistoryEntry] = []
    var query = ""
    var errorMessage: String?
    var copiedEntryID: UUID?

    private let store = HistoryStore()
    private let suggestionStore = VocabularySuggestionStore()

    init(session: VoiceSession) {
        self.session = session
        session.onHistoryChange = { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    var filteredEntries: [HistoryEntry] {
        entries.filter { $0.matches(query) }
    }

    func refresh() {
        do {
            entries = try store.load(
                retentionDays: session.preferences.historyRetentionDays,
                maximumItems: session.preferences.historyMaximumItems
            )
            errorMessage = session.historyError
        } catch {
            errorMessage = "Could not load history: \(error.localizedDescription)"
        }
    }

    func copy(_ entry: HistoryEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !pasteboard.setString(entry.text, forType: .string) {
            errorMessage = "Could not copy this transcript."
        } else {
            copiedEntryID = entry.id
        }
    }

    func retry(_ entry: HistoryEntry) {
        session.retryHistoryEntryHere(entry)
        refresh()
    }

    func delete(_ entry: HistoryEntry) {
        do {
            try store.delete(id: entry.id)
            refresh()
        } catch {
            errorMessage = "Could not delete this entry: \(error.localizedDescription)"
        }
    }

    func deleteAll() {
        session.deleteAllHistory()
        refresh()
    }

    func disableHistory(deleteExisting: Bool) {
        session.setHistoryEnabled(false)
        if deleteExisting {
            deleteAll()
        }
    }

    func suggestCorrection(
        for entry: HistoryEntry,
        correctedText: String
    ) {
        do {
            try suggestionStore.observeCorrection(
                source: entry.text,
                replacement: correctedText,
                enabled:
                    session.preferences.vocabularySuggestionsEnabled
            )
            errorMessage =
                "Correction added for local review. It is not active yet."
        } catch {
            errorMessage =
                "Could not save the suggestion: \(error.localizedDescription)"
        }
    }

    func reportExport(_ result: Result<URL, Error>) {
        if case let .failure(error) = result {
            errorMessage = "Could not export history: \(error.localizedDescription)"
        }
    }
}

private struct HistoryExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(entries: [HistoryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        data = (try? encoder.encode(entries)) ?? Data("[]".utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct HistoryView: View {
    @Bindable var model: HistoryModel
    @State private var confirmsDisable = false
    @State private var confirmsDeleteAll = false
    @State private var exportsHistory = false
    @State private var exportDocument: HistoryExportDocument?
    @State private var selectedEntryID: UUID?
    @State private var correctionEntry: HistoryEntry?
    @State private var correctedText = ""
    @State private var revisionEntry: HistoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if model.session.preferences.historyEnabled {
                historyContent
            } else {
                ContentUnavailableView(
                    "History Is Off",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Enable local text history to retain future final transcripts. Audio is never stored."
                    )
                )
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("History error: \(error)")
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 380)
        .searchable(
            text: $model.query,
            placement: .toolbar,
            prompt: "Search transcripts"
        )
        .confirmationDialog(
            "Turn off local history?",
            isPresented: $confirmsDisable
        ) {
            Button("Turn Off and Keep Existing") {
                model.disableHistory(deleteExisting: false)
            }
            Button("Turn Off and Delete All", role: .destructive) {
                model.disableHistory(deleteExisting: true)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Delete all dictation history?",
            isPresented: $confirmsDeleteAll
        ) {
            Button("Delete All", role: .destructive) {
                model.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileExporter(
            isPresented: $exportsHistory,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Autohand Voice History"
        ) { result in
            model.reportExport(result)
        }
        .sheet(item: $correctionEntry) { entry in
            VStack(alignment: .leading, spacing: 14) {
                Text("Suggest a Local Correction")
                    .font(.title2)
                Text(
                    "Edit the final text below. The pair is stored only as a pending suggestion and cannot change dictation until you confirm it in Vocabulary."
                )
                .foregroundStyle(.secondary)
                TextEditor(text: $correctedText)
                    .font(.body)
                    .frame(minWidth: 480, minHeight: 180)
                    .border(.quaternary)
                HStack {
                    Button("Cancel", role: .cancel) {
                        correctionEntry = nil
                    }
                    Spacer()
                    Button("Add for Review") {
                        model.suggestCorrection(
                            for: entry,
                            correctedText: correctedText
                        )
                        correctionEntry = nil
                    }
                    .disabled(
                        VocabularySuggestionPolicy.normalizedKey(
                            correctedText
                        ) == VocabularySuggestionPolicy.normalizedKey(
                            entry.text
                        )
                    )
                }
            }
            .padding(24)
        }
        .sheet(item: $revisionEntry) { entry in
            HistoryRevisionInspector(entry: entry)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                historyHeading
                Spacer()
                historyToggle
            }
            VStack(alignment: .leading, spacing: 12) {
                historyHeading
                historyToggle
            }
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    historyFilters
                    Spacer()
                    historyActions
                }
                VStack(alignment: .leading, spacing: 10) {
                    historyFilters
                    historyActions
                }
            }

            if model.filteredEntries.isEmpty {
                ContentUnavailableView.search(text: model.query)
            } else {
                List(
                    model.filteredEntries,
                    selection: $selectedEntryID
                ) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.text)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Text(metadata(for: entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if entry.outcome == .insertionFailed {
                            Button("Retry Here") {
                                model.retry(entry)
                            }
                        }
                        if model.session.preferences
                            .vocabularySuggestionsEnabled
                        {
                            Button("Suggest Correction") {
                                correctedText = entry.text
                                correctionEntry = entry
                            }
                        }
                        if entry.rawFinal != nil,
                           entry.revision != nil
                        {
                            Button("Revisions") {
                                revisionEntry = entry
                            }
                        }
                        Button(
                            model.copiedEntryID == entry.id
                                ? "Copied"
                                : "Copy"
                        ) {
                            model.copy(entry)
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(entry)
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(entry.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var historyHeading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dictation History")
                .font(.title)
            Text("Optional, text-only, and stored on this Mac.")
                .foregroundStyle(.secondary)
        }
    }

    private var historyToggle: some View {
        Toggle(
            "Save History",
            isOn: Binding(
                get: { model.session.preferences.historyEnabled },
                set: { enabled in
                    if enabled {
                        model.session.setHistoryEnabled(true)
                    } else {
                        confirmsDisable = true
                    }
                }
            )
        )
        .toggleStyle(.switch)
    }

    private var historyFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                retentionPicker
                customRetentionStepper
                maximumPicker
            }
            VStack(alignment: .leading) {
                retentionPicker
                customRetentionStepper
                maximumPicker
            }
        }
    }

    private var customRetentionStepper: some View {
        Stepper(
            "Custom: \(model.session.preferences.historyRetentionDays) days",
            value: Binding(
                get: {
                    model.session.preferences.historyRetentionDays
                },
                set: {
                    model.session.setHistoryRetentionDays($0)
                }
            ),
            in: 1 ... 365
        )
        .accessibilityLabel("Custom history retention in days")
        .accessibilityValue(
            "\(model.session.preferences.historyRetentionDays) days"
        )
    }

    private var retentionPicker: some View {
        Picker(
            "Retention",
            selection: Binding(
                get: {
                    model.session.preferences.historyRetentionDays
                },
                set: {
                    model.session.setHistoryRetentionDays($0)
                }
            )
        ) {
            Text("24 hours").tag(1)
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
        }
    }

    private var maximumPicker: some View {
        Picker(
            "Maximum",
            selection: Binding(
                get: {
                    model.session.preferences.historyMaximumItems
                },
                set: {
                    model.session.setHistoryMaximumItems($0)
                }
            )
        ) {
            Text("100 entries").tag(100)
            Text("500 entries").tag(500)
            Text("1,000 entries").tag(1_000)
        }
    }

    private func metadata(for entry: HistoryEntry) -> String {
        var values = [
            entry.createdAt.formatted(
                date: .abbreviated,
                time: .shortened
            ),
            entry.outcome.label,
        ]
        if let languageCode = entry.languageCode {
            values.append(languageCode.uppercased())
        }
        if let duration = entry.duration {
            values.append(
                Duration.seconds(duration).formatted(
                    .units(
                        allowed: [.minutes, .seconds],
                        width: .abbreviated
                    )
                )
            )
        }
        if let failureCategory = entry.failureCategory {
            values.append(failureCategory.code)
        }
        return values.joined(separator: " · ")
    }

    private var historyActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                exportButton
                deleteAllButton
            }
            VStack(alignment: .leading) {
                exportButton
                deleteAllButton
            }
        }
    }

    private var exportButton: some View {
        Button("Export…") {
            exportDocument = HistoryExportDocument(
                entries: model.entries
            )
            exportsHistory = true
        }
        .disabled(model.entries.isEmpty)
    }

    private var deleteAllButton: some View {
        Button("Delete All", role: .destructive) {
            confirmsDeleteAll = true
        }
        .disabled(model.entries.isEmpty)
    }
}

private struct HistoryRevisionInspector: View {
    let entry: HistoryEntry
    @State private var showsRaw = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcript Revisions")
                .font(.title2)
            Text(
                showsRaw
                    ? "Raw final · immutable recognition root"
                    : revisionLabel
            )
            .foregroundStyle(.secondary)

            ScrollView {
                Text(displayedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(minWidth: 500, minHeight: 220)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Button("Undo to Raw Final") {
                    showsRaw = true
                    copied = false
                }
                .disabled(showsRaw || entry.rawFinal == nil)
                Button("Redo Cleanup") {
                    showsRaw = false
                    copied = false
                }
                .disabled(!showsRaw || entry.revision == nil)
                Spacer()
                Button(copied ? "Copied" : "Copy This Revision") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(
                        displayedText,
                        forType: .string
                    )
                }
            }
        }
        .padding(24)
    }

    private var displayedText: String {
        if showsRaw {
            return entry.rawFinal?.text ?? entry.text
        }
        return entry.revision?.text ?? entry.text
    }

    private var revisionLabel: String {
        guard let revision = entry.revision else {
            return "Stored final"
        }
        return "\(revision.kind.rawValue) · \(revision.policyVersion) · \(revision.changes.count) change\(revision.changes.count == 1 ? "" : "s")"
    }
}
