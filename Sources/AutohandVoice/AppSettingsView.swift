import AppKit
import AutohandVoiceCore
import Carbon
import Observation
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPane: String, CaseIterable, Identifiable {
    case gettingStarted
    case general
    case formatting
    case vocabulary
    case permissions
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .general: "General"
        case .formatting: "Formatting"
        case .vocabulary: "Vocabulary"
        case .permissions: "Permissions"
        case .privacy: "Privacy & Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "checklist"
        case .general: "gearshape"
        case .formatting: "textformat"
        case .vocabulary: "text.book.closed"
        case .permissions: "hand.raised"
        case .privacy: "lock.shield"
        }
    }
}

struct AppSettingsView: View {
    @Bindable var model: AppSettingsModel
    @State private var selection: SettingsPane

    init(model: AppSettingsModel) {
        self.model = model
        _selection = State(
            initialValue: model.session.preferences.hasCompletedOnboarding
                ? .general
                : .gettingStarted
        )
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol)
                    .tag(pane)
            }
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 210,
                max: 260
            )
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 680, minHeight: 480)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .gettingStarted:
            GettingStartedView(model: model) {
                model.completeOnboarding()
                selection = .general
            }
        case .general:
            GeneralSettingsView(model: model)
        case .formatting:
            FormattingSettingsView(model: model)
        case .vocabulary:
            VocabularySettingsView(model: model.vocabulary)
        case .permissions:
            PermissionCenterView(model: model)
        case .privacy:
            PrivacyDiagnosticsView(model: model)
        }
    }
}

private enum FormattingPreviewPosition: String, CaseIterable, Identifiable {
    case start = "Document Start"
    case middle = "Between Words"
    case end = "Document End"

    var id: Self { self }

    var context: TextInsertionContext {
        switch self {
        case .start:
            .init(isAtDocumentStart: true)
        case .middle:
            .init(precedingCharacter: "x", followingCharacter: "y")
        case .end:
            .init(precedingCharacter: ".", isAtDocumentEnd: true)
        }
    }
}

private struct FormattingSettingsView: View {
    @Bindable var model: AppSettingsModel
    @State private var previewText = "hello from autohand voice"
    @State private var previewPosition = FormattingPreviewPosition.start

