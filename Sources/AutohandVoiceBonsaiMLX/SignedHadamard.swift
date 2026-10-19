import Foundation
#if arch(arm64)
import MLX
#endif

/// The blockwise signed Walsh–Hadamard rotation `R = H·S/√n` that the
/// Bonsai MLX pack folds into its packed weights (`hadamard.json`:
/// "normalized-sylvester-walsh-hadamard" over the input's last axis, block
/// 512, explicit ±1 signs). A packed linear layer computes `W·(R·x)`; the
/// embedding table stores rows in the rotated basis, so lookups apply
/// `Rᵀ = S·H/√n`. Both run in float32 and return the input's dtype, like
/// the pack's reference runtime (`runtime/runtime.py`, `fwht`).
public struct SignedHadamard: Sendable, Equatable {
    public enum Failure: Error, Equatable {
        case invalidBlock(block: Int, width: Int)
        case signCount(expected: Int, actual: Int)
    }

    public let blockSize: Int

    public init(blockSize: Int) {
        precondition(Self.isValidBlockSize(blockSize), "blockSize must be a power of two")
        self.blockSize = blockSize
    }

    public static func isValidBlockSize(_ block: Int) -> Bool {
        block > 1 && block & (block - 1) == 0
    }

    /// Plain-Swift reference (fast Walsh–Hadamard butterflies, Sylvester
    /// order). Used by tests to pin the MLX transform.
    public static func reference(
        _ x: [Float],
        signs: [Float],
        block: Int,
        inverse: Bool
    ) throws -> [Float] {
        guard isValidBlockSize(block), x.count % block == 0, !x.isEmpty else {
            throw Failure.invalidBlock(block: block, width: x.count)
        }
        guard signs.count == x.count else {
            throw Failure.signCount(expected: x.count, actual: signs.count)
        }
        var values = inverse ? x : zip(x, signs).map(*)
        let scale = 1 / Float(block).squareRoot()
        for start in stride(from: 0, to: values.count, by: block) {
            var half = 1
            while half < block {
                for i in stride(from: start, to: start + block, by: 2 * half) {
                    for j in i..<(i + half) {
                        let a = values[j]
                        let b = values[j + half]
                        values[j] = a + b
                        values[j + half] = a - b
                    }
                }
                half *= 2
            }
        }
        values = values.map { $0 * scale }
        return inverse ? zip(values, signs).map(*) : values
    }
}

#if arch(arm64)
extension SignedHadamard {
    /// `R·x` along the last axis: flip signs, then transform each block.
    func forward(_ x: MLXArray, signs: MLXArray) -> MLXArray {
        transform(x.asType(.float32) * signs).asType(x.dtype)
    }

    /// `Rᵀ·x` along the last axis: transform each block, then flip signs.
    func inverse(_ x: MLXArray, signs: MLXArray) -> MLXArray {
        (transform(x.asType(.float32)) * signs).asType(x.dtype)
    }

    private func transform(_ x: MLXArray) -> MLXArray {
        let shape = x.shape
        return hadamardTransform(
            x.reshaped(-1, blockSize),
            scale: 1 / Float(blockSize).squareRoot()
        ).reshaped(shape)
    }
}
#endif
