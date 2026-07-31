# Autohand Voice Release Evidence

Release candidate: `<version or commit>`\
Evidence date: `<YYYY-MM-DD>`\
Owner: `<name>`\
Scope: `<work package, feature flags, and source IDs>`

## Decision

- Status: `ready` / `not ready`
- Flags lifted: `<none or explicit AUTOHAND_VOICE_* keys>`
- Known limitations: `<list or none>`
- Rollback: `<binary, data-schema, and flag rollback path>`

Automated checks, native smoke tests, deployment evidence, and external-service
evidence are separate gates. One category does not substitute for another.

## Automated code proof

| Check | Command or artifact | Result | Evidence |
| --- | --- | --- | --- |
| Source coverage | `./scripts/verify-wispr-plan-coverage.sh` | pending | |
| Focused tests | `<command>` | pending | |
| Full Swift suite | `swift test` | pending | |
| Release executables | `swift build -c release` | pending | |
| Offline diagnostic | `./.build/release/autohand-voice check --json` | pending | |
| Application build | `./scripts/build-app.sh` | pending | |
| Privacy review | `<test or review artifact>` | pending | |

## Real Apple Silicon smoke

Hardware and OS: `<Mac model, chip, macOS version>`\
Signed application: `<path or build identifier>`

| Scenario | Result | Evidence |
| --- | --- | --- |
| Microphone and model validation | pending | |
| Start, stop, cancel, and final-only commit | pending | |
| Focus, selection, clipboard, and cursor preservation | pending | |
| Permission denial and recovery | pending | |
| Menu bar, hot key, HUD, and text insertion | pending | |
| Sleep, wake, route change, quit, and relaunch | pending | |
| Offline operation with network disabled | pending | |

## Deployment and distribution proof

| Gate | Result | Evidence |
| --- | --- | --- |
| Signing and entitlements | not evaluated | |
| Notarization | not evaluated | |
| Update or installer delivery | not evaluated | |
| Rollback artifact available | not evaluated | |

## External-service proof

Use `not applicable` only when the release does not expose the capability.
External success never changes the local CoreML/ANE speech path.

| Capability | Environment | Result | Evidence |
| --- | --- | --- | --- |
| Account and entitlement | `<none/staging/production>` | not evaluated | |
| Encrypted sync | `<none/staging/production>` | not evaluated | |
| Team administration | `<none/staging/production>` | not evaluated | |
| Billing or subscription | `<none/staging/production>` | not evaluated | |
| Incident delivery | `<none/staging/production>` | not evaluated | |

## Source-family traceability

List each in-scope `WF-*` source ID with its acceptance evidence. Run the
coverage verifier before declaring the full 55-family program complete.

| Source ID | Acceptance result | Automated evidence | Native/live evidence |
| --- | --- | --- | --- |
| `<WF-...>` | pending | | |
