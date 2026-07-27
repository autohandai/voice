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

    private let store = HistoryStore()

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
        }
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
                List(model.filteredEntries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(entry.text)
                                .lineLimit(3)
                                .textSelection(.enabled)
                            Text(
                                "\(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.outcome.label)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Copy") {
                            model.copy(entry)
                        }
                        Button("Delete", role: .destructive) {
                            model.delete(entry)
                        }
                    }
                    .padding(.vertical, 4)
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
                maximumPicker
            }
            VStack(alignment: .leading) {
                retentionPicker
                maximumPicker
            }
        }
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
