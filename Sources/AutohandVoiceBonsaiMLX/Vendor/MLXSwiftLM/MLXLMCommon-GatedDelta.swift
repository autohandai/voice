// Ported from github.com/ml-explore/mlx-swift-lm (MIT), PR #630 head
// a3596e4d3c8484a010c811021426d26dff1f365a, Libraries/MLXLMCommon/GatedDelta.swift
// (itself a port of mlx-lm's gated_delta.py). Modified for Autohand Voice;
// see NOTICE.md in this directory.

#if arch(arm64)
import Foundation
import MLX
import MLXNN

// MARK: - Metal kernel

/// One thread group per (batch, value head); 32 SIMD lanes split the key
/// dimension and each `y` row is one value dimension. State stays float32.
private func makeGatedDeltaKernel() -> MLXFast.MLXFastKernel {
    let source = """
            auto n = thread_position_in_grid.z;
            auto b_idx = n / Hv;
            auto hv_idx = n % Hv;
            auto hk_idx = hv_idx / (Hv / Hk);
            constexpr int n_per_t = Dk / 32;

            // q, k: [B, T, Hk, Dk]
            auto q_ = q + b_idx * T * Hk * Dk + hk_idx * Dk;
            auto k_ = k + b_idx * T * Hk * Dk + hk_idx * Dk;

            // v, y: [B, T, Hv, Dv]
            auto v_ = v + b_idx * T * Hv * Dv + hv_idx * Dv;
            y += b_idx * T * Hv * Dv + hv_idx * Dv;

            auto dk_idx = thread_position_in_threadgroup.x;
            auto dv_idx = thread_position_in_grid.y;

            // g, beta: [B, T, Hv]
            auto g_ = g + b_idx * T * Hv;
            auto beta_ = beta + b_idx * T * Hv;

            // state_in, state_out: [B, Hv, Dv, Dk]
            auto i_state = state_in + (n * Dv + dv_idx) * Dk;
            auto o_state = state_out + (n * Dv + dv_idx) * Dk;

            float state[n_per_t];
            for (int i = 0; i < n_per_t; ++i) {
              auto s_idx = n_per_t * dk_idx + i;
              state[i] = static_cast<float>(i_state[s_idx]);
            }

            for (int t = 0; t < T; ++t) {
              float kv_mem = 0.0f;
              {
                // Preserve Kahan summation under Metal's default fast math.
                #pragma clang fp reassociate(off)
                #pragma clang fp contract(off)
                float kv_compensation = 0.0f;
                for (int i = 0; i < n_per_t; ++i) {
                  auto s_idx = n_per_t * dk_idx + i;
                  state[i] = state[i] * g_[hv_idx];
                  auto product = state[i] * k_[s_idx];
                  auto corrected = product - kv_compensation;
                  auto next_sum = kv_mem + corrected;
                  kv_compensation = (next_sum - kv_mem) - corrected;
                  kv_mem = next_sum;
                }
              }
              kv_mem = simd_sum(kv_mem);

              auto delta = (v_[dv_idx] - kv_mem) * beta_[hv_idx];

              float out = 0.0f;
              for (int i = 0; i < n_per_t; ++i) {
                auto s_idx = n_per_t * dk_idx + i;
                state[i] = state[i] + k_[s_idx] * delta;
                out += state[i] * q_[s_idx];
              }
              out = simd_sum(out);
              if (thread_index_in_simdgroup == 0) {
                y[dv_idx] = static_cast<InT>(out);
              }
              // Increment data pointers to next time step
              q_ += Hk * Dk;
              k_ += Hk * Dk;
              v_ += Hv * Dv;
              y += Hv * Dv;
              g_ += Hv;
              beta_ += Hv;
            }
            for (int i = 0; i < n_per_t; ++i) {
              auto s_idx = n_per_t * dk_idx + i;
              o_state[s_idx] = static_cast<StT>(state[i]);
            }
        """

    return MLXFast.metalKernel(
        name: "autohand_bonsai_gated_delta_step",
        inputNames: ["q", "k", "v", "g", "beta", "state_in", "T"],
        outputNames: ["y", "state_out"],
        source: source
    )
}

private let gatedDeltaKernel = makeGatedDeltaKernel()

