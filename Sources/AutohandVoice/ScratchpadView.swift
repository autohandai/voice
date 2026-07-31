import AppKit
import AutohandVoiceCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ScratchpadModel {
    private(set) var notes: [ScratchpadNote] = []
    private(set) var versions: [ScratchpadVersion] = []
    private(set) var openNoteIDs: [UUID] = []
    private(set) var editorAttributed = NSAttributedString(string: "")
    var selectedNoteID: UUID?
    var search = ""
    private(set) var message: String?
    private(set) var isSaving = false

    @ObservationIgnored private let workspace: LocalWorkspace
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var isLoadingEditor = false

    init(workspace: LocalWorkspace) {
        self.workspace = workspace
        Task { await refresh() }
    }

    var selectedNote: ScratchpadNote? {
        notes.first { $0.id == selectedNoteID }
    }

    func refresh() async {
        do {
            let page = try await workspace.query(
                .notes(search: search, limit: 100, offset: 0)
            )
            notes = page.notes
            if selectedNoteID == nil {
                selectedNoteID = notes.first?.id
            }
            if let selectedNoteID {
                open(noteID: selectedNoteID)
                await loadEditor()
            }
            message = nil
        } catch {
            message = "Scratchpad could not be loaded: \(error.localizedDescription)"
        }
    }

    func searchChanged() {
        Task { await refresh() }
    }

    func createNote() {
        Task {
            do {
                let note = ScratchpadNote(
                    title: "Untitled Note",
                    plainText: ""
                )
                _ = try await workspace.apply(.createNote(note))
                notes.insert(note, at: 0)
                select(note.id)
                message = nil
            } catch {
                message =
                    "The note could not be created: \(error.localizedDescription)"
            }
        }
    }

    func select(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        selectedNoteID = id
        open(noteID: id)
        Task { await loadEditor() }
    }

    func closeTab(_ id: UUID) {
        openNoteIDs.removeAll { $0 == id }
        guard selectedNoteID == id else { return }
        selectedNoteID = openNoteIDs.last ?? notes.first?.id
        if let selectedNoteID {
            open(noteID: selectedNoteID)
            Task { await loadEditor() }
        } else {
            editorAttributed = NSAttributedString(string: "")
            versions = []
        }
    }

    func renameSelected(_ title: String) {
        guard
            let id = selectedNoteID,
            let index = notes.firstIndex(where: { $0.id == id })
        else { return }
        notes[index].title = String(
            title.trimmingCharacters(in: .newlines).prefix(200)
        )
        notes[index].updatedAt = Date()
        scheduleSave(notes[index])
    }

    func editorChanged(_ attributed: NSAttributedString) {
        guard
            !isLoadingEditor,
            let id = selectedNoteID,
            let index = notes.firstIndex(where: { $0.id == id })
        else { return }
        let textOnly = NSMutableAttributedString(
            attributedString: attributed
        )
        textOnly.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: textOnly.length),
            options: [.reverse]
        ) { value, range, _ in
            if value != nil {
                textOnly.deleteCharacters(in: range)
            }
        }
        let range = NSRange(location: 0, length: textOnly.length)
        let rtf = try? textOnly.data(
            from: range,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        notes[index].plainText = textOnly.string
        notes[index].richTextRTF = rtf
        notes[index].updatedAt = Date()
        editorAttributed = attributed.copy() as? NSAttributedString
            ?? attributed
        scheduleSave(notes[index])
    }

    func addImage(_ url: URL) {
        Task {
            let accessed = url.startAccessingSecurityScopedResource()
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(
                    contentsOf: url,
                    options: [.mappedIfSafe]
                )
                guard let image = NSImage(data: data) else {
                    throw LocalWorkspaceError.assetRejected
                }
                let mediaType = UTType(filenameExtension: url.pathExtension)?
                    .preferredMIMEType ?? "image/png"
                let receipt = try await workspace.apply(
                    .storeAsset(data: data, mediaType: mediaType)
                )
                guard
                    let id = selectedNoteID,
                    let index = notes.firstIndex(where: { $0.id == id })
                else { return }
                if !notes[index].assetHashes.contains(receipt.entityID) {
                    notes[index].assetHashes.append(receipt.entityID)
                }
                notes[index].updatedAt = Date()
                append(image: image)
                _ = try await workspace.apply(.updateNote(notes[index]))
                versions = try await workspace.query(
                    .versions(noteID: id, limit: 100)
                ).versions
                message = "Image added locally."
            } catch {
                message =
                    "The image could not be added: \(error.localizedDescription)"
            }
        }
    }

    func restore(_ version: ScratchpadVersion) {
        Task {
            do {
                _ = try await workspace.apply(
                    .restoreVersion(
                        noteID: version.noteID,
                        versionID: version.id
                    )
                )
                await refresh()
                message = "Earlier note version restored."
            } catch {
                message =
                    "The version could not be restored: \(error.localizedDescription)"
            }
        }
    }

    func deleteSelected() {
        guard let id = selectedNoteID else { return }
        Task {
            do {
                _ = try await workspace.apply(.deleteNote(id))
                closeTab(id)
                notes.removeAll { $0.id == id }
                selectedNoteID = notes.first?.id
                if let selectedNoteID {
                    select(selectedNoteID)
                }
                _ = try await workspace.enforceRetention()
                message = "Note deleted."
            } catch {
                message =
                    "The note could not be deleted: \(error.localizedDescription)"
            }
        }
    }

    func appendDictation(_ text: String) async throws {
        let note: ScratchpadNote
        if let selectedNote {
            note = selectedNote
        } else {
            let created = ScratchpadNote(title: "Quick Dictation")
            _ = try await workspace.apply(.createNote(created))
            notes.insert(created, at: 0)
            selectedNoteID = created.id
            open(noteID: created.id)
            note = created
        }
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else {
            throw LocalWorkspaceError.notFound
        }
        let separator = notes[index].plainText.isEmpty ? "" : "\n\n"
        notes[index].plainText += separator + text
        notes[index].updatedAt = Date()
        let attributed = NSMutableAttributedString(
            attributedString: editorAttributed
        )
        attributed.append(
            NSAttributedString(string: separator + text)
        )
        editorAttributed = attributed
        _ = try await workspace.apply(.updateNote(notes[index]))
        message = "Quick dictation saved in Scratchpad."
    }

    func prepareForLocalDataReset() async {
        saveTask?.cancel()
        _ = await saveTask?.result
        saveTask = nil
        await workspace.close()
        notes = []
        versions = []
        openNoteIDs = []
        selectedNoteID = nil
        editorAttributed = NSAttributedString(string: "")
        message = "Scratchpad data was removed from this Mac."
    }

    private func open(noteID: UUID) {
        if !openNoteIDs.contains(noteID) {
            openNoteIDs.append(noteID)
        }
    }

    private func scheduleSave(_ note: ScratchpadNote) {
        saveTask?.cancel()
        isSaving = true
        saveTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self else { return }
                _ = try await self.workspace.apply(.updateNote(note))
                self.versions = try await self.workspace.query(
                    .versions(noteID: note.id, limit: 100)
                ).versions
                self.isSaving = false
                self.message = nil
            } catch is CancellationError {
                return
            } catch {
                self?.isSaving = false
                self?.message =
                    "The note could not be saved: \(error.localizedDescription)"
            }
        }
    }

    private func loadEditor() async {
        guard let note = selectedNote else { return }
        saveTask?.cancel()
        isLoadingEditor = true
        defer { isLoadingEditor = false }
        let attributed: NSMutableAttributedString
        if let rtf = note.richTextRTF,
           let decoded = try? NSAttributedString(
               data: rtf,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            attributed = NSMutableAttributedString(
                attributedString: decoded
            )
        } else {
            attributed = NSMutableAttributedString(string: note.plainText)
        }
        for hash in note.assetHashes {
            guard
                let data = try? await workspace.assetData(hash),
                let image = NSImage(data: data)
            else { continue }
            attributed.append(NSAttributedString(string: "\n"))
            let attachment = NSTextAttachment()
            attachment.image = image
            attributed.append(NSAttributedString(attachment: attachment))
        }
        editorAttributed = attributed
        versions = (try? await workspace.query(
            .versions(noteID: note.id, limit: 100)
        ).versions) ?? []
    }

    private func append(image: NSImage) {
        let attributed = NSMutableAttributedString(
            attributedString: editorAttributed
        )
        if attributed.length > 0 {
            attributed.append(NSAttributedString(string: "\n"))
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        attributed.append(NSAttributedString(attachment: attachment))
        editorAttributed = attributed
    }
}

