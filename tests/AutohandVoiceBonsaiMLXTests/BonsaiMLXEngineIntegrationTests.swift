#if arch(arm64)
import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation
import Metal
import XCTest
@testable import AutohandVoiceBonsaiMLX

/// Runs the real model when it is installed and the MLX kernels sit next
/// to the test binary; skipped otherwise (CI, Intel, fresh checkouts).
final class BonsaiMLXEngineIntegrationTests: XCTestCase {
    private func engine(sampling: BonsaiSamplingSettings = .greedy) throws -> BonsaiMLXEngine {
        guard let binary = Bundle(for: Self.self).executableURL else {
            throw XCTSkip("no test binary")
        }
        let metallib = binary.deletingLastPathComponent().appendingPathComponent("mlx.metallib")
        guard FileManager.default.fileExists(atPath: metallib.path) else {
            throw XCTSkip("mlx.metallib is not next to the test binary")
        }
        let environment = BonsaiMLXEnvironment.make(
            architecture: .arm64,
            hasAppleGPU: MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) == true,
            metalLibraryURL: metallib
        )
        let engine = BonsaiMLXEngine(environment: environment, sampling: sampling)
        guard environment.isSupported, engine.isInstalled else {
            throw XCTSkip("the Bonsai MLX model is not installed")
        }
        return engine
    }

    private let messages = [
        TalkMessage(role: .system, content: FantailChatRequest.spokenSystemPrompt),
        TalkMessage(role: .user, content: "Why is the sky blue?"),
    ]

    func testGreedyReplyIsCoherentAndCancellationLeavesTheModelUsable() async throws {
        let engine = try engine()
        try await engine.prepare { _ in }
        XCTAssertTrue(engine.isLoaded)

        // Stop after a few pieces; the runtime must stop and stay usable.
        var pieces = 0
        for try await _ in engine.reply(to: messages, maxTokens: 200) {
            pieces += 1
            if pieces == 3 { break }
        }
        XCTAssertEqual(pieces, 3)

        var reply = ""
        for try await piece in engine.reply(to: messages, maxTokens: 40) {
            reply += piece
        }
        // Same greedy output llama.cpp produces from the GGUF build.
        XCTAssertTrue(
            reply.hasPrefix("The sky is blue because of a phenomenon called Rayleigh scattering."),
            reply
        )
        XCTAssertFalse(reply.contains("<think>"))
        engine.unload()
    }
}
#endif
