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
    @ObservationIgnored private let vault = KeychainAccountCredentialVault(
        service: Brand.bundleIdentifier + ".autohand-api-key",
        account: "talk"
    )
    @ObservationIgnored private var cachedToken: String?
    @ObservationIgnored private var signInTask: Task<Void, Never>?

    private static let emailDefaultsKey = "autohandAccountEmail"
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
        do {
            if let credential = try vault.load() {
                cachedToken = credential.accessToken
                status = .signedIn(
                    email: UserDefaults.standard.string(
                        forKey: Self.emailDefaultsKey
                    )
                )
            }
        } catch {
            Self.logger.error(
                "Autohand credential could not be read: \(error.localizedDescription)"
            )
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    var token: String? { cachedToken }

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
        cachedToken = nil
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
        cachedToken = token
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
