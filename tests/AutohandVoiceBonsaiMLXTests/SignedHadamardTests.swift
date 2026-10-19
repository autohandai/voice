import Foundation
import XCTest
@testable import AutohandVoiceBonsaiMLX
#if arch(arm64)
import MLX
#endif

final class SignedHadamardTests: XCTestCase {
    func testForwardMatchesTheNormalizedSylvesterMatrix() throws {
        // H4 / 2 · S · x with S = diag(1, -1, 1, 1), x = (1, 2, 3, 4):
        // S·x = (1, -2, 3, 4); H4 rows: ++++ +-+- ++-- +--+.
        let y = try SignedHadamard.reference(
            [1, 2, 3, 4],
            signs: [1, -1, 1, 1],
            block: 4,
            inverse: false
        )
        assertClose(y, [3, 1, -4, 2])
    }

    func testTransformIsBlockwiseAndInverseUndoesForward() throws {
        let x: [Float] = [0.5, -1, 2, 7, 3, 3, -4, 0.25]
        let signs: [Float] = [1, -1, -1, 1, 1, 1, -1, 1]
        let forward = try SignedHadamard.reference(x, signs: signs, block: 4, inverse: false)
        // Each block of 4 is transformed independently.
        let firstBlock = try SignedHadamard.reference(
            Array(x[0..<4]), signs: Array(signs[0..<4]), block: 4, inverse: false
        )
        assertClose(Array(forward[0..<4]), firstBlock)
        let back = try SignedHadamard.reference(forward, signs: signs, block: 4, inverse: true)
        assertClose(back, x)
    }

    func testRejectsBlocksThatAreNotPowersOfTwoOrDoNotDivideTheWidth() {
        XCTAssertThrowsError(try SignedHadamard.reference([1, 2, 3], signs: [1, 1, 1], block: 3, inverse: false))
        XCTAssertThrowsError(try SignedHadamard.reference([1, 2, 3, 4, 5, 6], signs: [1, 1, 1, 1, 1, 1], block: 4, inverse: false))
        XCTAssertThrowsError(try SignedHadamard.reference([1, 2], signs: [1], block: 2, inverse: false))
    }

    #if arch(arm64)
    /// MLX aborts the process when it can't find its kernels, so this runs
    /// only when mlx.metallib sits next to the test binary (MLX looks
    /// beside the binary that contains it): link the output of
    /// scripts/build-mlx-metallib.sh into
    /// .build/debug/AutohandVoicePackageTests.xctest/Contents/MacOS/.
    func testMLXTransformMatchesTheReference() throws {
        guard let binary = Bundle(for: Self.self).executableURL,
              FileManager.default.fileExists(
                  atPath: binary.deletingLastPathComponent()
                      .appendingPathComponent("mlx.metallib").path
              )
        else { throw XCTSkip("mlx.metallib is not next to the test binary") }
        let width = 1024
        let block = 512
        var x = [Float](repeating: 0, count: width)
        var signs = [Float](repeating: 1, count: width)
        for i in 0..<width {
            x[i] = Float((i * 37) % 101) / 50 - 1
            signs[i] = (i * 7) % 3 == 0 ? -1 : 1
        }
        let expected = try SignedHadamard.reference(x, signs: signs, block: block, inverse: false)
        let actual = Device.withDefaultDevice(.cpu) {
            SignedHadamard(blockSize: block)
                .forward(MLXArray(x).reshaped(1, 1, width), signs: MLXArray(signs))
                .asArray(Float.self)
        }
        assertClose(actual, expected, accuracy: 1e-4)
        let inverse = Device.withDefaultDevice(.cpu) {
            SignedHadamard(blockSize: block)
                .inverse(MLXArray(expected), signs: MLXArray(signs))
                .asArray(Float.self)
        }
        assertClose(inverse, x, accuracy: 1e-4)
    }
    #endif

    private func assertClose(
        _ actual: [Float],
        _ expected: [Float],
        accuracy: Float = 1e-5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertEqual(a, e, accuracy: accuracy, file: file, line: line)
        }
    }
}