struct ScratchpadView: View {
    @Bindable var model: ScratchpadModel
    let startQuickDictation: () -> Void
    @State private var importsImage = false

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(model.notes, selection: $model.selectedNoteID) { note in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title)
                            .lineLimit(1)
                        Text(note.updatedAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(note.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.select(note.id)
                    }
                }
                HStack {
                    Button {
                        model.createNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    Spacer()
                }
                .padding(10)
            }
            .searchable(text: $model.search, prompt: "Search notes")
            .onSubmit(of: .search) {
                model.searchChanged()
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                tabs
                Divider()
                if let note = model.selectedNote {
                    editor(note)
                } else {
                    ContentUnavailableView(
                        "No Note Selected",
                        systemImage: "note.text",
                        description: Text(
                            "Create a note or start Quick Dictation."
                        )
                    )
                }
                if let message = model.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(minWidth: 760, minHeight: 500)
        .fileImporter(
            isPresented: $importsImage,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let url = urls.first {
                model.addImage(url)
            }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(model.openNoteIDs, id: \.self) { id in
                    if let note = model.notes.first(where: { $0.id == id }) {
                        HStack(spacing: 5) {
                            Button(note.title) {
                                model.select(id)
                            }
                            .buttonStyle(.plain)
                            Button {
                                model.closeTab(id)
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close \(note.title)")
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            model.selectedNoteID == id
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear,
                            in: Capsule()
                        )
                    }
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
    }

    private func editor(_ note: ScratchpadNote) -> some View {
        VStack(spacing: 0) {
            HStack {
                TextField(
                    "Note title",
                    text: Binding(
                        get: { note.title },
                        set: { model.renameSelected($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))

                if model.isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving note")
                }
                Button {
                    applyFontTrait(.boldFontMask)
                } label: {
                    Image(systemName: "bold")
                }
                .help("Bold")
                Button {
                    applyFontTrait(.italicFontMask)
                } label: {
                    Image(systemName: "italic")
                }
                .help("Italic")
                Button {
                    importsImage = true
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .help("Add Image")
                Button {
                    startQuickDictation()
                } label: {
                    Label("Quick Dictation", systemImage: "mic")
                }
                Button(role: .destructive) {
                    model.deleteSelected()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Note")
            }
            .padding(14)

            RichTextEditor(
                attributed: model.editorAttributed,
                onChange: model.editorChanged
            )

            if !model.versions.isEmpty {
                DisclosureGroup("Version History") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(model.versions) { version in
                                Button(
                                    version.createdAt.formatted(
                                        date: .abbreviated,
                                        time: .shortened
                                    )
                                ) {
                                    model.restore(version)
                                }
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    private func applyFontTrait(_ trait: NSFontTraitMask) {
        guard let textView = NSApp.keyWindow?.firstResponder as? NSTextView
        else { return }
        let manager = NSFontManager.shared
        let range = textView.selectedRange()
        if range.length == 0 {
            let current = textView.typingAttributes[.font] as? NSFont
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textView.typingAttributes[.font] = manager.convert(
                current,
                toHaveTrait: trait
            )
            return
        }
        textView.textStorage?.enumerateAttribute(
            .font,
            in: range
        ) { value, subrange, _ in
            let current = value as? NSFont
                ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            textView.textStorage?.addAttribute(
                .font,
                value: manager.convert(current, toHaveTrait: trait),
                range: subrange
            )
        }
        textView.didChangeText()
    }
}

private struct RichTextEditor: NSViewRepresentable {
    let attributed: NSAttributedString
    let onChange: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let textView = NSTextView()
        textView.isRichText = true
        textView.allowsImageEditing = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.rendered = attributed
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(
        _ scroll: NSScrollView,
        context: Context
    ) {
        guard
            let textView = scroll.documentView as? NSTextView,
            !context.coordinator.rendered.isEqual(to: attributed)
        else { return }
        context.coordinator.isApplying = true
        let selection = textView.selectedRange()
        textView.textStorage?.setAttributedString(attributed)
        textView.setSelectedRange(
            NSRange(
                location: min(selection.location, attributed.length),
                length: 0
            )
        )
        context.coordinator.rendered = attributed
        context.coordinator.isApplying = false
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var rendered = NSAttributedString(string: "")
        var isApplying = false
        let onChange: (NSAttributedString) -> Void

        init(onChange: @escaping (NSAttributedString) -> Void) {
            self.onChange = onChange
        }

        func textDidChange(_ notification: Notification) {
            guard
                !isApplying,
                let textView = notification.object as? NSTextView,
                let storage = textView.textStorage
            else { return }
            rendered = NSAttributedString(attributedString: storage)
            onChange(rendered)
        }
    }
}
