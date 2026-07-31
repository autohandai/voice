# Connected capabilities release gate

Status: externally blocked; account and encrypted-sync UI remain unavailable.

Autohand Voice contains native, local contracts for optional encrypted sync
and account capability injection. They do not constitute a released connected
service. All sync data classes default off, audio is not a sync data class,
and the client performs zero transport calls while the policy is off.

When explicitly configured by a separately reviewed first-party integration,
the client encrypts each bounded object with AES-GCM and authenticates its
identity, class, version, key ID, tombstone state, and payload. A bounded key
ring supports rotation while retaining old read keys. Concurrent versions are
retained as two conflict branches. Transport, key, corruption, quota, and
revocation failures leave local data available.

The account integration contract includes S256 PKCE, cryptographic state and
nonce values, exact callback-origin/path validation, per-user
ThisDeviceOnly Keychain credentials, finite member/admin capabilities, a hard
no-private-content admin boundary, verified-BAA policy enforcement, and
separate local-data confirmation during sign-out. These are native integration
seams, not evidence that a control plane exists. The repository provides no
remote speech, cleanup, fallback recognizer, or account web runtime.

The following evidence is required before either UI can be enabled:

1. A reviewed authenticated control-plane and key lifecycle contract.
2. A second first-party client with connect, disconnect, retry, conflict,
   revocation, reset, and deletion interoperability proof.
3. Packet captures showing opaque authenticated payloads, no audio, and zero
   traffic when every sync class is off.
4. Credential expiry, device revocation, key loss, ciphertext corruption,
   offline queue, quota, and server-unavailability evidence.
5. Legal and security approval for data handling, deletion, privacy copy, and
   incident response.
6. Billing, receipt, entitlement, email, and restore evidence before account
   UI is exposed.

`ConnectedReleaseEvidence` deliberately fails closed until the relevant
external gates are all true. No environment flag may substitute for that
evidence.
