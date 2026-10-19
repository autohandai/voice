import AutohandVoiceCore
import Foundation

/// A conversation model that runs on this Mac. Talk uses it instead of
/// Fantail when Settings > Talk > Answered by is set to On this Mac.
@MainActor
protocol LocalTalkModel: AnyObject {
    /// Ready to answer without downloading anything.
    var isReady: Bool { get }
    /// Why it can't run here (for example on an Intel Mac), if it can't.
    var unavailableReason: String? { get }
    /// Starts loading so the first reply doesn't wait for it.
    func prepareInBackground()
    /// Downloads (first use) and loads the model.
    func prepare(
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
    /// Streams the reply text for a conversation.
    func reply(
        to messages: [TalkMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
}
