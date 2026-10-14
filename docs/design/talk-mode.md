# Talk mode — design

Status: v1 implemented (2026-10-15). v2 and v3 are not built yet.

Talk mode lets you speak to Autohand Voice and hear a spoken reply, as a
dialogue. Dictation is unchanged: hold Fn, text lands at the cursor, fully
local. Talk is a separate, explicit, opt-in feature that sends **text** (never
audio) to Autohand's Fantail model.

## Decisions

| Area | Decision |
|---|---|
| Trigger | Hold **Fn+Shift** to talk; release to send. Plain Fn stays dictation. |
| Speech to text | Local. Parakeet Unified 0.6B for English (punctuation, caps, streaming); Parakeet v3 for other languages. |
| Reasoning | Autohand API, model `fantail`, streamed. |
| Voice | Local Kokoro-82M, voice `af_heart`, via FluidAudio (Neural Engine). |
| Account | Optional "Sign in with Autohand". Offered at the end of onboarding (skippable) and on first Talk use. |
| Plans | Free works. On a quota error, show an upgrade prompt. |

## Experience

1. Hold Fn+Shift. The Flow pill turns accent-coloured and reads
   "Talking to Fantail", so it is obvious text will leave the Mac.
2. Speak, release. Local STT produces the final transcript.
3. The pill shows a thinking wave; Fantail streams the reply.
4. Kokoro speaks the reply sentence by sentence as it arrives. The pill
   expands to show the reply text with **Insert**, **Copy** and **Stop**.
5. Hold Fn+Shift again to follow up; the conversation keeps context.
   Esc, or 2 minutes idle, ends the conversation.

Pressing Fn+Shift while it is speaking stops playback and starts listening
(barge-in by key in v1; by voice in v2).

## Phases

- **v1 – push-to-talk turns.** Everything above. No open mic while speaking,
  so no echo handling needed.
- **v2 – hands-free.** After the reply, listen again automatically. Detect end
  of speech with Parakeet EOU 120M; allow voice barge-in using macOS voice
  processing (echo cancellation) on the input.
- **v3 – context.** Per conversation, opt in to send the selected text and the
  frontmost app name ("reply to this email"). Off by default.

## Architecture

Separate components, matching the repo rule that capture, recognition,
normalization and insertion stay separate:

- `TalkSession` – state machine: idle → listening → transcribing → thinking →
  speaking → (listening | idle); owns conversation history.
- `AutohandAccount` – device sign-in, Keychain storage, `GET /v1/auth/me` for
  plan and remaining quota.
- `FantailClient` – streaming Chat Completions (SSE), error mapping.
- `SpeechSynthesizer` – Kokoro `af_heart`, sentence-level synthesis.
- `SpeechPlayback` – AVAudioEngine player; stop/flush for barge-in.
- Reuses `AudioCapture`, the local recognizer and the Flow HUD.

Markdown and code blocks are stripped before synthesis; the system prompt asks
for short, spoken-style answers.

## Autohand API contract (from `api` and `inference` repos)

Inference lives in the `inference` Worker; `api.autohand.ai` proxies it.

- **Endpoint:** `POST https://inference.autohand.ai/v1/chat/completions`
  (recommended; `api.autohand.ai/v1` also works with one extra hop).
  OpenAI-compatible. Body: `model:"fantail"`, `messages`, `stream:true`,
  `max_tokens`, `temperature`, `prompt_cache_key` (conversation id).
- **Auth:** `Authorization: Bearer ahc_…`. Keys do not expire; revoked → 401.
- **Streaming:** SSE `chat.completion.chunk` deltas, final usage chunk,
  `data: [DONE]`. Ignore `: keepalive` comments. No error events mid-stream:
  a dropped stream is a connection failure; a truncated one ends with
  `finish_reason:"length"`.
- **Server prompt:** the server prepends a ~370-token identity block to every
  request.
- **Safety check:** may return 400 `content_blocked` before streaming and can
  add up to 1.5 s before the first token.

### Sign-in (device flow)

1. `POST /v1/auth/cli/initiate` `{clientId:"autohand-cli", clientType, schemaVersion:2}`
   → `userCode`, `verificationUriComplete`, `deviceCode`, `interval:5`, `expiresIn:300`.
2. Open `verificationUriComplete` in the browser; the user signs in there.
3. `POST /v1/auth/cli/poll` every ≥5 s → `authorized` with `token: "ahc_…"`
   (delivered once). Store in Keychain.
4. `POST /v1/auth/cli/cancel` if the user gives up.

### Free plan and what it means for voice

Free: 15 messages per 5 hours, 100 per month, 10 requests/min,
1,000 input tokens/min, 1,160 output tokens/min, `fantail` only. Each Talk
turn is one message.

The token meter reserves `max_tokens` (default **16,000**) up front, so Talk
must always send a small `max_tokens` (about 300) and keep history compact
(last ~6 turns, older turns summarised or dropped). Otherwise free users hit
`output_tpm` after one turn.

The pill shows remaining turns from the `x-autohand-remaining-5h` and
`x-autohand-remaining-month` response headers when they are low.

### Error handling

| Response | Talk mode does |
|---|---|
| 401 `unauthorized` / `invalid_credential` / `session_expired` | Sign in again |
| 402 `eligibility_required` | "Verify your email to use Talk" with link |
| 403 `model_not_available` | Upgrade prompt |
| 429 `scope: window_5h` / `window_month` | "You've used your free Talk turns" + reset time (`resetAt`) + **Upgrade** (`upgradeUrl`) |
| 429 `scope: input_tpm` / `output_tpm` | "Give it a few seconds" (`Retry-After`) + Upgrade |
| 429 `scope: rpm` | Retry once after `Retry-After`, silently |
| 400 `content_blocked` | Show the server message; do not speak it |
| 5xx / dropped stream | "Fantail is unavailable" + Retry |

Only open `upgradeUrl` if it is https on `console.autohand.ai` (same check as
the CLI).

## Changes needed in the Autohand API

1. Accept `clientType: "voice"` in device sign-in (zod schema, DB CHECK
   migration, site allowlist), so devices show as "Autohand Voice". Until then,
   v1 can use `desktop`.
2. Accept `voice` in `x-autohand-client-type` for analytics.
3. Let `upgradeUrl` carry `from=voice` (currently hard-coded `from=cli`).
4. Optional: a lower default `max_tokens` for voice clients, or document the
   reservation behaviour for clients.

## Privacy

- Audio never leaves the Mac; only the final transcript text of a Talk turn
  and the conversation history are sent.
- Dictation never uses the network and never falls back to Talk.
- Conversation history lives in memory for the session; nothing is written to
  disk unless a later "Talk history" feature is added.
- Update `AGENTS.md`, the privacy copy and onboarding to describe Talk as an
  explicit, opt-in remote feature.

## Open questions

1. What is Autohand's server-side retention for chat requests? This is needed
   for the privacy copy.
2. Parakeet Unified download size and first-run cost. Should it download only
   when English is selected?
3. Should Talk replies ever be typed automatically, or only via **Insert**?
4. Should the Talk voice be selectable in Settings (`af_heart` default), and
   should it follow the dictation language?
