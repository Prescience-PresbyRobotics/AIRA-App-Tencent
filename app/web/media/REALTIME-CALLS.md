# AIRA live browser calls

Implemented 16 October 2026. Voice and video call screens use continuous ElevenLabs
WebRTC audio with a native ElevenLabs Agent. The interaction prompt is saved in
ElevenLabs and uses its configured `deepseek-v41-flash` model. Calls never forward
to AIRA's OpenAI text endpoint. Video means the local
camera preview alongside AIRA's animated mascot; camera frames are never uploaded.
This is an AI companion, not another human on video.

## Official SDK and reproducibility

- Official [`@elevenlabs/client` 1.28.0](https://www.npmjs.com/package/@elevenlabs/client),
  published browser IIFE `dist/lib.iife.js`, copied unchanged to
  `vendor/elevenlabs-client-1.28.0.js`. It includes LiveKit client 2.21.0.
- npm tarball SHA-512 integrity and local bundle SHA-256 are recorded in
  `ELEVENLABS-ASSETS.json`. MIT client and Apache 2.0 LiveKit licences are bundled.
- No runtime CDN or browser provider key is used. The script is served with AIRA.
- SDK reference: https://elevenlabs.io/docs/eleven-agents/libraries/java-script
- Server token reference:
  https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token

To update, fetch the official npm package, verify npm integrity, review the SDK
contract and dependency licences, copy the published IIFE, update the manifest,
and rerun the lifecycle and browser checks. Do not hand-edit the vendor bundle.

## Contract and privacy

The user's voice/video call button starts an authenticated call; the browser asks
for microphone permission if needed. Preview mode does not start a provider call.
`Conversation.startSession` receives:

```js
{
  conversationToken,
  connectionType: 'webrtc',
  webRtc: { singlePeerConnection: false },
  dynamicVariables: {
    aira_name: '...',
    aira_greeting: '...',
    aira_call_id: '...',
    aira_call_binding: '...'
  },
  useWakeLock: false
}
```

The connection token and random call-binding nonce stay in memory and are never
logged, persisted to browser storage or rendered. The server controls the private
agent and holds the ElevenLabs key. There is no custom-LLM payload, OpenAI key or
custom bridge secret in the live-call path. The agent prompt/configuration lives
in `supabase/functions/_shared/voice_agent.ts` and is saved to ElevenLabs by the
protected temporary `aira-voice-setup` helper's `configure-native` operation.
That operation creates an agent when none is configured and updates it otherwise;
remove the deployed helper after setup. The retired `aira-realtime` route returns
410 so old browser builds cannot silently keep using the former OpenAI bridge.

The configured native model is `deepseek-v41-flash`; Scribe Realtime recognizes
speech and Jessica/`eleven_flash_v2` speaks. The agent's automatic thinking cue is
disabled (`soft_timeout_config.timeout_seconds=-1`), and its prompt forbids repeated
“Hmm, let me think” filler. Native calls use the provider's conversational behavior
and prompt safeguards; they are not buffered through AIRA's OpenAI text-screening
pipeline and do not automatically produce that route's incident records.

The requested provider privacy settings disable recording and set `retention_days`
to zero with transcript/audio deletion enabled. `zero_retention_mode` remains false.
Zero days requests scheduled deletion; it is not a guarantee of immediate deletion
or no provider logging. Saved AIRA transcripts are a separate owner-controlled
archive. The app saves SDK captions and later retrieves a canonical provider copy,
checking agent ID plus server-created call ID/binding against the provider's stored
initiation variables. Guessed provider conversation IDs cannot reveal another
owner's transcript. A labelled device-caption fallback remains if canonical
recovery is unavailable. Provider transcript recovery is bounded and respects
storage opt-out, account deletion and individual archive deletion.

Call text lives only in **Settings → Call history**, not the main chat window or
text-chat model context. It stays while Save conversations is enabled until the
owner deletes it. A late response cannot recreate a removed archive. Starting and
ending a call never clears the separate text thread; native call turns do not use
text-message quota. Preview calls/transcripts are clearly labelled examples.

The microphone is continuous while connected and unmuted. Mute immediately disables
tracked audio tracks and calls the SDK's `setMicMuted`; End silences output, saves
permitted final captions, disables/stops tracks, calls `endSession`, clears transient
captions and closes server call state. Spoken interruptions are handled by the
ElevenLabs VAD/WebRTC SDK. Duration begins only after a successful connection. The
interface uses actual caption/mode/audio-level events; the mascot is animated with
waves, hops, stretches, blinks, listening nods and speaking reactions, with no
eyebrows and with reduced-motion support.

The SDK currently provides no AbortSignal for its pending microphone permission
request. During the session, the adapter narrowly guards its audio `getUserMedia`
requests, remembers obtained tracks and immediately stops streams that arrive after
End or page hiding. Video requests pass through untouched. A new call is refused
while an earlier SDK connection is unresolved; this prevents old asynchronous work
from capturing for a new session. The original browser function is restored when
cleanup settles. There is no automatic reconnect or background resume in AIRA.

A video-call action opens the local camera after audio connects; voice calls can
enable it explicitly. Facial analysis needs the saved `face_cues` setting and browser
camera permission. Only fresh single-face expression labels/timestamps and optional
self-reported feelings may become transient native-agent context. Unknown, stale,
no-face, multiple-face and disabled states clear the estimate. Self-report takes
priority and stays separate. No camera frame is sent, and the prompt must not pretend
to see video or diagnose how someone feels.

## Scheduled incoming calls

**Settings → Calls from AIRA** lets the owner choose one daily time in Singapore time
(`Asia/Singapore`). No schedule is created until a time is chosen. A persistent
server schedule produces a two-minute foreground incoming invitation; the user can
Accept or Decline. A gentle local ringtone can be silenced; browser autoplay may block sound, but the visible controls remain available. The sound stops on accept/decline, expiry, logout or page hiding. Acceptance is owner-checked, versioned and single-use at call
reservation. The native agent's dynamic opening greeting makes Aira speak first.

The app must be open and visible at the chosen time. Closed tabs, sleeping devices,
PSTN calls and background phone notifications are unsupported. A missed/late or
busy occurrence does not unexpectedly ring later. Editing/pausing cancels pending
invitations; removing the schedule deletes them. An explicitly chosen time is
independent of ordinary social-reminder quiet hours and invitation limits.

## Browser compatibility and microphone controls

The published SDK embeds LiveKit 2.21.0, whose default single-peer connection join
failed in the tested WebKit browser before it published microphone audio:
`RTCPeerConnection.setConfiguration` rejected an unsupported configuration change.
A before/after real-provider test reproduced the failure and then passed with
`webRtc: { singlePeerConnection: false }`. This is the official SDK's supported
compatibility option; the vendor bundle is unchanged. See the upstream
[ElevenLabs fix](https://github.com/elevenlabs/packages/pull/963).

The SDK requests a preliminary permission stream and a second WebRTC capture stream.
It normally stops the first without emitting `ended`. The adapter checks only
still-live tracks, displays their microphone name, and reports device loss or
system muting. The input/output meters come from the SDK's actual audio analysers;
silence is not treated as a failure or proof that the provider heard speech.
The microphone chooser calls `changeInputDevice({inputDeviceId})`; additional
sample-rate/format options are unsupported by the bundled SDK's WebRTC path.
Speaker mute changes output volume and does not change the operating system's
speaker/headphone routing. Device names are local UI state, never sent to AIRA.

## Verification and limits

`realtime_lifecycle_test.cjs` exercises the real adapter with controlled SDK/device
fixtures: two-stream acquisition, dual-peer option, real level plumbing, captions,
waiting for a reply, mute/speaker controls, lost/changed devices, denied permission,
late permission after End, background cancellation and guard restoration.
`media_lifecycle_test.cjs` covers local camera/analysis lifecycle and mirrored
cover-crop box projection. These mock tests are separate from provider tests.

Historical check, earlier 16 October release: a browser test used the exact bundled
SDK and adapter, generated speech supplied as a synthetic MediaStream, a private
agent token and the then-deployed screened OpenAI bridge. It is transport evidence
for the previous release, not acceptance of the replacement native agent. Before the compatibility option, WebRTC failed at negotiation.
After the option, both SDK audio streams opened, ElevenLabs recognized the expected
garden/tomatoes speech, and AIRA returned a new spoken reply. Observed input and
output levels were nonzero. This verifies real browser WebRTC transport and provider
audio ingestion, not a physical microphone, acoustic echo, headset routing, phone
behavior, or human conversational accuracy. Earlier WebSocket text-only testing did
not exercise microphone ingestion and is not used as evidence for this result.

Native iOS/Android Flutter media adapters remain unimplemented. Use the browser
build. Physical devices, permission flows, realistic interruption/echo, call limits
and actual provider deletion still need separate verification. Jessica remains the
user-confirmed live voice. Current test/deployment results must identify the native
agent configuration actually exercised; earlier custom-bridge timings do not apply.

Current native-call release verification (16 October 2026): **72 Flutter tests and 42 Deno tests passed**, plus both JavaScript media lifecycle suites and a connected release web build. Supabase migrations004–006 and API/worker/retired-bridge functions are deployed; Firebase Hosting `aira-app-tencent` is updated. The private native agent settings were read back with `deepseek-v41-flash`, Jessica, no custom LLM or fallback, auth enabled and thinking filler disabled. A real browser WebRTC run with generated speech recognized the input and returned a spoken reply (16.1seconds for the entire fixture, not a response-latency benchmark). It then recovered the canonical provider transcript with ownership validation, verified that main text history contained no call turns, and sent a successful text message after hangup. A separate cloud check produced an invitation at the selected minute, accepted it and obtained a native session with Aira's scheduled opening greeting. Test accounts were removed and cleanup verified; the temporary setup function was deleted. Physical-device acceptance remains pending.

## Repeat the synthetic browser audio test

The test page lives in `scripts/`, outside the hosted app assets. It never opens a
physical microphone/camera; generated speech is injected into a MediaStream and
flows through the same official SDK and AIRA adapter. It creates a marked synthetic
account, mints a real call token, and deletes the account/call in `finally`. Normal
provider charges apply, including a separate text-chat check when the harness
verifies messaging after hangup. The call itself uses ElevenLabs only. The local
server binds only to `127.0.0.1`, checks Host/Origin,
and protects its in-memory token endpoint with a per-run nonce. Keys, tokens and
transcripts are not printed or saved. Only the caller-supplied synthetic WAV and a
non-secret cleanup journal are files.

Prepare a 1–30 second mono 16 kHz, 16-bit PCM WAV containing generated English speech.
On macOS, for example:

```sh
say --file-format=WAVE --data-format=LEI16@16000 -o /tmp/aira-smoke.wav "I enjoyed my garden today. The tomatoes are growing nicely. What do you think?"
python3 scripts/smoke_browser_audio.py --project-ref YOUR_PROJECT_REF
python3 scripts/smoke_browser_audio.py --project-ref YOUR_PROJECT_REF --audio-file /tmp/aira-smoke.wav --expect garden tomatoes --run
```

Set `--supabase /path/to/supabase` if needed. Open the printed `http://127.0.0.1:8766/`
URL, click **Run synthetic WebRTC call**, and keep the page visible. `--port` changes
the localhost port; `--origin` chooses an already allowed AIRA origin for server-side
API calls. `--timeout` bounds the server wait (default 180 seconds). The browser has
its own 75-second timeout beginning before SDK startup. Success requires all expected
transcript words, a subsequent non-filler agent reply, measured input audio, and
measured output **after that reply**, so the opening greeting cannot pass the test.
It reports only booleans/counts/levels and then stops media.

Ctrl-C and SIGTERM follow cleanup. After SIGKILL/power loss, use the printed run UUID:

```sh
python3 scripts/smoke_browser_audio.py --project-ref YOUR_PROJECT_REF --cleanup-run RUN_UUID
```

Cleanup verifies the account's synthetic identity markers before deletion. The
same cleanup UUID is compatible with `scripts/smoke_live.py --cleanup-run`.
