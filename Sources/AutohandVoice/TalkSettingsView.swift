import AutohandVoiceCore
import SwiftUI

/// Settings for Talk: the switch, the optional Autohand account, the voice
/// and what leaves the Mac.
struct TalkSettingsView: View {
    let model: AppSettingsModel

    private var session: VoiceSession { model.session }
    private var account: AutohandAccount { session.talk.account }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Talk with Fantail",
                    isOn: Binding(
                        get: { session.preferences.talkEnabled },
                        set: { session.setTalkEnabled($0) }
                    )
                )
                Text(
                    "Hold Fn and Shift, ask your question, then let go. Fantail answers out loud and on screen. Hold Fn and Shift again to follow up."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "For a hands-free conversation, hold Command and Shift, then press Fn, or set Recording Mode to Hands-Free. Fantail listens again after each reply. Press Esc to end, then copy the conversation."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Autohand Account") {
                accountContent
                if let error = account.signInError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Voice") {
                LabeledContent("Voice") {
                    HStack(spacing: 8) {
                        Text("Heart (English)")
                        if session.talk.isPreparingVoice {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button("Play Sample") {
                            session.talk.playVoiceSample()
                        }
                        .disabled(session.talk.isPreparingVoice)
                    }
                }
                if let notice = session.talk.voiceNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(
                    "Replies are spoken on this Mac with the Kokoro voice model, which downloads the first time you use Talk."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label {
                    Text(
                        "Your audio never leaves this Mac. Talk sends the text of your question and the recent conversation to Autohand to create a reply. Dictation stays fully on this Mac."
                    )
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var accountContent: some View {
        switch account.status {
        case .signedOut:
            Text(
                "Talk needs a free Autohand account. Dictation never does."
            )
            .foregroundStyle(.secondary)
            Button("Sign In with Autohand") {
                account.signIn()
            }
        case let .signingIn(code, _):
            LabeledContent("Sign-in code") {
                Text(code)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }
            Text("Finish signing in in your browser.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Browser") {
                    account.reopenSignInPage()
                }
                Button("Cancel") {
                    account.cancelSignIn()
                }
            }
        case let .signedIn(email):
            LabeledContent("Signed in as") {
                if let email {
                    Text(verbatim: email)
                } else {
                    Text("Autohand account")
                }
            }
            if let remaining = account.quota?.remaining {
                LabeledContent("Talk turns left") {
                    Text(remaining, format: .number)
                }
            }
            Button("Sign Out", role: .destructive) {
                account.signOut()
            }
        }
    }
}
