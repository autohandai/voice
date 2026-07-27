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
    case appProfiles
    case languageModels
    case permissions
    case privacy

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .gettingStarted: "Getting Started"
        case .general: "General"
        case .formatting: "Formatting"
        case .vocabulary: "Vocabulary"
        case .appProfiles: "App Profiles"
        case .languageModels: "Language & Models"
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
        case .appProfiles: "square.stack.3d.up"
        case .languageModels: "character.bubble"
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
        case .appProfiles:
            AppProfilesSettingsView(model: model.appProfiles)
        case .languageModels:
            LanguageModelSettingsView(model: model)
        case .permissions:
            PermissionCenterView(model: model)
        case .privacy:
            PrivacyDiagnosticsView(model: model)
        }
    }
}

private enum ProfileBooleanOverride: String, CaseIterable, Identifiable {
    case global = "Use Global"
    case enabled = "On"
    case disabled = "Off"

    var id: Self { self }

    init(_ value: Bool?) {
        self = value.map { $0 ? .enabled : .disabled } ?? .global
    }

    var value: Bool? {
        switch self {
        case .global: nil
        case .enabled: true
        case .disabled: false
        }
    }
}

private struct AppProfilesSettingsView: View {
    @Bindable var model: AppProfileSettingsModel

    var body: some View {
        SettingsPage(
            "App Profiles",
            subtitle: "Override global behavior using only an app’s bundle identifier."
        ) {
            Form {
                Section("Active") {
                    LabeledContent(
                        "Current Profile",
                        value: model.sessionLabel
                    )
                }

                Section("Add Running App") {
                    Picker(
                        "Application",
                        selection: $model.selectedRunningBundleIdentifier
                    ) {
                        ForEach(model.runningApps) { app in
                            Text("\(app.name) — \(app.id)")
                                .tag(Optional(app.id))
                        }
                    }
                    HStack {
                        Button("Refresh Apps") {
                            model.refreshRunningApps()
                        }
                        Button("Add Profile") {
                            model.addRunningApp()
                        }
                        .disabled(model.selectedRunningBundleIdentifier == nil)
                    }
                }

                Section("Add by Bundle Identifier") {
                    TextField("Profile name", text: $model.manualName)
                    TextField(
                        "Bundle identifier, for example com.example.Editor",
                        text: $model.manualBundleIdentifier
                    )
                    HStack {
                        Spacer()
                        Button("Add Profile") {
                            model.addManual()
                        }
                    }
                }

                Section("Profiles") {
                    if model.profiles.isEmpty {
                        ContentUnavailableView(
                            "No App Profiles",
                            systemImage: "square.stack.3d.up",
                            description: Text(
                                "Global settings apply to every application."
                            )
                        )
                    } else {
                        Picker("Profile", selection: $model.selectedID) {
                            ForEach(model.profiles) { profile in
                                Text(profile.name).tag(Optional(profile.id))
                            }
                        }
                        if let profile = model.selectedProfile {
                            LabeledContent(
                                "Bundle Identifier",
                                value: profile.bundleIdentifier
                            )
                            profileOverrides(profile)
                            HStack {
                                Spacer()
                                Button("Delete Profile", role: .destructive) {
                                    model.deleteSelected()
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Text(
                "Profiles match exact bundle identifiers. No window title, document name, or app content is read. Any setting left on Use Global follows General."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            ActionMessage(message: model.message)
        }
    }

    @ViewBuilder
    private func profileOverrides(_ profile: AppProfile) -> some View {
        Picker(
            "Output",
            selection: Binding<OutputMode?>(
                get: { profile.outputMode },
                set: { value in
                    model.updateSelected { $0.outputMode = value }
                }
            )
        ) {
            Text("Use Global").tag(OutputMode?.none)
            Text("Insert at Cursor").tag(Optional(OutputMode.type))
            Text("Copy to Clipboard").tag(Optional(OutputMode.clipboard))
        }

        Picker(
            "Recording Mode",
            selection: Binding<RecordingMode?>(
                get: { profile.recordingMode },
                set: { value in
                    model.updateSelected { $0.recordingMode = value }
                }
            )
        ) {
            Text("Use Global").tag(RecordingMode?.none)
            ForEach(RecordingMode.allCases, id: \.self) {
                Text($0.displayName).tag(Optional($0))
            }
        }

        Picker(
            "Local Model",
            selection: Binding<String?>(
                get: { profile.modelVersion },
                set: { value in
                    model.updateSelected { $0.modelVersion = value }
                }
            )
        ) {
            Text("Use Global").tag(String?.none)
            ForEach(SpeechModelVariant.allCases, id: \.self) {
                Text($0.displayName).tag(Optional($0.rawValue))
            }
        }

        Picker(
            "Dictation Language",
            selection: Binding<String?>(
                get: { profile.dictationLanguageCode },
                set: { value in
                    model.updateSelected {
                        $0.dictationLanguageCode = value
                    }
                }
            )
        ) {
            Text("Use Global").tag(String?.none)
            ForEach(SupportedDictationLanguage.displayOrder, id: \.self) {
                Text($0.displayName).tag(Optional($0.code))
            }
        }

        booleanOverride(
            "Dictation Commands",
            value: profile.dictationCommandsEnabled
        ) { value in
            model.updateSelected {
                $0.dictationCommandsEnabled = value
            }
        }
        booleanOverride(
            "Smart Formatting",
            value: profile.smartFormattingEnabled
        ) { value in
            model.updateSelected {
                $0.smartFormattingEnabled = value
            }
        }
        booleanOverride(
            "Terminal Punctuation",
            value: profile.automaticTerminalPunctuation
        ) { value in
            model.updateSelected {
                $0.automaticTerminalPunctuation = value
            }
        }
        booleanOverride(
            "Recording HUD",
            value: profile.showRecordingHUD
        ) { value in
            model.updateSelected { $0.showRecordingHUD = value }
        }
        booleanOverride(
            "Live Provisional Preview",
            value: profile.livePreviewEnabled
        ) { value in
            model.updateSelected { $0.livePreviewEnabled = value }
        }
        booleanOverride(
            "Sound Feedback",
            value: profile.playSounds
        ) { value in
            model.updateSelected { $0.playSounds = value }
        }
    }

    private func booleanOverride(
        _ title: String,
        value: Bool?,
        update: @escaping (Bool?) -> Void
    ) -> some View {
        Picker(
            title,
            selection: Binding(
                get: { ProfileBooleanOverride(value) },
                set: { update($0.value) }
            )
        ) {
            ForEach(ProfileBooleanOverride.allCases) {
                Text(LocalizedStringKey($0.rawValue)).tag($0)
            }
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
                            Text(LocalizedStringKey($0.rawValue)).tag($0)
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
                model.session.preferences.automaticTerminalPunctuation,
            locale: Locale(
                identifier:
                    model.session.preferences.dictationLanguageCode
            )
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
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    init(
        _ title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
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
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
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
                    .accessibilityLabel(title)
                    .accessibilityValue("Ready")
            } else {
                Button(action: action) {
                    if number == 3 {
                        Text("Prepare")
                    } else {
                        Text("Allow")
                    }
                }
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
                            Text(LocalizedStringKey(mode.displayName)).tag(mode)
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
                        "Live Provisional Preview",
                        isOn: Binding(
                            get: {
                                model.session.preferences.livePreviewEnabled
                            },
                            set: {
                                model.session.setLivePreviewEnabled($0)
                            }
                        )
                    )

                    if model.session.preferences.livePreviewEnabled {
                        Text(
                            "Shows changing local text only inside the HUD. Provisional text is never inserted; stopping runs one final language-aware transcription."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

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
                        Button {
                            if model.session.isTestingMicrophone {
                                model.session.stopMicrophoneTest()
                            } else {
                                model.session.startMicrophoneTest()
                            }
                        } label: {
                            if model.session.isTestingMicrophone {
                                Text("Stop Test")
                            } else {
                                Text("Test Microphone")
                            }
                        }
                        .accessibilityHint(
                            model.session.isTestingMicrophone
                                ? "Stops the microphone level test."
                                : "Starts a local microphone level test."
                        )
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

    private var recordingModeHelp: LocalizedStringKey {
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
        Button {
            isRecording ? stopRecording() : startRecording()
        } label: {
            if isRecording {
                Text("Type Shortcut…")
            } else {
                Text(verbatim: shortcut.displayName)
            }
        }
        .accessibilityLabel(
            isRecording
                ? "Type a new keyboard shortcut"
                : "Shortcut: \(shortcut.accessibilityName)"
        )
        .accessibilityHint(
            isRecording
                ? "Press the desired key combination, or Escape to cancel."
                : "Starts recording a new global shortcut."
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
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
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
                Text(verbatim: status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isAuthorized {
                Button(action: action) {
                    if status == "not-determined" {
                        Text("Allow")
                    } else {
                        Text("Open Settings")
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(
            isAuthorized ? "Authorized" : status.capitalized
        )
    }
}

private struct LanguageModelSettingsView: View {
    @Bindable var model: AppSettingsModel
    @State private var confirmsModelRepair = false
    @State private var confirmsModelRemoval = false

    var body: some View {
        SettingsPage(
            "Language & Models",
            subtitle: "Choose a documented local transcription profile."
        ) {
            Form {
                Section("Dictation Language") {
                    Picker(
                        "Language",
                        selection: Binding(
                            get: { model.selectedDictationLanguage },
                            set: { model.session.setDictationLanguage($0) }
                        )
                    ) {
                        ForEach(
                            SupportedDictationLanguage.displayOrder,
                            id: \.self
                        ) {
                            Text($0.displayName).tag($0)
                        }
                    }

                    LabeledContent("Try Saying") {
                        Text(model.selectedDictationLanguage.testPhrase)
                            .textSelection(.enabled)
                    }

                    Text(
                        "Language guides this local profile. Autohand Voice transcribes speech; it does not translate it."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    Text(modelRecommendation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Button("Prepare Local Model") {
                    model.session.prepareLocalModel()
                }
                Button("Validate") {
                    model.session.validateLocalModel()
                }
                Button("Repair…", role: .destructive) {
                    confirmsModelRepair = true
                }
                Button("Remove…", role: .destructive) {
                    confirmsModelRemoval = true
                }
                if model.session.modelState == .preparing {
                    Button("Cancel") {
                        model.session.cancelModelPreparation()
                    }
                }
                Spacer()
            }
            .disabled(
                model.session.isRecordingOrStarting
                    || model.session.state == .processing
            )
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
        .confirmationDialog(
            "Remove \(model.selectedModelVariant.displayName)?",
            isPresented: $confirmsModelRemoval
        ) {
            Button("Remove Local Model", role: .destructive) {
                model.session.removeLocalModel(
                    model.selectedModelVariant
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Only the selected known model cache is removed. It must be prepared again before use."
            )
        }
    }

    private var modelRecommendation: String {
        switch model.selectedModelVariant {
        case .v2:
            "English-focused profile for stronger recall on rare English words."
        case .v3:
            "Multilingual profile for the 25 documented European languages."
        }
    }
}

private struct PrivacyDiagnosticsView: View {
    @Bindable var model: AppSettingsModel

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
                    LabeledContent(
                        "Selected Language",
                        value: model.selectedDictationLanguage.displayName
                    )
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
                Spacer()
                Button("Copy Diagnostic Report") {
                    model.copyDiagnosticReport()
                }
            }

            ActionMessage(message: model.actionMessage)
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
