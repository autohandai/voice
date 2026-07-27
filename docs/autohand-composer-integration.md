# Autohand Composer Integration

This document defines the boundary between Autohand Code and Autohand Voice on
macOS Apple Silicon. It is a release contract, not a claim that the streaming
service is implemented in `0.1.0`.

## Activation

When the user presses the voice shortcut, Autohand Code must:

1. Preserve the current composer value, selection, and cursor position.
2. Check that the Mac is Apple Silicon and that `autohand-voice` is available.
3. Show a one-time installation prompt when the runtime is missing.
4. Start the local service and request microphone permission through macOS.
5. Begin rendering audio levels and provisional text in the composer.

Declining installation leaves the composer unchanged. Autohand Code must not
install software or download a model without explicit user consent.

## Engine order

The default engine order is:

1. CoreML Parakeet on the Apple Neural Engine.
2. Qwen3-ASR through MLX when explicitly selected or when its language coverage
   is required and the optional extra is installed.
3. Apple Speech as the operating-system fallback when the model service is
   unavailable.

There is no automatic cloud fallback. Remote cleanup remains opt-in through the
documented privacy boundary.

## Streaming protocol

The service will communicate over newline-delimited JSON. Standard output is
reserved for protocol events; diagnostics belong on standard error.

Client commands:

```json
{"type":"start","requestId":"01","language":"auto"}
{"type":"stop","requestId":"01"}
{"type":"cancel","requestId":"01"}
```

Service events:

```json
{"type":"ready","engine":"ane","model":"parakeet"}
{"type":"level","requestId":"01","rms":0.24}
{"type":"partial","requestId":"01","revision":3,"text":"draft words"}
{"type":"final","requestId":"01","text":"Final words."}
{"type":"error","requestId":"01","code":"microphone_permission_denied","recoverable":true}
```

Every request has one terminal `final`, `cancelled`, or `error` event. Revisions
must increase monotonically. Buffers and event payloads must be bounded.

## Composer behavior

- Audio levels drive the floating voice spectrum and never mutate text.
- Partial transcripts are ghost text and are replaceable by later revisions.
- User typing remains editable while recognition is active.
- Final text is inserted once at the preserved selection or current cursor,
  according to the composer interaction policy.
- Cancel, permission failure, service exit, and model failure remove provisional
  text without removing user-authored text.
- A stale event from an earlier request ID must never update the composer.

## Release gate

The integration is ready only after automated protocol tests and a real
Apple Silicon PTY/TUI smoke test prove shortcut activation, permission handling,
level rendering, concurrent typing, final insertion, cancellation, and Apple
Speech fallback.