    var body: some View {
        SettingsPage(
            "Formatting",
            subtitle: "Apply deterministic local spacing and punctuation at the cursor."
        ) {
            Form {
                Section("Smart Formatting") {
                    Toggle(
                        "Enable Smart Formatting",
                        isOn: Binding(
                            get: {
                                model.session.preferences.smartFormattingEnabled
                            },
                            set: {
                                model.session.setSmartFormattingEnabled($0)
                            }
                        )
                    )
                    Toggle(
                        "Add Terminal Punctuation",
                        isOn: Binding(
                            get: {
                                model.session.preferences
                                    .automaticTerminalPunctuation
                            },
                            set: {
                                model.session
                                    .setAutomaticTerminalPunctuation($0)
                            }
                        )
                    )
                    .disabled(!model.session.preferences.smartFormattingEnabled)
                }

                Section("Preview") {
                    TextField("Recognized text", text: $previewText)
                    Picker("Cursor Position", selection: $previewPosition) {
                        ForEach(FormattingPreviewPosition.allCases) {
                            Text($0.rawValue).tag($0)
                        }
                    }
                    LabeledContent("Inserted Text") {
                        Text(preview)
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Text(
                "When cursor context is available, Autohand Voice reads at most one adjacent character on each side. Unknown context is left unchanged. Turn this off for literal output."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var preview: String {
        SmartTextFormatter.format(
            previewText,
            context: previewPosition.context,
            enabled: model.session.preferences.smartFormattingEnabled,
            addsTerminalPunctuation:
                model.session.preferences.automaticTerminalPunctuation
        )
    }
}

private struct VocabularySettingsView: View {
    @Bindable var model: VocabularySettingsModel
    @State private var importsFile = false
    @State private var exportsFile = false
    @State private var exportType: UTType = .json

    var body: some View {
        SettingsPage(
            "Vocabulary",
            subtitle: "Replace recognized words and phrases locally before insertion."
        ) {
            Form {
                Section("Add Replacement") {
                    TextField("Spoken phrase", text: $model.source)
                    TextField("Insert instead", text: $model.replacement)
                    HStack {
                        Spacer()
                        Button("Add Replacement") {
                            model.add()
                        }
                        .disabled(!model.canAdd)
                    }
                }

                Section("Replacements") {
                    if model.rules.isEmpty {
                        ContentUnavailableView(
                            "No Replacements",
                            systemImage: "text.book.closed",
                            description: Text(
                                "Add a phrase above or import a JSON or CSV vocabulary."
                            )
                        )
                    } else {
                        List {
                            ForEach(model.rules) { rule in
                                LabeledContent(rule.source) {
                                    Text(rule.replacement)
                                        .textSelection(.enabled)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    "\(rule.source), replaced with \(rule.replacement)"
                                )
                            }
                            .onDelete(perform: model.delete)
                        }
                        .frame(minHeight: 150)
                    }

                    HStack {
                        Button("Import…") {
                            importsFile = true
                        }
                        Button("Export JSON…") {
                            exportType = .json
                            exportsFile = true
                        }
                        .disabled(model.rules.isEmpty)
                        Button("Export CSV…") {
                            exportType = .commaSeparatedText
                            exportsFile = true
                        }
                        .disabled(model.rules.isEmpty)
                        Spacer()
                        Text("\(model.rules.count) replacement\(model.rules.count == 1 ? "" : "s")")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Test") {
                    TextField("Try a sentence", text: $model.testInput)
                    LabeledContent("Result") {
                        Text(
                            model.testOutput.isEmpty
                                ? "Enter text to preview"
                                : model.testOutput
                        )
                        .foregroundStyle(
                            model.testOutput.isEmpty ? .secondary : .primary
                        )
                        .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            Text(
                "Matching is case-insensitive, uses whole words, and applies the longest phrase first. Replacements never call a remote service."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ActionMessage(message: model.message)
        }
        .fileImporter(
            isPresented: $importsFile,
            allowedContentTypes: [.json, .commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    model.importFile(url)
                }
            case let .failure(error):
                model.reportImportError(error)
            }
        }
        .fileExporter(
            isPresented: $exportsFile,
            document: model.exportDocument(),
            contentType: exportType,
            defaultFilename: "autohand-voice-vocabulary"
        ) { result in
            model.reportExport(result)
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(
        _ title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title)
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }

                content
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(32)
        }
    }
}

private struct GettingStartedView: View {
    @Bindable var model: AppSettingsModel
    let onContinue: () -> Void

    var body: some View {
        SettingsPage(
            "Welcome to Autohand Voice",
            subtitle: "Private voice input, processed locally on your Mac."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                SetupStep(
                    number: 1,
                    title: "Allow microphone access",
                    detail: "Audio stays in memory and is transcribed locally.",
                    isComplete: model.systemCheck.microphonePermission == "authorized"
                ) {
                    Task { await model.requestMicrophonePermission() }
                }

                SetupStep(
                    number: 2,
                    title: "Allow Accessibility access",
                    detail: "Used only to insert the final transcript at your cursor.",
                    isComplete: model.systemCheck.accessibilityPermission
                ) {
                    model.requestAccessibilityPermission()
                }

                SetupStep(
                    number: 3,
                    title: "Prepare the local speech model",
                    detail: "The pinned CoreML model runs on the Apple Neural Engine.",
                    isComplete: model.session.modelState == .ready
                ) {
                    model.session.prepareLocalModel()
                }

                Divider()

                HStack {
                    Button("Check Again") {
                        model.refresh()
                    }

                    Spacer()

                    Button("Continue") {
                        onContinue()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!requiredSetupIsComplete)
                }

                ActionMessage(message: model.actionMessage)
            }
        }
    }

    private var requiredSetupIsComplete: Bool {
        model.systemCheck.microphonePermission == "authorized"
            && model.systemCheck.accessibilityPermission
            && model.session.modelState == .ready
    }
}

private struct SetupStep: View {
    let number: Int
    let title: String
    let detail: String
    let isComplete: Bool
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle")
                .font(.title2)
                .foregroundStyle(isComplete ? .green : .secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isComplete {
                Text("Ready")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(title): ready")
            } else {
                Button(number == 3 ? "Prepare" : "Allow", action: action)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct GeneralSettingsView: View {
    @Bindable var model: AppSettingsModel

    var body: some View {
        SettingsPage(
            "General",
            subtitle: "Choose how dictation behaves across your Mac."
        ) {
            Form {
                Section("Dictation") {
                    Picker(
                        "Output",
                        selection: Binding(
                            get: { model.session.preferences.outputMode },
                            set: { model.session.setOutputMode($0) }
                        )
                    ) {
                        Text("Insert at Cursor").tag(OutputMode.type)
                        Text("Copy to Clipboard").tag(OutputMode.clipboard)
                    }

                    LabeledContent("Shortcut") {
                        HStack {
                            ShortcutRecorderButton(
                                shortcut: model.session.preferences.shortcut,
                                onRecord: model.setShortcut,
                                onError: model.reportShortcutError
                            )
                            Button("Reset") {
                                model.setShortcut(.controlOptionSpace)
                            }
                        }
                    }

                    Picker(
                        "Recording Mode",
                        selection: Binding(
                            get: { model.session.preferences.recordingMode },
                            set: { model.session.setRecordingMode($0) }
                        )
                    ) {
                        ForEach(RecordingMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    Text(recordingModeHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Sound Feedback",
                        isOn: Binding(
                            get: { model.session.preferences.playSounds },
                            set: { model.session.setPlaySounds($0) }
                        )
                    )

                    Toggle(
                        "Show Recording HUD",
                        isOn: Binding(
                            get: { model.session.preferences.showRecordingHUD },
                            set: { model.session.setShowRecordingHUD($0) }
                        )
                    )

                    Toggle(
                        "Enable Dictation Commands",
                        isOn: Binding(
                            get: {
                                model.session.preferences
                                    .dictationCommandsEnabled
                            },
                            set: {
                                model.session.setDictationCommandsEnabled($0)
                            }
                        )
                    )

                    if model.session.preferences.dictationCommandsEnabled {
                        Text(
                            "Say “command new line,” “command new paragraph,” “command comma,” “command period,” “command question mark,” “command scratch that,” “command literal mode,” or “command cancel dictation.” English only."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Audio Input") {
                    Picker(
                        "Microphone",
                        selection: Binding<String?>(
                            get: {
                                model.session.preferences.audioInputDeviceUID
                            },
                            set: { model.setAudioInputDevice($0) }
                        )
                    ) {
                        Text("System Default")
                            .tag(String?.none)
                        ForEach(model.audioInputDevices) { device in
                            Text(
                                device.isSystemDefault
                                    ? "\(device.name) (Default)"
                                    : device.name
                            )
                            .tag(Optional(device.id))
                        }
                    }

                    Text(model.audioInputStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LabeledContent(
                        "Signal",
                        value: model.session.audioInputHealth.label
                    )

                    ProgressView(value: Double(model.session.audioLevel))
                        .accessibilityLabel("Microphone input level")
                        .accessibilityValue(
                            "\(Int(model.session.audioLevel * 100)) percent"
                        )

                    HStack {
                        Button(
                            model.session.isTestingMicrophone
                                ? "Stop Test"
                                : "Test Microphone"
                        ) {
                            if model.session.isTestingMicrophone {
                                model.session.stopMicrophoneTest()
                            } else {
                                model.session.startMicrophoneTest()
                            }
                        }
                        Button("Refresh Devices") {
                            model.refreshAudioInputDevices()
                        }
                    }
                }

                Section {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    .disabled(!model.launchAtLoginAvailable)
                    Text(model.launchAtLoginStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Startup")
                }
            }
            .formStyle(.grouped)

            ActionMessage(message: model.actionMessage)
        }
    }

    private var recordingModeHelp: String {
        switch model.session.preferences.recordingMode {
        case .pressAndHold:
            "Hold the shortcut while speaking, then release to transcribe."
        case .toggle:
            "Press once to start and again to finish."
        case .handsFree:
            "Press once to start. Press again to finish, or Escape to cancel."
        }
    }
}

private struct ShortcutRecorderButton: View {
    let shortcut: RegisteredShortcut
    let onRecord: (RegisteredShortcut) -> Void
    let onError: (Error) -> Void
    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button(isRecording ? "Type Shortcut…" : shortcut.displayName) {
            isRecording ? stopRecording() : startRecording()
        }
        .accessibilityLabel(
            isRecording
                ? "Type a new keyboard shortcut"
                : "Shortcut: \(shortcut.accessibilityName)"
        )
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        guard eventMonitor == nil else { return }
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown
        ) { event in
            guard !event.isARepeat else { return nil }
            if event.keyCode == UInt16(kVK_Escape) {
                Task { @MainActor in stopRecording() }
                return nil
            }

            let modifiers = ShortcutModifiers(event.modifierFlags)
            do {
                let recorded = try RegisteredShortcut(
                    validatingKeyCode: UInt32(event.keyCode),
                    modifiers: modifiers
                )
                Task { @MainActor in
                    onRecord(recorded)
                    stopRecording()
                }
            } catch {
                Task { @MainActor in onError(error) }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}

private extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: ShortcutModifiers = []
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.command) { value.insert(.command) }
        self = value
    }
}

private struct PermissionCenterView: View {
    @Bindable var model: AppSettingsModel

    var body: some View {
        SettingsPage(
            "Permissions",
            subtitle: "Autohand Voice requests only what local dictation needs."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                PermissionRow(
                    title: "Microphone",
                    detail: "Captures speech for local transcription.",
                    isAuthorized: model.systemCheck.microphonePermission == "authorized",
                    status: model.systemCheck.microphonePermission
                ) {
                    if model.systemCheck.microphonePermission == "not-determined" {
                        Task { await model.requestMicrophonePermission() }
                    } else {
                        model.openMicrophoneSettings()
                    }
                }

                Divider()

                PermissionRow(
                    title: "Accessibility",
                    detail: "Inserts only final transcripts into the focused control.",
                    isAuthorized: model.systemCheck.accessibilityPermission,
                    status: model.systemCheck.accessibilityPermission
                        ? "authorized"
                        : "not authorized"
                ) {
                    model.requestAccessibilityPermission()
                }

                Divider()

                LabeledContent("Input Monitoring", value: "Not required")

                HStack {
                    Button("Check Again") {
                        model.refresh()
                    }
                    Spacer()
                }

                ActionMessage(message: model.actionMessage)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let isAuthorized: Bool
    let status: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: isAuthorized ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.title2)
                .foregroundStyle(isAuthorized ? .green : .orange)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                Text(status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isAuthorized {
                Button(
                    status == "not-determined" ? "Allow" : "Open Settings",
                    action: action
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct PrivacyDiagnosticsView: View {
    @Bindable var model: AppSettingsModel
    @State private var confirmsModelRepair = false

    var body: some View {
        SettingsPage(
            "Privacy & Diagnostics",
            subtitle: "Verify the local runtime without exposing dictated text."
        ) {
            Form {
                Section("Privacy") {
                    LabeledContent("Speech Recognition", value: "Local CoreML")
                    LabeledContent("Remote Fallback", value: "Disabled")
                    LabeledContent("Audio Storage", value: "In memory only")
                    LabeledContent("Provisional Text", value: "Never inserted")
                    LabeledContent(
                        "Text History",
                        value: model.session.preferences.historyEnabled
                            ? "Enabled locally"
                            : "Off"
                    )
                }

                Section("Local Speech Model") {
                    Picker(
                        "Model",
                        selection: Binding(
                            get: { model.selectedModelVariant },
                            set: { model.session.setModelVariant($0) }
                        )
                    ) {
                        ForEach(SpeechModelVariant.allCases, id: \.self) {
                            variant in
                            Text(variant.displayName).tag(variant)
                        }
                    }
                    .disabled(
                        model.session.isRecordingOrStarting
                            || model.session.state == .processing
                    )

                    LabeledContent(
                        "Language Coverage",
                        value: model.selectedModelVariant.languageCoverage
                    )
                    LabeledContent(
                        "Readiness",
                        value: model.session.modelStatusLabel
                    )
                    LabeledContent(
                        "Storage",
                        value: model.modelStorageLabel
                    )
                    LabeledContent(
                        "Last Validation",
                        value: model.modelLastValidatedLabel
                    )

                    if model.session.modelState == .preparing {
                        ProgressView(value: model.session.modelProgress)
                            .accessibilityLabel("Model preparation progress")
                            .accessibilityValue(
                                "\(Int(model.session.modelProgress * 100)) percent"
                            )
                    }
                }

                Section("System") {
                    LabeledContent(
                        "Platform",
                        value: model.systemCheck.supported ? "Supported" : "Unsupported"
                    )
                    LabeledContent(
                        "Architecture",
                        value: model.systemCheck.architecture
                    )
                    LabeledContent(
                        "macOS",
                        value: model.systemCheck.macOSVersion
                    )
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Refresh") {
                    model.refresh()
                }
                Button("Prepare Local Model") {
                    model.session.prepareLocalModel()
                }
                Button("Validate") {
                    model.session.validateLocalModel()
                }
                Button("Repair…", role: .destructive) {
                    confirmsModelRepair = true
                }
                if model.session.modelState == .preparing {
                    Button("Cancel") {
                        model.session.cancelModelPreparation()
                    }
                }
                Spacer()
                Button("Copy Diagnostic Report") {
                    model.copyDiagnosticReport()
                }
            }

            ActionMessage(message: model.actionMessage)
        }
        .confirmationDialog(
            "Repair \(model.selectedModelVariant.displayName)?",
            isPresented: $confirmsModelRepair
        ) {
            Button("Redownload Selected Model", role: .destructive) {
                model.session.repairLocalModel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Only this model’s cache is replaced. Other models and user data are preserved."
            )
        }
    }
}

private struct ActionMessage: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(message)")
        }
    }
}