private func gatedDeltaKernelStep(
    q: MLXArray,
    k: MLXArray,
    v: MLXArray,
    g: MLXArray,
    beta: MLXArray,
    state: MLXArray
) -> (MLXArray, MLXArray) {
    let B = k.dim(0)
    let T = k.dim(1)
    let Hk = k.dim(2)
    let Dk = k.dim(3)
    let Hv = v.dim(2)
    let Dv = v.dim(3)
    let outputs = gatedDeltaKernel(
        [q, k, v, g, beta, state, MLXArray(T)],
        template: [
            ("InT", q.dtype),
            ("StT", state.dtype),
            ("Dk", Dk),
            ("Dv", Dv),
            ("Hk", Hk),
            ("Hv", Hv),
        ],
        grid: (32, Dv, B * Hv),
        threadGroup: (32, 4, 1),
        outputShapes: [[B, T, Hv, Dv], state.shape],
        outputDTypes: [q.dtype, state.dtype]
    )
    return (outputs[0], outputs[1])
}

// MARK: - Ops reference

/// The same recurrence as plain MLX ops, one step at a time. Used when the
/// key head dimension does not fit the kernel's 32-lane split, and by
/// tests to pin the kernel.
func gatedDeltaOps(
    q: MLXArray,
    k: MLXArray,
    v: MLXArray,
    g: MLXArray,
    beta: MLXArray,
    state: MLXArray
) -> (MLXArray, MLXArray) {
    var q = q
    var k = k
    let repeatFactor = v.dim(2) / q.dim(2)
    if repeatFactor > 1 {
        q = repeated(q, count: repeatFactor, axis: -2)
        k = repeated(k, count: repeatFactor, axis: -2)
    }
    var state = state
    var ys: [MLXArray] = []
    ys.reserveCapacity(q.dim(1))
    for t in 0..<q.dim(1) {
        let qt = q[0..., t]
        let kt = k[0..., t]
        let decay = expandedDimensions(g[0..., t], axes: [2, 3])
        state = state * decay
        let kvMem = (state * expandedDimensions(kt, axis: -2)).sum(axis: -1)
        let delta = (v[0..., t] - kvMem) * expandedDimensions(beta[0..., t], axis: -1)
        state = state + expandedDimensions(kt, axis: -2) * expandedDimensions(delta, axis: -1)
        ys.append((state * expandedDimensions(qt, axis: -2)).sum(axis: -1).asType(q.dtype))
    }
    return (stacked(ys, axis: 1), state)
}

// MARK: - Entry point

/// Gated DeltaNet recurrence over `T` steps.
///
/// - q, k: `[B, T, Hk, Dk]` (already L2-normalized and scaled)
/// - v: `[B, T, Hv, Dv]`
/// - a, b: `[B, T, Hv]` raw decay and write-strength projections
/// - state: `[B, Hv, Dv, Dk]` float32, or nil for zeros
///
/// Returns `y: [B, T, Hv, Dv]` and the new float32 state.
func gatedDeltaUpdate(
    q: MLXArray,
    k: MLXArray,
    v: MLXArray,
    a: MLXArray,
    b: MLXArray,
    aLog: MLXArray,
    dtBias: MLXArray,
    state: MLXArray?,
    useKernel: Bool = true
) -> (MLXArray, MLXArray) {
    let beta = sigmoid(b).asType(.float32)
    let g = exp(-exp(aLog.asType(.float32)) * softplus(a + dtBias))
    let B = q.dim(0)
    let Dk = q.dim(3)
    let Hv = v.dim(2)
    let Dv = v.dim(3)
    // fp32 state, as mlx-lm keeps it: half precision compounds rounding
    // error across the recurrence.
    var state = state ?? MLXArray.zeros([B, Hv, Dv, Dk], dtype: .float32)
    if state.dtype != .float32 { state = state.asType(.float32) }
    // The kernel splits Dk over exactly 32 lanes; anything else would drop
    // trailing state dimensions, so it takes the ops path.
    if useKernel, Dk % 32 == 0 {
        return gatedDeltaKernelStep(q: q, k: k, v: v, g: g, beta: beta, state: state)
    }
    return gatedDeltaOps(q: q, k: k, v: v, g: g, beta: beta, state: state)
}
#endif
