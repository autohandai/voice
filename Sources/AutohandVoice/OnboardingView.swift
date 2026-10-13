import AutohandVoiceCore
import SwiftUI

private enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome
    case howItWorks
    case privacy
    case setup
    case test

    var id: Self { self }

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .howItWorks: "How It Works"
        case .privacy: "Privacy"
        case .setup: "Setup"
        case .test: "Try Dictation"
        }
    }
}

struct OnboardingView: View {
    @Bindable var model: AppSettingsModel
    let onComplete: () -> Void

    @State private var page: OnboardingPage = .welcome
    @State private var dictationTestPassed = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                switch page {
                case .welcome:
                    OnboardingWelcomeStep()
                case .howItWorks:
                    OnboardingHowItWorksStep(
                        primaryActivation: model.session.preferences
                            .primaryActivationMethod,
                        fallbackShortcut: model.session.preferences.shortcut
                    )
                case .privacy:
                    OnboardingPrivacyStep()
                case .setup:
                    OnboardingSetupStep(model: model)
                case .test:
                    OnboardingDictationTestStep(
                        model: model,
                        passed: $dictationTestPassed
                    )
                }
            }
            .id(page)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(
                .asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                )
            )

            footer
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(.background)
        .animation(.easeInOut(duration: 0.22), value: page)
        .onAppear {
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AutohandBrandMark()

            VStack(alignment: .leading, spacing: 1) {
                Text("AUTOHAND")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .tracking(1.2)
                Text("VOICE")
                    .font(.system(.caption2, design: .monospaced).weight(.medium))
                    .tracking(2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Step \(page.rawValue + 1) of \(OnboardingPage.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    "\(page.title), step \(page.rawValue + 1) of \(OnboardingPage.allCases.count)"
                )
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    private var footer: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                ForEach(OnboardingPage.allCases) { item in
                    Capsule()
                        .fill(
                            item.rawValue <= page.rawValue
                                ? Color.accentColor
                                : Color.secondary.opacity(0.22)
                        )
                        .frame(
                            width: item == page ? 28 : 8,
                            height: 5
                        )
                        .animation(.spring(response: 0.28), value: page)
                        .accessibilityHidden(true)
                }
            }

            HStack {
                if page != .welcome {
                    Button("Back") {
                        move(by: -1)
                    }
                }

                Spacer()

                if page == .test {
                    Button("Finish Setup") {
                        onComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!readiness.canComplete)
                } else {
                    Button("Continue") {
                        move(by: 1)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(page == .setup && !readiness.canTestDictation)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
    }

    private var readiness: OnboardingReadiness {
        OnboardingReadiness(
            microphoneAuthorized:
                model.systemCheck.microphonePermission == "authorized",
            accessibilityAuthorized:
                model.systemCheck.accessibilityPermission,
            modelReady: model.session.modelState == .ready,
            dictationTestPassed: dictationTestPassed
        )
    }

    private func move(by offset: Int) {
        guard let next = OnboardingPage(
            rawValue: page.rawValue + offset
        ) else {
            return
        }
        page = next
    }
}

private struct OnboardingWelcomeStep: View {
    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: 18) {
                Text("Your voice. Your Mac. Your words.")
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Autohand Voice turns speech into polished text anywhere on macOS, using private models that run on your Mac."
                )
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 30) {
                    OnboardingFeature(
                        symbol: "waveform",
                        title: "Speak naturally",
                        detail: "A live HUD shows microphone activity."
                    )
                    OnboardingFeature(
                        symbol: "text.cursor",
                        title: "Works at your cursor",
                        detail: "Only final text is inserted."
                    )
                    OnboardingFeature(
                        symbol: "lock.shield",
                        title: "Local by default",
                        detail: "No remote speech fallback."
                    )
                }
                .padding(.top, 12)
            }
        } footer: {
            HStack(spacing: 16) {
                Link("Autohand AI", destination: Brand.websiteURL)
                Link("Company", destination: Brand.companyURL)
                Link("Brand", destination: Brand.brandURL)
            }
            .font(.caption)
        }
    }
}

private struct OnboardingHowItWorksStep: View {
    let primaryActivation: VoiceActivationMethod
    let fallbackShortcut: RegisteredShortcut

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingTitle(
                    "Dictation without changing how you work",
                    subtitle:
                        "Keep using the apps you already know. Autohand Voice stays in the menu bar."
                )

