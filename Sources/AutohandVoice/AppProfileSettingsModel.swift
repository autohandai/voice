import AppKit
import AutohandVoiceCore
import Observation

struct RunningAppOption: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
@Observable
final class AppProfileSettingsModel {
    private(set) var profiles: [AppProfile] = []
    private(set) var runningApps: [RunningAppOption] = []
    var selectedID: UUID?
    var selectedRunningBundleIdentifier: String?
    var manualName = ""
    var manualBundleIdentifier = ""
    private(set) var message: String?

    @ObservationIgnored private let store: AppProfileStore
    @ObservationIgnored private weak var session: VoiceSession?

    init(
        session: VoiceSession,
        store: AppProfileStore = AppProfileStore()
    ) {
        self.session = session
        self.store = store
        reload()
        refreshRunningApps()
    }

    var selectedProfile: AppProfile? {
        profiles.first { $0.id == selectedID }
    }

    var sessionLabel: String {
        session?.activeProfileLabel ?? "Global"
    }

    func refreshRunningApps() {
        var seen: Set<String> = []
        runningApps = NSWorkspace.shared.runningApplications.compactMap { app in
            guard
                let identifier = app.bundleIdentifier,
                identifier != Brand.bundleIdentifier,
                !identifier.isEmpty,
                seen.insert(identifier).inserted
            else { return nil }
            return RunningAppOption(
                id: identifier,
                name: app.localizedName ?? identifier
            )
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        if selectedRunningBundleIdentifier == nil {
            selectedRunningBundleIdentifier = runningApps.first?.id
        }
    }

    func addRunningApp() {
        guard
            let identifier = selectedRunningBundleIdentifier,
            let app = runningApps.first(where: { $0.id == identifier })
        else {
            message = "Choose a running app."
            return
        }
        add(name: app.name, bundleIdentifier: app.id)
    }

    func addManual() {
        add(name: manualName, bundleIdentifier: manualBundleIdentifier)
        if message?.hasPrefix("Profile added") == true {
            manualName = ""
            manualBundleIdentifier = ""
        }
    }

    func deleteSelected() {
        guard let selectedID else { return }
        let updated = profiles.filter { $0.id != selectedID }
        save(updated, success: "Profile deleted.")
        self.selectedID = updated.first?.id
    }

    func updateSelected(_ transform: (inout AppProfile) -> Void) {
        guard
            let selectedID,
            let index = profiles.firstIndex(where: { $0.id == selectedID })
        else { return }
        var updated = profiles
        transform(&updated[index])
        save(updated, success: "Profile updated.")
    }

    private func add(name: String, bundleIdentifier: String) {
        let profile = AppProfile(
            name: name,
            bundleIdentifier: bundleIdentifier
        )
        var updated = profiles
        updated.append(profile)
        save(updated, success: "Profile added for \(profile.name).")
        if message?.hasPrefix("Profile added") == true {
            selectedID = profile.id
        }
    }

    private func reload() {
        do {
            profiles = try store.load()
            selectedID = profiles.first?.id
            message = nil
            session?.replaceAppProfiles(profiles)
        } catch {
            profiles = []
            message = "Profiles could not be loaded: \(error.localizedDescription)"
        }
    }

    private func save(_ updated: [AppProfile], success: String) {
        do {
            let normalized = updated.map(normalize)
            try store.save(normalized)
            profiles = normalized
            message = success
            session?.replaceAppProfiles(normalized)
        } catch {
            message = "Profiles could not be saved: \(error.localizedDescription)"
        }
    }

    private func normalize(_ profile: AppProfile) -> AppProfile {
        guard let session else { return profile }
        var result = profile
        let globalLanguage = session.preferences.dictationLanguageCode
        let effectiveLanguage = result.dictationLanguageCode
            ?? globalLanguage
        if result.modelVersion == SpeechModelVariant.v2.rawValue,
           effectiveLanguage != SupportedDictationLanguage.english.code {
            result.dictationLanguageCode =
                SupportedDictationLanguage.english.code
        } else if effectiveLanguage
            != SupportedDictationLanguage.english.code {
            let effectiveModel = result.modelVersion
                ?? session.preferences.modelVersion
            if effectiveModel == SpeechModelVariant.v2.rawValue {
                result.modelVersion = SpeechModelVariant.v3.rawValue
            }
        }
        return result
    }
}
