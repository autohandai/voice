import AutohandVoiceCore
import Foundation

/// Streams a Fantail reply from the Autohand inference API.
struct FantailClient: Sendable {
    enum Update: Sendable {
        case text(String)
        case quota(TalkQuota)
    }

    private static let maximumErrorBodyBytes = 64 * 1024

    let endpoints: AutohandEndpoints
    let urlSession: URLSession

    init(
        endpoints: AutohandEndpoints = .production,
        urlSession: URLSession = .shared
    ) {
        self.endpoints = endpoints
        self.urlSession = urlSession
    }

    /// Text deltas as they arrive. Fails with a `TalkFailure`, or with
    /// `CancellationError` when the consumer stops listening.
    func reply(
        to request: FantailChatRequest,
        token: String
    ) -> AsyncThrowingStream<Update, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(request, token: token, into: continuation)
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch let failure as TalkFailure {
                    continuation.finish(throwing: failure)
                } catch let error as URLError where error.code == .cancelled {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: TalkFailure.connectionLost)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func stream(
        _ request: FantailChatRequest,
        token: String,
        into continuation: AsyncThrowingStream<Update, Error>.Continuation
    ) async throws {
        var urlRequest = URLRequest(
            url: endpoints.chatCompletions,
            timeoutInterval: 60
        )
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.setValue("desktop", forHTTPHeaderField: "x-autohand-client-type")
        urlRequest.setValue(
            UUID().uuidString.lowercased(),
            forHTTPHeaderField: "x-autohand-client-request-id"
        )
        urlRequest.setValue(Brand.productName, forHTTPHeaderField: "x-source")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await urlSession.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw TalkFailure.unavailable
        }
        guard http.statusCode == 200 else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count >= Self.maximumErrorBodyBytes { break }
            }
            throw AutohandAPIError.failure(
                status: http.statusCode,
                body: body,
                retryAfter: http.value(forHTTPHeaderField: "Retry-After")
            )
        }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) {
            if let key = $1.key as? String, let value = $1.value as? String {
                $0[key] = value
            }
        }
        if let quota = TalkQuota(headers: headers) {
            continuation.yield(.quota(quota))
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            switch FantailStreamParser.parse(line: line) {
            case let .content(text):
                continuation.yield(.text(text))
            case .done:
                return
            case .finished, .ignored:
                continue
            }
        }
    }
}
