import AppKit
import AVFoundation
import AutohandVoiceCore
import Observation
import SwiftUI
import UniformTypeIdentifiers

private let markdownType =
    UTType(filenameExtension: "md", conformingTo: .plainText) ?? .plainText

@MainActor
@Observable
final class FileTranscriptionModel {
    enum State: Equatable {
        case empty
        case selected
        case transcribing
        case cancelling
        case complete

        var label: String {
            switch self {
            case .empty: "Choose an audio file to begin."
            case .selected: "Ready for local transcription."
            case .transcribing: "Transcribing locally…"
            case .cancelling: "Cancelling and releasing file access…"
            case .complete: "Final transcript is ready."
            }
        }
    }

    let session: VoiceSession
    var state: State = .empty
    var selectedURL: URL?
    var transcript = ""
    var progress: Double?
    var errorMessage: String?

    private var task: Task<Void, Never>?
    private var operationID: UUID?

    init(session: VoiceSession) {
        self.session = session
    }

    var selectedName: String {
        selectedURL?.lastPathComponent ?? "No file selected"
    }

    var canTranscribe: Bool {
        state == .selected || state == .complete
    }

    func select(_ url: URL) {
        cancel()
        do {
            try AudioImportValidator.validate(url)
            selectedURL = url
            transcript = ""
            progress = nil
            errorMessage = nil
            state = .selected
        } catch {
            selectedURL = nil
            transcript = ""
            state = .empty
            errorMessage = error.localizedDescription
        }
    }

    func transcribe() {
        guard let selectedURL, canTranscribe else { return }
        guard session.beginFileTranscription() else {
            errorMessage =
                "Finish the current recording or microphone test first."
            return
        }

        let id = UUID()
        operationID = id
        transcript = ""
        progress = nil
        errorMessage = nil
        state = .transcribing
        let modelVersion = session.preferences.modelVersion
        let languageCode = session.preferences.dictationLanguageCode

        task = Task { [self] in
            let lease = SecurityScopedResourceLease(url: selectedURL)
            defer {
                lease.close()
                session.endFileTranscription()
            }

            do {
                try Task.checkCancellation()
                try AudioImportValidator.validate(selectedURL)
                let audioFile = try AVAudioFile(forReading: selectedURL)
                guard
                    audioFile.length > 0,
                    audioFile.processingFormat.sampleRate > 0
                else {
                    throw VoiceError.recordingTooShort
                }
                try Task.checkCancellation()

                let recognizer = LocalSpeechRecognizer(
                    modelVersion: modelVersion
                )
                let result = try await recognizer.transcribe(
                    file: selectedURL,
                    languageCode: languageCode
                ) { [weak self] value in
                    Task { @MainActor [weak self] in
                        guard self?.operationID == id else { return }
                        self?.progress = min(max(value, 0), 1)
                    }
                }
                try Task.checkCancellation()
                let text = try result.finalText()
                guard operationID == id else { return }
                transcript = text
                progress = 1
                state = .complete
            } catch is CancellationError {
                guard operationID == id else { return }
                progress = nil
                state = .selected
            } catch {
                guard operationID == id else { return }
                progress = nil
                state = .selected
                errorMessage =
                    "Could not transcribe this file: \(error.localizedDescription)"
            }
            if operationID == id {
                operationID = nil
                task = nil
            }
        }
    }

    func cancel() {
        guard let task else { return }
        state = .cancelling
        task.cancel()
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        if !NSPasteboard.general.setString(
            transcript,
            forType: .string
        ) {
            errorMessage = "Could not copy the transcript."
        }
    }

    func reportImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                errorMessage = "No audio file was selected."
                return
            }
            select(url)
        case let .failure(error):
            errorMessage = "Could not open the file: \(error.localizedDescription)"
        }
    }

    func reportExport(_ result: Result<URL, Error>) {
        if case let .failure(error) = result {
            errorMessage =
                "Could not export the transcript: \(error.localizedDescription)"
        }
    }
}

