import AutohandVoiceCore
import Observation
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case gettingStarted
    case general
    case permissions
    case privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .general: "General"
        case .permissions: "Permissions"
        case .privacy: "Privacy & Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .gettingStarted: "checklist"
        case .general: "gearshape"
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
        case .permissions:
            PermissionCenterView(model: model)
        case .privacy:
            PrivacyDiagnosticsView(model: model)
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

                    LabeledContent(
                        "Push-to-Talk",
                        value: model.session.preferences.pushToTalkKey.displayName
                    )

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
                    LabeledContent(
                        "Local Model",
                        value: model.session.modelState.label
                    )
                    LabeledContent(
                        "Model Version",
                        value: model.session.preferences.modelVersion
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
