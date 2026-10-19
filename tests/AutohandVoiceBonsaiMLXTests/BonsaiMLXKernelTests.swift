#if arch(arm64)
import Foundation
import MLX
import XCTest
@testable import AutohandVoiceBonsaiMLX

/// GPU paths pinned against their plain references. MLX aborts the process
/// without its kernels, so these run only when mlx.metallib sits next to
/// the test binary (see SignedHadamardTests).
final class BonsaiMLXKernelTests: XCTestCase {
    override func setUpWithError() throws {
        guard let binary = Bundle(for: Self.self).executableURL,
              FileManager.default.fileExists(
                  atPath: binary.deletingLastPathComponent()
                      .appendingPathComponent("mlx.metallib").path
              )
        else { throw XCTSkip("mlx.metallib is not next to the test binary") }
    }

    func testGatedDeltaKernelMatchesTheOpsRecurrence() {
        MLXRandom.seed(11)
        let (B, T, Hk, Hv, Dk, Dv) = (1, 5, 2, 4, 64, 32)
        let q = MLXRandom.normal([B, T, Hk, Dk]) * 0.1
        let k = MLXRandom.normal([B, T, Hk, Dk]) * 0.1
        let v = MLXRandom.normal([B, T, Hv, Dv])
        let a = MLXRandom.normal([B, T, Hv])
        let b = MLXRandom.normal([B, T, Hv])
        let aLog = MLXRandom.normal([Hv]) * 0.5
        let dtBias = MLXRandom.normal([Hv]) * 0.1
        let state = MLXRandom.normal([B, Hv, Dv, Dk]) * 0.1
        let (kernelY, kernelState) = gatedDeltaUpdate(
            q: q, k: k, v: v, a: a, b: b, aLog: aLog, dtBias: dtBias,
            state: state, useKernel: true
        )
        let (opsY, opsState) = gatedDeltaUpdate(
            q: q, k: k, v: v, a: a, b: b, aLog: aLog, dtBias: dtBias,
            state: state, useKernel: false
        )
        XCTAssertEqual(kernelY.shape, [B, T, Hv, Dv])
        XCTAssertLessThan(abs(kernelY - opsY).max().item(Float.self), 1e-4)
        XCTAssertLessThan(abs(kernelState - opsState).max().item(Float.self), 1e-4)
    }

    func testGPUSamplerAgreesWithTheReferenceWhenDeterministic() {
        var settings = BonsaiSamplingSettings.greedy
        settings.presencePenalty = 1.5
        settings.topK = 4
        let logits: [Float] = [0.1, 3, 2.9, -1, 2.0, 0.5]
        var gpu = BonsaiGPUSampler(settings: settings, seed: 1)
        var cpu = BonsaiSampler(settings: settings, seed: 1)
        var history: [Int] = []
        // Greedy with a presence penalty: repeated picks rotate as each
        // chosen token gets penalised.
        for _ in 0..<4 {
            let fromGPU = Int(gpu.sample(MLXArray(logits)).item(Int32.self))
            let fromCPU = cpu.sample(
                logits.enumerated().map { .init(id: $0.offset, logit: $0.element) },
                recentTokens: history
            )
            XCTAssertEqual(fromGPU, fromCPU)
            history.append(fromCPU)
        }
        XCTAssertEqual(history, [1, 2, 4, 1])
    }

    func testGPUSamplerTopPAndTopKKeepTheNucleus() {
        let settings = BonsaiSamplingSettings(
            temperature: 1, topP: 0.5, topK: 2, presencePenalty: 0, penaltyWindow: 64
        )
        var sampler = BonsaiGPUSampler(settings: settings, seed: 5)
        for _ in 0..<50 {
            let token = Int(sampler.sample(MLXArray([Float](arrayLiteral: 0, 5, 1, 4.9))).item(Int32.self))
            XCTAssertTrue([1, 3].contains(token))
        }
        // Top-p 0.5 over a dominant token always keeps just that token.
        for _ in 0..<50 {
            let token = Int(sampler.sample(MLXArray([Float](arrayLiteral: 0, 9, 1, 2))).item(Int32.self))
            XCTAssertEqual(token, 1)
        }
    }
}
#endif
