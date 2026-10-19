import Foundation
import XCTest
@testable import AutohandVoiceBonsaiMLX

final class BonsaiSamplerTests: XCTestCase {
    private func candidates(_ logits: [Float]) -> [BonsaiSampler.Candidate] {
        logits.enumerated().map { .init(id: $0.offset, logit: $0.element) }
    }

    func testGreedyPicksTheHighestLogit() {
        var sampler = BonsaiSampler(settings: .greedy, seed: 1)
        XCTAssertEqual(sampler.sample(candidates([0.1, 3, 2.9, -1]), recentTokens: []), 1)
    }

    func testPresencePenaltyAppliesOncePerRecentTokenWithinTheWindow() {
        var settings = BonsaiSamplingSettings.greedy
        settings.presencePenalty = 1.5
        settings.penaltyWindow = 2
        var sampler = BonsaiSampler(settings: settings, seed: 1)
        // Token 1 repeated: penalised once (3 - 1.5 = 1.5), so token 2 wins.
        XCTAssertEqual(
            sampler.sample(candidates([0, 3, 2.9]), recentTokens: [1, 1]),
            2
        )
        // Token 1 is outside the 2-token window: not penalised.
        XCTAssertEqual(
            sampler.sample(candidates([0, 3, 2.9]), recentTokens: [1, 0, 0]),
            1
        )
    }

    func testTopKKeepsOnlyTheBestCandidates() {
        let logits: [Float] = [0.5, 9, -2, 7, 8, 1]
        let top = BonsaiSampler.topK(logits, k: 3)
        XCTAssertEqual(top.map(\.id), [1, 4, 3])
        XCTAssertEqual(BonsaiSampler.topK(logits, k: 0).count, logits.count)
        XCTAssertEqual(BonsaiSampler.topK(logits, k: 99).count, logits.count)
    }

    func testTopPDropsTheLongTail() {
        var settings = BonsaiSamplingSettings.greedy
        settings.temperature = 1
        settings.topP = 0.5
        settings.topK = 0
        settings.presencePenalty = 0
        // Token 0 alone holds > 50% of the mass, so it is always chosen.
        var sampler = BonsaiSampler(settings: settings, seed: 7)
        for _ in 0..<200 {
            XCTAssertEqual(sampler.sample(candidates([5, 1, 1, 1]), recentTokens: []), 0)
        }
    }

    func testSeededSamplingIsReproducibleAndCoversTheNucleus() {
        let settings = BonsaiSamplingSettings(
            temperature: 1,
            topP: 1,
            topK: 0,
            presencePenalty: 0,
            penaltyWindow: 64
        )
        var first = BonsaiSampler(settings: settings, seed: 42)
        var second = BonsaiSampler(settings: settings, seed: 42)
        var seen = Set<Int>()
        for _ in 0..<300 {
            let a = first.sample(candidates([1, 1, 1]), recentTokens: [])
            let b = second.sample(candidates([1, 1, 1]), recentTokens: [])
            XCTAssertEqual(a, b)
            seen.insert(a)
        }
        XCTAssertEqual(seen, [0, 1, 2])
    }

    func testLowTemperatureConcentratesOnTheBestToken() {
        let settings = BonsaiSamplingSettings(
            temperature: 0.05,
            topP: 1,
            topK: 0,
            presencePenalty: 0,
            penaltyWindow: 64
        )
        var sampler = BonsaiSampler(settings: settings, seed: 3)
        for _ in 0..<100 {
            XCTAssertEqual(sampler.sample(candidates([2, 1.5, 1]), recentTokens: []), 0)
        }
    }

    func testDefaultsMatchTheLlamaCppTalkSampler() {
        let settings = BonsaiSamplingSettings()
        XCTAssertEqual(settings.temperature, 0.7)
        XCTAssertEqual(settings.topP, 0.8)
        XCTAssertEqual(settings.topK, 20)
        XCTAssertEqual(settings.presencePenalty, 1.5)
        XCTAssertEqual(settings.penaltyWindow, 64)
    }
}
