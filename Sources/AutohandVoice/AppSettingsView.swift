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
    @State private var forceOnboarding = false

    init(model: AppSettingsModel) {
        self.model = model
        _selection = State(
            initialValue: model.session.preferences.hasCompletedOnboarding
                ? .general
                : .gettingStarted
        )
    }

    var body: some View {
        if !model.session.preferences.hasCompletedOnboarding
            || forceOnboarding
        {
            OnboardingView(model: model) {
                if !model.session.preferences.hasCompletedOnboarding {
                    model.completeOnboarding()
                }
                forceOnboarding = false
                selection = .general
            }
        } else {
            settings
        }
    }

    private var settings: some View {
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
                forceOnboarding = true
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
        if model.minimalContextCapabilityEnabled {
            Picker(
                "Context Access",
                selection: Binding<AppContextAccess?>(
                    get: { profile.contextAccess },
                    set: { value in
                        model.updateSelected { $0.contextAccess = value }
                    }
                )
            ) {
                Text("Use Global").tag(AppContextAccess?.none)
                Text("Allow Minimum Context")
                    .tag(Optional(AppContextAccess.enabled))
                Text("No Context")
                    .tag(Optional(AppContextAccess.disabled))
            }
        }
        booleanOverride(
            "Sensitive App",
            value: profile.isSensitive
        ) { value in
            model.updateSelected {
                $0.isSensitive = value
            }
        }
        Picker(
            "Dictation Style",
            selection: Binding<UUID?>(
                get: { profile.styleID },
                set: { value in
                    model.updateSelected { $0.styleID = value }
                }
            )
        ) {
            Text("Use Global").tag(UUID?.none)
            ForEach(model.dictationStyles) { style in
                Text(style.name).tag(Optional(style.id))
            }
        }
        Picker(
            "Cleanup Level",
            selection: Binding<CleanupLevel?>(
                get: { profile.cleanupLevel },
                set: { value in
                    model.updateSelected {
                        $0.cleanupLevel = value
                        $0.smartFormattingEnabled = value.map {
                            $0 != .literal
                        }
                    }
                }
            )
        ) {
            Text("Use Global").tag(CleanupLevel?.none)
            Text("Literal").tag(Optional(CleanupLevel.literal))
            Text("Light").tag(Optional(CleanupLevel.light))
            Text("Medium").tag(Optional(CleanupLevel.medium))
            if model.localTransformsEnabled {
                Text("High").tag(Optional(CleanupLevel.high))
            }
        }
        .disabled(profile.styleID != nil)
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
    @State private var styleName = ""
    @State private var styleCleanupLevel = CleanupLevel.medium
    @State private var stylePunctuation = true
    @State private var styleVocabulary = true

    var body: some View {
        SettingsPage(
            "Formatting",
            subtitle: "Clean up spoken text locally before it reaches the cursor."
        ) {
            Form {
                Section("Dictation Styles") {
                    Picker(
                        "Default Style",
                        selection: Binding<UUID?>(
                            get: {
                                model.session.preferences.defaultStyleID
                            },
                            set: {
                                model.session.setDefaultDictationStyle($0)
                            }
                        )
                    ) {
                        Text("Manual Settings").tag(UUID?.none)
                        ForEach(model.session.dictationStyles) { style in
                            Text(style.name).tag(Optional(style.id))
                        }
                    }

                    Picker(
                        "Temporary Override",
                        selection: Binding<UUID?>(
                            get: {
                                model.session.temporaryStyleOverrideID
                            },
                            set: {
                                model.session
                                    .setTemporaryDictationStyle($0)
                            }
                        )
                    ) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.session.dictationStyles) { style in
                            Text(style.name).tag(Optional(style.id))
                        }
                    }

                    LabeledContent(
                        "Active",
                        value: "\(model.session.activeStyleLabel) · \(model.session.activeStyleSource.rawValue.replacingOccurrences(of: "_", with: " "))"
                    )

                    TextField("New style name", text: $styleName)
                    Picker(
                        "New Style Cleanup",
                        selection: $styleCleanupLevel
                    ) {
                        Text("Literal").tag(CleanupLevel.literal)
                        Text("Light").tag(CleanupLevel.light)
                        Text("Medium").tag(CleanupLevel.medium)
                        if model.session.localTransformsEnabled {
                            Text("High").tag(CleanupLevel.high)
                        }
                    }
                    Toggle(
                        "New Style Adds Terminal Punctuation",
                        isOn: $stylePunctuation
                    )
                    Toggle(
                        "New Style Uses Vocabulary",
                        isOn: $styleVocabulary
                    )
                    HStack {
                        Button("Add Style") {
                            addStyle()
                        }
                        .disabled(
                            styleName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                        )
                        Spacer()
                    }

                    ForEach(model.session.customDictationStyles) { style in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.name)
                                Text(style.cleanupLevel.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Delete", role: .destructive) {
                                deleteStyle(style)
                            }
                        }
                    }

                    Text(
                        "Temporary overrides expire after 15 minutes without dictation and never change the stored default."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Local Refinement") {
                    Picker(
                        "Cleanup Level",
                        selection: Binding(
                            get: {
                                model.session.preferences.cleanupLevel
                            },
                            set: {
                                model.session.setCleanupLevel($0)
                            }
                        )
                    ) {
                        Text("Literal").tag(CleanupLevel.literal)
                        Text("Light").tag(CleanupLevel.light)
                        Text("Medium").tag(CleanupLevel.medium)
                        if model.session.localTransformsEnabled {
                            Text("High").tag(CleanupLevel.high)
                        }
                    }

                    Text(cleanupLevelHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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
                    .disabled(
                        model.session.preferences.cleanupLevel != .medium
                    )
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
                "Cleanup is deterministic and local. The immutable raw final remains available for revision recovery; High stays unavailable until its separate signed local CoreML model passes release review."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var cleanupLevelHelp: LocalizedStringKey {
        switch model.session.preferences.cleanupLevel {
        case .literal:
            "Preserves the final transcript except for explicit vocabulary replacements."
        case .light:
            "Removes high-confidence fillers and accidental repetition, then applies vocabulary."
        case .medium:
            "Adds local spacing, capitalization, and punctuation to Light cleanup."
        case .high:
            "Uses the optional local Transform model. No remote fallback is allowed."
        }
    }

    private var preview: String {
        let cleanupLevel = model.session.preferences.cleanupLevel
        guard cleanupLevel != .literal else { return previewText }
        let refined = SpeechTextRefiner.refine(
            previewText,
            enabled: true,
            locale: Locale(
                identifier:
                    model.session.preferences.dictationLanguageCode
            )
        )
        guard cleanupLevel == .medium else { return refined }
        return SmartTextFormatter.format(
            refined,
            context: previewPosition.context,
            enabled: true,
            addsTerminalPunctuation:
                model.session.preferences.automaticTerminalPunctuation,
            locale: Locale(
                identifier:
                    model.session.preferences.dictationLanguageCode
            )
        )
    }

    private func addStyle() {
        var styles = model.session.customDictationStyles
        styles.append(
            DictationStylePreset(
                name: styleName,
                cleanupLevel: styleCleanupLevel,
                automaticTerminalPunctuation: stylePunctuation,
                vocabularyEnabled: styleVocabulary
            )
        )
        model.session.saveCustomDictationStyles(styles)
        if model.session.styleError == nil {
            styleName = ""
        }
    }

    private func deleteStyle(_ style: DictationStylePreset) {
        model.session.saveCustomDictationStyles(
            model.session.customDictationStyles.filter {
                $0.id != style.id
            }
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

                Section("Local Suggestion Review") {
                    Toggle(
                        "Learn from Explicit Corrections",
                        isOn: Binding(
                            get: { model.suggestionsEnabled },
                            set: { model.setSuggestionsEnabled($0) }
                        )
                    )
                    Text(
                        "When enabled, a correction you explicitly submit from History becomes a pending local suggestion. It never becomes an active replacement until you confirm it here."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if model.suggestionsEnabled {
                        if model.suggestions.isEmpty {
                            Text("No suggestions waiting for review.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.suggestions) { suggestion in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(suggestion.source)
                                            .lineLimit(2)
                                        Image(systemName: "arrow.right")
                                            .foregroundStyle(.secondary)
                                        Text(suggestion.replacement)
                                            .lineLimit(2)
                                    }
                                    Text(
                                        "Observed \(suggestion.observationCount) time\(suggestion.observationCount == 1 ? "" : "s")"
                                    )
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    HStack {
                                        Button("Confirm") {
                                            model.acceptSuggestion(
                                                suggestion
                                            )
                                        }
                                        Button(
                                            "Dismiss",
                                            role: .destructive
                                        ) {
                                            model.dismissSuggestion(
                                                suggestion
                                            )
                                        }
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
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
                                HStack(alignment: .firstTextBaseline) {
                                    Button {
                                        model.toggleStar(rule)
                                    } label: {
                                        Image(
                                            systemName: rule.isStarred
                                                ? "star.fill"
                                                : "star"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help(
                                        rule.isStarred
                                            ? "Unstar Replacement"
                                            : "Star Replacement"
                                    )
                                    .accessibilityLabel(
                                        rule.isStarred
                                            ? "Unstar \(rule.source)"
                                            : "Star \(rule.source)"
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(rule.source)
                                        Text(
                                            "\(rule.usageCount) use\(rule.usageCount == 1 ? "" : "s")"
                                        )
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        if let lastUsedAt =
                                            rule.lastUsedAt
                                        {
                                            Text(
                                                "Last used \(lastUsedAt.formatted(date: .abbreviated, time: .shortened))"
                                            )
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Text(rule.replacement)
                                        .textSelection(.enabled)
                                }
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
    let onOpenGuide: () -> Void

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

                    Button("Run Guided Setup Again") {
                        onOpenGuide()
                    }
                    .buttonStyle(.borderedProminent)
                }

                ActionMessage(message: model.actionMessage)
            }
        }
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
    @State private var confirmsPointerMonitoring = false

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

                    LabeledContent("Primary Activation") {
                        primaryActivationLabel
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        "Use Long-press Fn",
                        isOn: Binding(
                            get: {
                                model.session.preferences
                                    .functionKeyLongPressEnabled
                            },
                            set: {
                                model.session
                                    .setFunctionKeyLongPressEnabled($0)
                            }
                        )
                    )

                    Text(
                        "Hold Fn for 0.4 seconds to start, then release to finish. Short presses keep their normal macOS behavior."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if model.session.preferences
                        .functionKeyLongPressEnabled
                    {
                        Text(model.session.functionKeyLongPressStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Fallback Shortcut") {
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

                    LabeledContent("Cancel Shortcut") {
                        HStack {
                            ShortcutRecorderButton(
                                shortcut: model.session.keyboardBinding(
                                    for: .cancel
                                ),
                                onRecord: {
                                    _ = model.session.setKeyboardBinding(
                                        $0,
                                        for: .cancel
                                    )
                                },
                                onError: model.reportShortcutError
                            )
                            if model.session.keyboardBinding(
                                for: .cancel
                            ) != nil {
                                Button("Remove") {
                                    _ = model.session.setKeyboardBinding(
                                        nil,
                                        for: .cancel
                                    )
                                }
                            }
                        }
                    }

                    LabeledContent("Commit Shortcut") {
                        HStack {
                            ShortcutRecorderButton(
                                shortcut: model.session.keyboardBinding(
                                    for: .commit
                                ),
                                onRecord: {
                                    _ = model.session.setKeyboardBinding(
                                        $0,
                                        for: .commit
                                    )
                                },
                                onError: model.reportShortcutError
                            )
                            if model.session.keyboardBinding(
                                for: .commit
                            ) != nil {
                                Button("Remove") {
                                    _ = model.session.setKeyboardBinding(
                                        nil,
                                        for: .commit
                                    )
                                }
                            }
                        }
                    }

                    Text(
                        "Escape still cancels Hands-Free recording. A Commit shortcut sends Enter only during the brief verified window after a successful typed insertion."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if model.session.scratchpadEnabled {
                        LabeledContent("Scratchpad Shortcut") {
                            HStack {
                                ShortcutRecorderButton(
                                    shortcut: model.session.preferences
                                        .scratchpadShortcut,
                                    onRecord:
                                        model.setScratchpadShortcut,
                                    onError: model.reportShortcutError
                                )
                                Button("Reset") {
                                    model.setScratchpadShortcut(.optionS)
                                }
                            }
                        }
                        if let error =
                            model.session.scratchpadShortcutError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }

                    if model.session.pointerInputCapabilityEnabled {
                        Toggle(
                            "Extra Mouse Button Control",
                            isOn: Binding(
                                get: {
                                    model.session.preferences
                                        .pointerMonitoringEnabled
                                },
                                set: { enabled in
                                    if enabled {
                                        confirmsPointerMonitoring = true
                                    } else {
                                        model.session
                                            .setPointerMonitoringEnabled(
                                                false
                                            )
                                    }
                                }
                            )
                        )
                        Text(model.session.pointerInputStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let button =
                            model.session.observedPointerButton
                        {
                            Picker(
                                "Mouse Button \(button + 1)",
                                selection: Binding(
                                    get: {
                                        model.session.preferences
                                            .inputBindings
                                            .first {
                                                $0.trigger == .pointer(
                                                    button: button
                                                )
                                            }?.action ?? .startStop
                                    },
                                    set: {
                                        model.session
                                            .bindObservedPointerButton(
                                                to: $0
                                            )
                                    }
                                )
                            ) {
                                ForEach(
                                    InputBindingAction.allCases,
                                    id: \.self
                                ) { action in
                                    Text(action.displayName).tag(action)
                                }
                            }
                            Button(
                                "Remove Mouse Binding",
                                role: .destructive
                            ) {
                                model.session.removePointerBinding(
                                    button
                                )
                            }
                        }

                    }

                    if let error = model.session.inputBindingError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
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

                    if model.session.hudCustomizationEnabled,
                       model.session.preferences.showRecordingHUD
                    {
                        Picker(
                            "HUD Style",
                            selection: Binding(
                                get: {
                                    model.session.preferences.recordingHUDMode
                                },
                                set: {
                                    model.session.setRecordingHUDMode($0)
                                }
                            )
                        ) {
                            Text("Automatic")
                                .tag(RecordingHUDPresentationMode.automatic)
                            Text("Compact")
                                .tag(RecordingHUDPresentationMode.compact)
                            Text("Dot")
                                .tag(RecordingHUDPresentationMode.dot)
                        }

                        LabeledContent("HUD Opacity") {
                            HStack {
                                Slider(
                                    value: Binding(
                                        get: {
                                            model.session.preferences
                                                .recordingHUDOpacity
                                        },
                                        set: {
                                            model.session
                                                .setRecordingHUDOpacity($0)
                                        }
                                    ),
                                    in: 0.2 ... 1
                                )
                                .frame(width: 140)

                                Text(
                                    "\(Int(model.session.preferences.recordingHUDOpacity * 100))%"
                                )
                                .monospacedDigit()
                                .frame(width: 42, alignment: .trailing)
                            }
                        }

                        Picker(
                            "HUD Edge",
                            selection: Binding(
                                get: { currentHUDPlacement.anchor },
                                set: { setHUDAnchor($0) }
                            )
                        ) {
                            Text("Left").tag(RecordingHUDAnchor.left)
                            Text("Bottom").tag(RecordingHUDAnchor.bottom)
                            Text("Right").tag(RecordingHUDAnchor.right)
                        }

                        HStack {
                            Text(
                                "Drag the recording HUD to fine-tune its position on each display."
                            )
                            Spacer()
                            Button("Reset Position") {
                                setHUDAnchor(currentHUDPlacement.anchor)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

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

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Microphone Priority")
                            .font(.headline)

                        ForEach(
                            model.audioInputPriority,
                            id: \.self
                        ) { identifier in
                            let index = model.audioInputPriority
                                .firstIndex(of: identifier) ?? 0
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 18, alignment: .trailing)

                                Text(
                                    model.audioInputPriorityLabel(
                                        identifier
                                    )
                                )
                                .lineLimit(1)

                                Spacer()

                                Button {
                                    model.moveAudioInputPriority(
                                        identifier,
                                        offset: -1
                                    )
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == 0)
                                .accessibilityLabel(
                                    "Move microphone earlier"
                                )

                                Button {
                                    model.moveAudioInputPriority(
                                        identifier,
                                        offset: 1
                                    )
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(
                                    index
                                        == model.audioInputPriority.count - 1
                                )
                                .accessibilityLabel(
                                    "Move microphone later"
                                )
                            }
                        }
                    }

                    Toggle(
                        "Automatic Microphone Handoff",
                        isOn: Binding(
                            get: {
                                model.session.preferences
                                    .automaticAudioHandoffEnabled
                            },
                            set: {
                                model.session
                                    .setAutomaticAudioHandoff($0)
                            }
                        )
                    )

                    Text(
                        "At rest, the first available route wins. During recording, an enabled handoff creates a bounded audio segment without restarting recognition or discarding earlier samples."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        .confirmationDialog(
            "Enable extra mouse button control?",
            isPresented: $confirmsPointerMonitoring
        ) {
            Button("Continue to Input Monitoring") {
                model.session.setPointerMonitoringEnabled(true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Autohand Voice will ask macOS for Input Monitoring so it can observe only non-primary mouse-button down and up events. Primary and secondary click are never captured, and keyboard dictation keeps working if permission is denied."
            )
        }
    }

    @ViewBuilder
    private var primaryActivationLabel: some View {
        switch model.session.preferences.primaryActivationMethod {
        case .functionKeyLongPress:
            Text("Long-press Fn")
        case let .keyboard(shortcut):
            Text(shortcut.accessibilityName)
        }
    }

    private var currentHUDDisplayID: String {
        guard let screen = NSScreen.main else { return "main" }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?
            .stringValue ?? screen.localizedName
    }

    private var currentHUDPlacement: RecordingHUDDisplayPreference {
        model.session.recordingHUDPlacement(for: currentHUDDisplayID)
    }

    private func setHUDAnchor(_ anchor: RecordingHUDAnchor) {
        model.session.setRecordingHUDPlacement(
            RecordingHUDDisplayPreference(
                displayID: currentHUDDisplayID,
                anchor: anchor,
                offset: .zero
            )
        )
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
    let shortcut: RegisteredShortcut?
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
                Text(
                    verbatim:
                        shortcut?.displayName ?? "Set Shortcut…"
                )
            }
        }
        .accessibilityLabel(
            isRecording
                ? "Type a new keyboard shortcut"
                : shortcut.map {
                    "Shortcut: \($0.accessibilityName)"
                } ?? "Set keyboard shortcut"
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

                if model.session.pointerInputCapabilityEnabled
                    || model.session.preferences
                        .functionKeyLongPressEnabled
                {
                    PermissionRow(
                        title: "Fn Key Access",
                        detail:
                            "Uses Accessibility access when available, or optional Input Monitoring, to observe long-press Fn without reading typed text.",
                        isAuthorized: inputMonitoringAuthorized,
                        status: inputMonitoringStatus
                    ) {
                        model.openInputMonitoringSettings()
                    }
                } else {
                    LabeledContent(
                        "Input Monitoring",
                        value: "Not required"
                    )
                }

                HStack {
                    Button("Check Again") {
                        model.recheckPermissions()
                    }
                    Spacer()
                }

                ActionMessage(message: model.actionMessage)
            }
        }
    }

    private var inputMonitoringAuthorized: Bool {
        let fnReady = !model.session.preferences
            .functionKeyLongPressEnabled
            || model.session.functionKeyLongPressStatus.hasPrefix("On")
        let pointerReady = !model.session.preferences
            .pointerMonitoringEnabled
            || (
                !model.session.pointerInputStatus.contains("denied")
                    && !model.session.pointerInputStatus
                        .contains("unavailable")
            )
        return fnReady && pointerReady
    }

    private var inputMonitoringStatus: String {
        if model.session.preferences.functionKeyLongPressEnabled {
            return model.session.functionKeyLongPressStatus
        }
        return model.session.pointerInputStatus
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
                    if model.session.shouldRecommendCanadianEnglish {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(
                                "Use Canadian English spelling?",
                                systemImage: "textformat.abc"
                            )
                            .font(.headline)

                            Text(
                                "Your Mac is set to English (Canada). Canadian spelling is a local cleanup policy, not a different speech model, and Literal output remains unchanged."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            HStack {
                                Button("Use Canadian Spelling") {
                                    model.session
                                        .acceptCanadianEnglishRecommendation()
                                }
                                Button("Not Now") {
                                    model.session
                                        .dismissCanadianEnglishRecommendation()
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

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

                    Picker(
                        "English Spelling",
                        selection: Binding(
                            get: {
                                model.session.preferences
                                    .englishSpellingPolicy
                            },
                            set: {
                                model.session.setEnglishSpellingPolicy($0)
                            }
                        )
                    ) {
                        ForEach(EnglishSpellingPolicy.allCases, id: \.self) {
                            Text(LocalizedStringKey($0.displayName)).tag($0)
                        }
                    }
                    .disabled(
                        model.session.isRecordingOrStarting
                            || model.session.state == .processing
                    )

                    Text(
                        "Canadian spelling applies only during Light or Medium local cleanup. Literal transcripts and non-English languages are never rewritten."
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

                    if model.session.showsModelPreparationProgress {
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
    @State private var confirmsClearIssues = false
    @State private var confirmsClearReliability = false
    @State private var confirmsResetAllLocalData = false
    @State private var sensitiveBundleIdentifier = ""

    var body: some View {
        SettingsPage(
            "Privacy & Diagnostics",
            subtitle: "Verify the local runtime without exposing dictated text."
        ) {
            Form {
                if model.session.notificationCapabilityEnabled {
                    Section("Notifications") {
                        Toggle(
                            "Allow System Notifications",
                            isOn: Binding(
                                get: {
                                    model.session.preferences
                                        .notificationPreferences
                                        .systemNotificationsEnabled
                                },
                                set: {
                                    model.session
                                        .setSystemNotificationsEnabled($0)
                                }
                            )
                        )
                        Text(
                            "Permission is requested only after you enable this. Muting system notifications never hides active failures from the HUD or menu."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        ForEach(
                            VoiceNotificationCategory.allCases,
                            id: \.self
                        ) { category in
                            Toggle(
                                category.rawValue
                                    .replacingOccurrences(
                                        of: "_",
                                        with: " "
                                    )
                                    .capitalized,
                                isOn: Binding(
                                    get: {
                                        !model.session.preferences
                                            .notificationPreferences
                                            .mutedCategories
                                            .contains(category)
                                    },
                                    set: { enabled in
                                        model.session
                                            .setNotificationCategory(
                                                category,
                                                muted: !enabled
                                            )
                                    }
                                )
                            )
                        }
                    }
                }

                Section("Sensitive Target Protection") {
                    LabeledContent(
                        "Built-in rules",
                        value: SensitiveAppRuleset.builtIn.hasValidSignature
                            ? "Signature verified"
                            : "Signature invalid"
                    )

                    Text(
                        "Password and secure text fields are always blocked before the microphone starts. Signed built-in rules and the exact bundle identifiers below add app-level protection without reading window titles, URLs, or field contents."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        TextField(
                            "Bundle identifier",
                            text: $sensitiveBundleIdentifier
                        )
                        Button("Add Sensitive App") {
                            model.session.addSensitiveApp(
                                sensitiveBundleIdentifier
                            )
                            sensitiveBundleIdentifier = ""
                        }
                        .disabled(
                            !sensitiveBundleIdentifier.contains(".")
                        )
                    }

                    ForEach(
                        model.session.preferences.sensitiveAppDenylist,
                        id: \.self
                    ) { bundleIdentifier in
                        HStack {
                            Text(verbatim: bundleIdentifier)
                                .textSelection(.enabled)
                            Spacer()
                            Button("Remove") {
                                model.session.removeSensitiveApp(
                                    bundleIdentifier
                                )
                            }
                        }
                    }

                    if model.session.minimalContextCapabilityEnabled {
                        Toggle(
                            "Allow Minimum Context",
                            isOn: Binding(
                                get: {
                                    model.session.preferences
                                        .minimalContextEnabled
                                },
                                set: {
                                    model.session
                                        .setMinimalContextEnabled($0)
                                }
                            )
                        )
                        Text(
                            "When enabled, Autohand Voice may read at most 64 adjacent Unicode scalars for local continuation. Context stays in memory and is cleared with the dictation session."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Runtime Checks") {
                    ForEach(model.diagnosticSnapshot.checks) { check in
                        DiagnosticCheckRow(check: check) {
                            if let remediation = check.remediation {
                                model.performDiagnosticRemediation(
                                    remediation
                                )
                            }
                        }
                    }
                }

                Section("Local Status") {
                    LabeledContent(
                        "Overall",
                        value: model.session.localStatusSnapshot
                            .overall.rawValue
                            .replacingOccurrences(of: "_", with: " ")
                            .capitalized
                    )
                    ForEach(model.session.localStatusSnapshot.items) {
                        item in
                        LabeledContent {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(
                                    item.state.rawValue
                                        .replacingOccurrences(
                                            of: "_",
                                            with: " "
                                        )
                                        .capitalized
                                )
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } label: {
                            Text(item.domain.rawValue.capitalized)
                        }
                    }
                    Text(
                        "This status is derived only from local finite state. No incident page is shown for local-only capabilities."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Recent Operational Issues") {
                    if model.operationalIssues.isEmpty {
                        Label(
                            "No recent operational issues",
                            systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.operationalIssues) { issue in
                            LabeledContent {
                                Text(
                                    "\(issue.count.formatted()) · "
                                        + issue.lastSeenAt.formatted(
                                            date: .abbreviated,
                                            time: .shortened
                                        )
                                )
                            } label: {
                                Text(LocalizedStringKey(issue.kind.title))
                            }
                        }
                        Button(
                            "Clear Recent Issues…",
                            role: .destructive
                        ) {
                            confirmsClearIssues = true
                        }
                    }
                }

                Section("Reliability Aggregates") {
                    LabeledContent("Local status") {
                        Text(verbatim: model.reliabilityStatus)
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "The reliability ledger contains only finite outcome counts, bounded latency buckets, dates, app and model versions, and supported-platform state. It never stores dictated text or audio."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack {
                        Button("Copy Reliability Report") {
                            model.copyReliabilityReport()
                        }
                        Spacer()
                        Button(
                            "Clear Reliability Aggregates…",
                            role: .destructive
                        ) {
                            confirmsClearReliability = true
                        }
                    }
                }

                Section("Report Privacy") {
                    Text(
                        "The copied report contains only diagnostic states, aggregate issue categories and counts, dates, and model disk bytes. It excludes transcript text, audio, file paths, usernames, focused content, credentials, environment values, and microphone names."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section("Reset All Local Data") {
                    Text(
                        "Deletes preferences, History, vocabulary, app profiles, styles, insights, diagnostics, Scratchpad notes and assets, transform templates, encrypted recovery artifacts, and the Keychain recovery key. Local model files are not user content and remain installed."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button(
                        model.session.isResettingLocalData
                            ? "Resetting…"
                            : "Reset All Local Data…",
                        role: .destructive
                    ) {
                        confirmsResetAllLocalData = true
                    }
                    .disabled(
                        model.session.isResettingLocalData
                            || model.session.state == .processing
                    )

                    if let message =
                        model.session.localDataResetMessage
                    {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(
                                model.session.state == .ready
                                    ? Color.secondary
                                    : Color.red
                            )
                            .textSelection(.enabled)
                    }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .parityGlassSurface()

            ActionMessage(message: model.actionMessage)
        }
        .confirmationDialog(
            "Clear recent operational issues?",
            isPresented: $confirmsClearIssues
        ) {
            Button("Clear Issues", role: .destructive) {
                model.clearOperationalIssues()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes only bounded diagnostic categories and counts. It does not change settings or transcript history."
            )
        }
        .confirmationDialog(
            "Clear reliability aggregates?",
            isPresented: $confirmsClearReliability
        ) {
            Button("Clear Aggregates", role: .destructive) {
                model.clearReliabilityAggregates()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This removes only redacted daily outcome counts and latency buckets. It does not change settings, models, or transcript history."
            )
        }
        .confirmationDialog(
            "Reset all local user data?",
            isPresented: $confirmsResetAllLocalData
        ) {
            Button("Delete and Verify", role: .destructive) {
                model.session.resetAllLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "This closes active local workspaces, deletes every owner-only data location in the reset ledger, and destroys the recovery encryption key. This cannot be undone."
            )
        }
    }
}

private struct DiagnosticCheckRow: View {
    let check: DiagnosticCheck
    let remediate: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(statusLabel, systemImage: statusSymbol)
                .labelStyle(.iconOnly)
                .foregroundStyle(statusColor)
                .accessibilityLabel(statusLabel)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(check.title))
                Text(verbatim: check.value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            if let remediation = check.remediation {
                Button(action: remediate) {
                    Text(LocalizedStringKey(remediation.label))
                }
            } else {
                Text(statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var statusLabel: LocalizedStringKey {
        switch check.status {
        case .ready: "Ready"
        case .attention: "Needs attention"
        case .unavailable: "Unavailable"
        case .informational: "Information"
        }
    }

    private var statusSymbol: String {
        switch check.status {
        case .ready: "checkmark.circle.fill"
        case .attention: "exclamationmark.circle"
        case .unavailable: "xmark.octagon.fill"
        case .informational: "info.circle"
        }
    }

    private var statusColor: Color {
        switch check.status {
        case .ready: .green
        case .attention: .orange
        case .unavailable: .red
        case .informational: .secondary
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