                OnboardingExplanation(
                    number: 1,
                    title: "Place your cursor",
                    detail: "Click any editable text field in a macOS app."
                )
                OnboardingExplanation(
                    number: 2,
                    title: "Start speaking",
                    detail: startSpeakingDetail
                )
                OnboardingExplanation(
                    number: 3,
                    title: "Watch the live HUD",
                    detail:
                        "The waveform confirms your microphone is active. Preview words are provisional."
                )
                OnboardingExplanation(
                    number: 4,
                    title: "Finish",
                    detail:
                        "Autohand Voice creates the final transcript locally and inserts it at the original cursor."
                )
            }
        }
    }

    private var startSpeakingDetail: String {
        switch primaryActivation {
        case .functionKeyLongPress:
            "Hold Fn for 0.4 seconds while you speak, then release to finish. \(fallbackShortcut.displayName) remains available as a fallback."
        case let .keyboard(shortcut):
            "Use \(shortcut.displayName), or choose Start Recording from the menu bar."
        }
    }
}

private struct OnboardingPrivacyStep: View {
    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: 22) {
                OnboardingTitle(
                    "Private by design",
                    subtitle:
                        "Speech recognition runs locally with CoreML on Apple Silicon."
                )

                PrivacyPromise(
                    symbol: "icloud.slash",
                    title: "No remote fallback",
                    detail:
                        "Audio and transcripts are never silently sent to a speech or cleanup service."
                )
                PrivacyPromise(
                    symbol: "memorychip",
                    title: "Audio stays in memory",
                    detail:
                        "Recordings are not saved to disk. A failed dictation can remain in a bounded 15-minute in-memory recovery buffer."
                )
                PrivacyPromise(
                    symbol: "cursorarrow.rays",
                    title: "Accessibility has one job",
                    detail:
                        "It captures the focused target and inserts only the verified final transcript."
                )
                PrivacyPromise(
                    symbol: "text.badge.checkmark",
                    title: "Provisional text is never committed",
                    detail:
                        "Live preview can change while you speak; only final recognition reaches the field."
                )
            }
        } footer: {
            Link(
                "Read the Autohand Privacy Policy",
                destination: Brand.privacyPolicyURL
            )
            .font(.callout)
        }
    }
}

private struct OnboardingSetupStep: View {
    @Bindable var model: AppSettingsModel

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: 20) {
                OnboardingTitle(
                    "Prepare this Mac",
                    subtitle:
                        "All three checks must pass before the dictation test."
                )

                OnboardingRequirementRow(
                    title: "Microphone",
                    detail: "Captures your speech for local recognition.",
                    isComplete:
                        model.systemCheck.microphonePermission == "authorized",
                    buttonTitle:
                        model.systemCheck.microphonePermission == "not-determined"
                            ? "Allow"
                            : "Open Settings"
                ) {
                    if model.systemCheck.microphonePermission == "not-determined" {
                        Task { await model.requestMicrophonePermission() }
                    } else {
                        model.openMicrophoneSettings()
                    }
                }

                OnboardingRequirementRow(
                    title: "Accessibility",
                    detail: "Inserts final text into the focused field.",
                    isComplete: model.systemCheck.accessibilityPermission,
                    buttonTitle: "Allow"
                ) {
                    model.requestAccessibilityPermission()
                }

                OnboardingRequirementRow(
                    title: "Local speech model",
                    detail: model.session.modelStatusLabel,
                    isComplete: model.session.modelState == .ready,
                    buttonTitle: "Prepare"
                ) {
                    model.session.prepareLocalModel()
                }

                if model.session.showsModelPreparationProgress {
                    ProgressView(value: model.session.modelProgress)
                        .accessibilityLabel("Local model preparation")
                }

                HStack {
                    Button("Check Again") {
                        model.refresh()
                    }
                    Spacer()
                    Text("Nothing is uploaded during setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = model.actionMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Status: \(message)")
                }
            }
        }
    }
}

private struct OnboardingDictationTestStep: View {
    @Bindable var model: AppSettingsModel
    @Binding var passed: Bool

    @FocusState private var testFieldFocused: Bool
    @State private var testText = ""
    @State private var didStartTest = false
    @State private var transcriptBeforeTest: String?

