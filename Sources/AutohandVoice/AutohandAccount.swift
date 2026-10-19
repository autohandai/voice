import AppKit
import AutohandVoiceCore
import Foundation
import Observation
import OSLog

/// The optional Autohand account used by Talk. Sign-in uses the same browser
/// device flow as the Autohand CLI; the resulting API key lives in Keychain.
@MainActor
@Observable
final class AutohandAccount {
    enum Status: Equatable {
        case signedOut
        case signingIn(userCode: String, verificationURL: URL)
        case signedIn(email: String?)
    }

    private(set) var status: Status = .signedOut {
        didSet { onChange?() }
    }
    private(set) var signInError: String?
    private(set) var quota: TalkQuota?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onSignedIn: (() -> Void)?

    @ObservationIgnored private let endpoints: AutohandEndpoints
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let vault = TalkCredentialVault(
        storage: CredentialStorage.choose(isAdHocSigned: CodeSignature.isAdHoc)
    )
    /// Read from Keychain only when Talk first needs it: reading at launch
    /// makes macOS ask for the login password after each ad-hoc update.
    @ObservationIgnored private var credential: DeferredCredential<String>
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    private static let emailDefaultsKey = "autohandAccountEmail"
    private static let signedInDefaultsKey = "autohandAccountSignedIn"
    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "account"
    )

    init(
        endpoints: AutohandEndpoints = .production,
        urlSession: URLSession = .shared
    ) {
        self.endpoints = endpoints
        self.urlSession = urlSession
        let vault = vault
        credential = DeferredCredential { try vault.load()?.accessToken }
        let defaults = UserDefaults.standard
        // Earlier builds only recorded the email; treat it as signed in too.
        if defaults.bool(forKey: Self.signedInDefaultsKey)
            || defaults.string(forKey: Self.emailDefaultsKey) != nil
        {
            status = .signedIn(
                email: defaults.string(forKey: Self.emailDefaultsKey)
            )
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    /// The API key, read from Keychain the first time it is needed. Returns
    /// nil (and shows signed out) when there is no key or it can't be read.
    func currentToken() -> String? {
        do {
            if let token = try credential.value() { return token }
        } catch {
            Self.logger.error(
                "Autohand credential could not be read: \(error.localizedDescription)"
            )
            signInError = "Autohand Voice couldn't read your sign-in from Keychain. Sign in again to keep talking."
        }
        if isSignedIn {
            UserDefaults.standard.removeObject(forKey: Self.signedInDefaultsKey)
            UserDefaults.standard.removeObject(forKey: Self.emailDefaultsKey)
            status = .signedOut
        }
        return nil
    }

    func signIn() {
        guard signInTask == nil, !isSignedIn else { return }
        signInError = nil
        signInTask = Task { [weak self] in
            await self?.runDeviceSignIn()
            self?.signInTask = nil
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
    }

    /// Reopens the browser page for a sign-in that is already waiting.
    func reopenSignInPage() {
        if case let .signingIn(_, url) = status {
            NSWorkspace.shared.open(url)
        }
    }

    func signOut() {
        signInTask?.cancel()
        do {
            try vault.delete()
        } catch {
            Self.logger.error(
                "Autohand credential could not be removed: \(error.localizedDescription)"
            )
        }
        UserDefaults.standard.removeObject(forKey: Self.emailDefaultsKey)
        UserDefaults.standard.removeObject(forKey: Self.signedInDefaultsKey)
        credential.clear()
        quota = nil
        status = .signedOut
    }

    /// Called when the API rejects the stored key (revoked or invalid).
    func credentialRejected() {
        signOut()
        signInError = "Your Autohand sign-in expired. Sign in again to keep talking."
    }

    func update(quota: TalkQuota) {
        self.quota = quota
    }

    // MARK: - Device flow

    private func runDeviceSignIn() async {
        do {
            let start = try await initiate()
            status = .signingIn(
                userCode: start.userCode,
                verificationURL: start.verificationURL
            )
            NSWorkspace.shared.open(start.verificationURL)
            try await poll(start)
        } catch is CancellationError {
            status = .signedOut
        } catch {
            Self.logger.error(
                "Autohand sign-in failed: \(error.localizedDescription)"
            )
            signInError = "Sign-in didn't complete. Try again."
            status = .signedOut
        }
    }

    private func initiate() async throws -> DeviceSignInStart {
        let (data, response) = try await urlSession.data(
            for: jsonRequest(
                endpoints.deviceInitiate,
                body: DeviceSignInRequest()
            )
        )
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        return try DeviceSignInStart.decode(data)
    }

    private func poll(_ start: DeviceSignInStart) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(start.expiresIn))
        var interval = start.interval
        while Date() < deadline {
            try await Task.sleep(for: .seconds(interval))
            do {
                let (data, response) = try await urlSession.data(
                    for: jsonRequest(
                        endpoints.devicePoll,
                        body: PollBody(deviceCode: start.deviceCode)
                    )
                )
                let http = response as? HTTPURLResponse
                let result = DeviceSignInPoll.decode(
                    status: http?.statusCode ?? 0,
                    body: data,
                    retryAfter: http?.value(forHTTPHeaderField: "Retry-After")
                )
                switch result {
                case let .pending(next):
                    interval = next
                case let .slowDown(retryAfter):
                    interval = max(interval, retryAfter)
                case let .authorized(token, email):
                    try store(token: token, email: email)
                    return
                case .expired:
                    signInError = "The sign-in code expired. Try again."
                    status = .signedOut
                    return
                case .cancelled:
                    signInError = "Sign-in was cancelled in the browser."
                    status = .signedOut
                    return
                case .failed:
                    throw URLError(.badServerResponse)
                }
            } catch is CancellationError {
                await cancelOnServer(start.deviceCode)
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                await cancelOnServer(start.deviceCode)
                throw CancellationError()
            } catch let error as URLError
                where error.code == .notConnectedToInternet
                || error.code == .timedOut
            {
                // Transient network loss: keep polling until the code expires.
                continue
            }
        }
        signInError = "The sign-in code expired. Try again."
        status = .signedOut
    }

    private func store(token: String, email: String?) throws {
        try vault.store(
            AccountCredential(
                accessToken: token,
                refreshToken: nil,
                expiresAt: .distantFuture
            )
        )
        if let email {
            UserDefaults.standard.set(email, forKey: Self.emailDefaultsKey)
        }
        UserDefaults.standard.set(true, forKey: Self.signedInDefaultsKey)
        credential.store(token)
        signInError = nil
        status = .signedIn(email: email)
        onSignedIn?()
    }

    private func cancelOnServer(_ deviceCode: String) async {
        _ = try? await urlSession.data(
            for: jsonRequest(
                endpoints.deviceCancel,
                body: PollBody(deviceCode: deviceCode)
            )
        )
    }

    private struct PollBody: Encodable {
        let deviceCode: String
        let schemaVersion = 2
    }

    private func jsonRequest(
        _ url: URL,
        body: some Encodable
    ) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Brand.productName, forHTTPHeaderField: "x-source")
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

/// Keychain for builds with a stable signature; an owner-only file for
/// ad-hoc builds, which Keychain would challenge after every update.
private struct TalkCredentialVault: Sendable {
    let storage: CredentialStorage
    private let keychain = KeychainAccountCredentialVault(
        service: Brand.bundleIdentifier + ".autohand-api-key",
        account: "talk"
    )
    private let file = FileAccountCredentialVault(
        url: Brand.applicationSupportDirectory
            .appendingPathComponent("talk-credential.json")
    )

    func store(_ credential: AccountCredential) throws {
        switch storage {
        case .keychain: try keychain.store(credential)
        case .ownerOnlyFile: try file.store(credential)
        }
    }

    func load() throws -> AccountCredential? {
        switch storage {
        case .keychain: try keychain.load()
        case .ownerOnlyFile: try file.load()
        }
    }

    func delete() throws {
        switch storage {
        case .keychain: try keychain.delete()
        case .ownerOnlyFile: try file.delete()
        }
    }
}
