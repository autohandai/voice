# Local Speech and Refinement Evaluation

These schemas define reproducible, offline evidence for model, recognition, and
deterministic refinement changes. They do not contain a benchmark dataset and
must never be used to commit recordings, transcripts, model caches, usernames,
credentials, or private application context.

The manifest records the licensed dataset identity, immutable checksums,
supported languages, selected local model, and policy configuration. The
report records finite outcome counts, word-error components, refinement
results, and bounded latency buckets. Raw samples remain outside the
repository.

Required rules:

- run on a supported Apple Silicon Mac with networking disabled;
- use `autohand-voice-stt` and the pinned local CoreML model only;
- set `remoteFallbackEnabled` and `marketComparisonClaim` to `false`;
- record failures by finite family, never by arbitrary error message;
- use aggregate results for release decisions and keep per-sample text out of
  the report;
- compare Autohand Voice releases only when both reports use the same manifest
  checksum and evaluation policy.

Schemas:

- `evaluation-manifest.schema.json` — immutable inputs and privacy assertions;
- `evaluation-report.schema.json` — redacted aggregate output.

Release-boundary documents:

- `local-transform-feasibility.md` — signed local CoreML Transform artifact
  requirements and fail-closed behavior;
- `connected-capabilities-gate.md` — external control-plane, second-client,
  privacy, security, revocation, and entitlement evidence required before
  account or encrypted-sync UI can ship.

These artifacts establish an Autohand Voice baseline. They do not establish or
claim parity with a third-party product without separately reproducible,
authorized evidence.