private struct TranscriptExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.plainText, markdownType]
    let data: Data

    init(text: String, markdown: Bool) {
        let output = markdown ? "# Transcript\n\n\(text)\n" : "\(text)\n"
        data = Data(output.utf8)
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct FileTranscriptionView: View {
    @Bindable var model: FileTranscriptionModel
    @State private var importsFile = false
    @State private var exportsFile = false
    @State private var exportDocument: TranscriptExportDocument?
    @State private var exportType = UTType.plainText

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Divider()
            fileControls
            status

            TextEditor(text: $model.transcript)
                .font(.body)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if model.transcript.isEmpty {
                        ContentUnavailableView(
                            "No Final Transcript",
                            systemImage: "waveform.badge.magnifyingglass",
                            description: Text(
                                "Choose a supported audio file and transcribe it entirely on this Mac."
                            )
                        )
                        .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Editable final transcript")

            resultActions

            Text(
                "Audio and transcript text stay on this Mac. No upload, cloud cleanup, translation, meeting capture, or speaker diarization is performed."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("File transcription error: \(error)")
            }
        }
        .padding(24)
        .frame(minWidth: 600, minHeight: 440)
        .fileImporter(
            isPresented: $importsFile,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            model.reportImport(result)
        }
        .fileExporter(
            isPresented: $exportsFile,
            document: exportDocument,
            contentType: exportType,
            defaultFilename: "Autohand Voice Transcript"
        ) { result in
            model.reportExport(result)
        }
        .onDisappear {
            model.cancel()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Transcribe Audio File")
                .font(.title)
            Text("Final, editable text from the selected local model.")
                .foregroundStyle(.secondary)
        }
    }

    private var fileControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                chooseFileButton
                selectedFileName
                Spacer()
                transcriptionButton
            }
            VStack(alignment: .leading, spacing: 10) {
                selectedFileName
                HStack {
                    chooseFileButton
                    Spacer()
                    transcriptionButton
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        if model.state == .transcribing {
            if let progress = model.progress, progress > 0 {
                ProgressView(value: progress, total: 1) {
                    Text(model.state.label)
                }
                .accessibilityValue("\(Int(progress * 100)) percent")
            } else {
                ProgressView {
                    Text(model.state.label)
                }
            }
        } else {
            Label(
                model.state.label,
                systemImage: model.state == .complete
                    ? "checkmark.circle.fill"
                    : "waveform"
            )
            .foregroundStyle(
                model.state == .complete ? .green : .secondary
            )
        }
    }

    private var resultActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                copyButton
                Spacer()
                exportButtons
            }
            VStack(alignment: .leading, spacing: 10) {
                copyButton
                exportButtons
            }
        }
    }

    private var chooseFileButton: some View {
        Button("Choose Audio…") {
            importsFile = true
        }
        .disabled(
            model.state == .transcribing
                || model.state == .cancelling
        )
    }

    private var selectedFileName: some View {
        Text(verbatim: model.selectedName)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(
                model.selectedURL == nil ? .secondary : .primary
            )
            .accessibilityLabel("Selected audio file")
            .accessibilityValue(model.selectedName)
    }

    @ViewBuilder
    private var transcriptionButton: some View {
        if model.state == .transcribing {
            Button("Cancel", role: .cancel) {
                model.cancel()
            }
        } else {
            Button("Transcribe") {
                model.transcribe()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canTranscribe)
        }
    }

    private var copyButton: some View {
        Button("Copy") {
            model.copyTranscript()
        }
        .disabled(model.transcript.isEmpty)
    }

    private var exportButtons: some View {
        HStack {
            Button("Export Text…") {
                prepareExport(markdown: false)
            }
            Button("Export Markdown…") {
                prepareExport(markdown: true)
            }
        }
        .disabled(model.transcript.isEmpty)
    }

    private func prepareExport(markdown: Bool) {
        exportType = markdown ? markdownType : .plainText
        exportDocument = TranscriptExportDocument(
            text: model.transcript,
            markdown: markdown
        )
        exportsFile = true
    }
}
