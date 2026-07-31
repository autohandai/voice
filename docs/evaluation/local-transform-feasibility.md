# Local Transform feasibility and release boundary

Status: artifact-blocked; capability remains off by default.

Autohand Voice may expose High cleanup, Polish, Prompt Builder, custom
templates, or automatic per-app transforms only after a separately licensed
CoreML text model is signed, installed, and validated on supported Apple
Silicon Macs. The runtime contract is local-only and permits no network,
heuristic, or alternate-engine fallback.

The signed manifest binds the model version, SHA-256 checksum, exact byte
count, license identifier, supported languages, input/output limits, and the
Apple Neural Engine requirement. A compiled `.mlmodelc` directory is hashed as
a deterministic tree: sorted relative paths, file lengths, and file bytes.
Symlinks are rejected and total bytes are bounded. A failed signature,
checksum, language, memory, cancellation, secure-target, or output validation
returns the input unchanged.

Before enabling `AUTOHAND_VOICE_LOCAL_TRANSFORMS`, release evidence must
include:

1. Model license and redistribution approval.
2. Signed `.mlmodelc` artifact and pinned signer key rotation procedure.
3. Peak memory, first-run compile, warm latency, and cancellation results on
   every supported Mac class.
4. Network-disabled and network-traffic audits.
5. Golden semantic-preservation fixtures for each enabled language.
6. Selection, focus-token, Undo, secure-field, and exact app-policy smoke.
7. Model absence, checksum corruption, out-of-memory, and unsupported-language
   proof that the original input remains untouched.

No model artifact or signing key is committed in this repository.