    var body: some View {
        OnboardingStepLayout {
            VStack(alignment: .leading, spacing: 18) {
                OnboardingTitle(
                    passed ? "Dictation works" : "Try your first dictation",
                    subtitle: passed
                        ? "Your microphone, local model, activation, and text insertion are ready."
                        : "Say “Autohand Voice is ready” and finish the recording."
                )

                TextField(
                    "Your dictated text will appear here",
                    text: $testText,
                    axis: .vertical
                )
                .focused($testFieldFocused)
                .lineLimit(3...5)
                .font(.title3)
                .padding(14)
                .background(.quaternary.opacity(0.5))
                .clipShape(.rect(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            testFieldFocused
                                ? Color.accentColor
                                : Color.secondary.opacity(0.2),
                            lineWidth: 1
                        )
                }
                .accessibilityHint(
                    "Autohand Voice will insert the final test transcript here."
                )

                HStack(spacing: 12) {
                    Button(testButtonTitle) {
                        toggleTest()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        model.session.state == .processing
                            || passed
                            || (
                                model.session.hasRecoverableAudio
                                    && !model.session.isRecordingOrStarting
                            )
                    )

                    if model.session.state == .processing {
                        ProgressView()
                            .controlSize(.small)
                        Text("Creating the final transcript locally…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else if passed {
                        Label(
                            "End-to-end test passed",
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(.green)
                    } else {
                        Text(alternativeActivationText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                if case let .failed(message) = model.session.state {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                if model.session.hasRecoverableAudio,
                   model.session.state != .processing {
                    HStack(spacing: 12) {
                        Button("Retry Last Recording") {
                            testFieldFocused = true
                            DispatchQueue.main.asyncAfter(
                                deadline: .now() + 0.18
                            ) {
                                model.session.retryRecoverableAudio()
                            }
                        }
                        Button("Discard Recording") {
                            model.session.discardRecoverableAudio()
                        }
                    }
                    .font(.callout)
                }

                Text(
                    "This test uses the same path as every dictation: microphone → local CoreML model → verified final text → focused field."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.session.lastTranscript) { oldValue, newValue in
            guard
                didStartTest,
                newValue != oldValue,
                newValue != transcriptBeforeTest,
                !testText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return
            }
            passed = true
        }
    }

    private var testButtonTitle: String {
        if model.session.isRecordingOrStarting {
            return "Stop & Transcribe"
        }
        return didStartTest ? "Try Again" : "Start Dictation Test"
    }

    private var alternativeActivationText: String {
        switch model.session.preferences.primaryActivationMethod {
        case .functionKeyLongPress:
            "Hold Fn for 0.4 seconds, speak, then release. \(model.session.preferences.shortcut.displayName) is the fallback."
        case let .keyboard(shortcut):
            "You can also use \(shortcut.displayName)."
        }
    }

    private func toggleTest() {
        if model.session.isRecordingOrStarting {
            model.session.finishRecording()
            return
        }

        didStartTest = true
        transcriptBeforeTest = model.session.lastTranscript
        testText = ""
        testFieldFocused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            model.session.beginRecording(origin: .onboarding)
            }
        }
    }

private struct OnboardingStepLayout<
    Content: View,
    Footer: View
>: View {
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            content
            Spacer(minLength: 8)
            footer
        }
        .frame(maxWidth: 660, alignment: .leading)
        .padding(.horizontal, 52)
        .padding(.vertical, 24)
    }
}

private extension OnboardingStepLayout where Footer == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content) {
            EmptyView()
        }
    }
}

private struct OnboardingTitle: View {
    let title: String
    let subtitle: String

    init(_ title: String, subtitle: String) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold))
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingExplanation: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Text("\(number)")
                .font(.system(.callout, design: .rounded).weight(.bold))
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.14), in: Circle())
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct PrivacyPromise: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 15) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OnboardingRequirementRow: View {
    let title: String
    let detail: String
    let isComplete: Bool
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(
                systemName: isComplete
                    ? "checkmark.circle.fill"
                    : "circle.dashed"
            )
            .font(.title2)
            .foregroundStyle(isComplete ? .green : .secondary)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isComplete {
                Text("Ready")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(title): ready")
            } else {
                Button(buttonTitle, action: action)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct AutohandBrandMark: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let orbits: [Orbit] = [
        .init(id: 0, duration: 2.0, clockwise: true),
        .init(id: 1, duration: 2.5, clockwise: false),
        .init(id: 2, duration: 3.0, clockwise: true),
        .init(id: 3, duration: 1.8, clockwise: false),
        .init(id: 4, duration: 2.2, clockwise: false),
        .init(id: 5, duration: 2.8, clockwise: true),
        .init(id: 6, duration: 2.6, clockwise: false),
        .init(id: 7, duration: 1.9, clockwise: true),
    ]

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 30.0,
                paused: reduceMotion
            )
        ) { timeline in
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.fixed(12), spacing: 4),
                    count: 4
                ),
                spacing: 7
            ) {
                ForEach(Self.orbits) { orbit in
                    ZStack {
                        Circle()
                            .stroke(lineWidth: 1.4)
                        Circle()
                            .fill()
                            .frame(width: 2.4, height: 2.4)
                            .offset(y: -6)
                    }
                    .frame(width: 12, height: 12)
                    .rotationEffect(
                        .degrees(
                            reduceMotion
                                ? 0
                                : orbit.angle(at: timeline.date)
                        )
                    )
                }
            }
        }
        .frame(width: 60, height: 34)
        .accessibilityHidden(true)
    }

    private struct Orbit: Identifiable {
        let id: Int
        let duration: TimeInterval
        let clockwise: Bool

        func angle(at date: Date) -> Double {
            let progress =
                date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: duration)
                / duration
            return progress * 360 * (clockwise ? 1 : -1)
        }
    }
}
