# Wispr Flow Feature-Parity Plan

Research snapshot: 2026-07-29\
Target: Autohand Voice for macOS 14+ on Apple Silicon

## Purpose

This plan set captures every material capability published on Wispr Flow's
current [What's New](https://wisprflow.ai/whats-new) page, translates it into a
macOS-native Autohand Voice product decision, and defines the architecture,
acceptance evidence, and delivery order needed to implement it.

The 2026-07-29 snapshot contains 55 feature families across nine dated entries
and 19 platform/version cards, from March 31 through July 9, 2026. No older
first-party archive was exposed from the same public surface during research.

"Parity" means matching the user outcome when it fits Autohand Voice. It does
not mean copying another product's implementation, introducing a mobile
keyboard, or weakening the local speech contract. Mobile-only releases are
still captured and receive one of three explicit outcomes:

1. a macOS-native equivalent;
2. an invariant that macOS already owns and Autohand Voice must preserve; or
3. a documented control-plane dependency that cannot live in this native
   runtime.

No source item may disappear merely because it is not directly portable.

## Plan set

| Document | Role |
| --- | --- |
| [`wispr-flow-source-inventory.md`](wispr-flow-source-inventory.md) | Dated first-party evidence inventory and stable source IDs |
| [`wispr-flow-parity-product-spec.md`](wispr-flow-parity-product-spec.md) | Product behavior, UX, requirements, and acceptance criteria |
| [`autohand-voice-parity-architecture.md`](autohand-voice-parity-architecture.md) | Target domain model, deep modules, interfaces, persistence, privacy, and failure contracts |
| [`wispr-flow-parity-delivery-plan.md`](wispr-flow-parity-delivery-plan.md) | Current-state gap ledger, work packages, feature flags, dependency order, and release gates |

## Governing contract

Every feature in this plan is subordinate to the repository contract:

- The shipping runtime is native Swift.
- Speech recognition stays on-device through CoreML on the Apple Neural Engine.
- `autohand-voice-stt` remains the only speech-to-text path.
- No speech, cleanup, or transform silently falls back to a remote service or a
  second engine.
- Provisional transcripts remain view-only; only a final transcript may cross
  the text-commit gate.
- Focus, selection, cursor, existing text, and clipboard state must be
  preserved or the commit must stop with a recoverable error.
- Audio, transcripts, notes, metrics, logs, tasks, caches, and temporary files
  are bounded and have explicit deletion behavior.
- Permission, model, microphone, shortcut, transformation, synchronization,
  and insertion failures are visible and actionable.

Features that require a non-STT model must use an explicit, independently
downloaded local CoreML model. They remain opt-in, disclose the active model,
and fail closed without changing the recognized final transcript.

Optional synchronization is storage, never inference. Its design is
end-to-end encrypted, independently opt-in, and unavailable until a separate
authenticated control plane and a second first-party client exist. Local
dictation must remain fully functional when sync is disabled or unavailable.

## Source-ID convention

The source inventory assigns one stable ID to each changelog feature family:

```text
WF-YYYYMMDD-{DESKTOP|ANDROID|IOS}-NN
```

Material bullets remain acceptance subrequirements beneath the family ID. The
product specification and delivery ledger use the same IDs, making omissions
detectable with a mechanical coverage check.

## Decision labels

| Label | Meaning |
| --- | --- |
| `extend` | A current Autohand Voice capability exists but needs the specified behavior |
| `new` | No current implementation seam provides the user outcome |
| `adapt` | The source behavior is mobile- or cloud-shaped; implement the specified native Mac outcome |
| `preserve` | macOS owns the behavior; Autohand Voice must avoid breaking it and add regression proof |
| `external` | Requires a separately owned account, billing, team, or sync control plane |
| `quality` | A reliability, latency, accuracy, accessibility, or evaluation gate rather than a standalone screen |

None of these labels means "ignore."

## Delivery policy

- New or incomplete user-facing capability is off by default behind an
  explicit `AUTOHAND_VOICE_` feature flag until its release gate passes.
- Data migrations are additive and backward-readable before a flag is enabled.
- Each work package starts with failing XCTest coverage at the module
  interface, then uses focused tests, the full Swift suite, both release
  executables, app packaging, and privacy verification.
- Microphone, keyboard, menu bar, permission, model, notification, pointer, or
  insertion changes also require a real Apple Silicon smoke test.
- External control-plane work cannot be declared complete from mocked native
  tests. It needs authenticated API, offline, revocation, and live delivery
  evidence in its owning repository.

## Definition of complete

This initiative is complete only when:

1. every source ID and material subfeature has a target decision;
2. every `extend`, `new`, `adapt`, `preserve`, and `quality` requirement has
   implementation plus its specified automated and manual evidence;
3. every `external` requirement has a versioned owning contract and live
   integration proof, or the user explicitly removes it from scope;
4. all new persistence is bounded, owner-only, migratable, and erasable;
5. local dictation passes with networking disabled;
6. remote speech/cleanup fallback remains impossible;
7. the required repository validation passes at the final commit; and
8. current-browser, native interaction, deployment, and live-provider evidence
   are reported separately rather than inferred from unit tests.
