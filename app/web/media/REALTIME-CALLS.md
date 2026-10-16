# AIRA live browser calls

Implemented 16 October 2026. Voice and video call screens use continuous ElevenLabs
WebRTC audio with the server's OpenAI custom-LLM endpoint. Video means the local
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
  customLlmExtraBody: { aira_session_token: signedPerCallToken },
  dynamicVariables: { aira_name: '...' },
  useWakeLock: false
}
```

The token is short-lived, kept in memory, and never logged, stored in local storage
or rendered. The server controls the selected agent, voice, shared custom-LLM
secret and OpenAI key. `customLlmExtraBody` is the official camel-case SDK option;
its payload reaches ElevenLabs' custom LLM as `elevenlabs_extra_body`.

The configured ElevenLabs agent has audio recording disabled and retention_days
set to zero, requesting scheduled deletion of provider conversation history and
audio after each call. This is not the provider's special zero-retention mode:
that setting is incompatible with this custom-LLM configuration. Do not describe
this as no provider logging or immediate deletion. The call details disclose
ElevenLabs voice processing, OpenAI replies, and this scheduled deletion policy.

The microphone is continuous while connected and unmuted. Mute immediately disables
tracked audio tracks and calls the SDK's `setMicMuted`; End silences output, disables
and stops tracks, calls `endSession`, clears transient captions and closes the server
call. Spoken interruptions are handled by ElevenLabs' VAD/WebRTC SDK. Replies may
pause while AIRA performs server checks. The screen counts duration only after a
successful WebRTC connection and displays actual user/agent captions and mode events.

The SDK currently provides no AbortSignal for its pending microphone permission
request. During the session, the adapter narrowly guards its audio `getUserMedia`
requests, remembers obtained tracks and immediately stops streams that arrive after
End or page hiding. Video requests pass through untouched. A new call is refused
while an earlier SDK connection is unresolved; this prevents old asynchronous work
from capturing for a new session. The original browser function is restored when
cleanup settles. There is no automatic reconnect or background resume in AIRA.

A video-call action opens the local camera after audio connects; voice calls can
enable the camera explicitly. Facial analysis remains separate and starts only after
`face_cues` consent is saved. A fresh single-face estimate can be sent through the
protected call-context endpoint (label and timestamp only). Unknown, stale, no-face,
multiple-face and disabled states clear that estimate. A correction is sent as
`selfReportedFeeling`, separate from the model result; clearing the stated feeling
sends null. Both are ephemeral context, not automatically recorded mood measurements.

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

On 16 October 2026, a browser test used the exact bundled SDK and adapter, generated
speech supplied as a synthetic MediaStream, a private agent token, and the deployed
screened OpenAI bridge. Before the compatibility option, WebRTC failed at negotiation.
After the option, both SDK audio streams opened, ElevenLabs recognized the expected
garden/tomatoes speech, and AIRA returned a new spoken reply. Observed input and
output levels were nonzero. This verifies real browser WebRTC transport and provider
audio ingestion, not a physical microphone, acoustic echo, headset routing, phone
behavior, or human conversational accuracy. Earlier WebSocket text-only testing did
not exercise microphone ingestion and is not used as evidence for this result.

Native iOS/Android Flutter media adapters remain unimplemented. Use the browser
build. Physical devices, permission flows, realistic interruption/echo, call limits
and actual provider deletion still need separate verification. Jessica remains the
user-confirmed live voice.

## Repeat the synthetic browser audio test

The test page lives in `scripts/`, outside the hosted app assets. It never opens a
physical microphone/camera; generated speech is injected into a MediaStream and
flows through the same official SDK and AIRA adapter. It creates a marked synthetic
account, mints a real call token, and deletes the account/call in `finally`. Normal
provider charges apply. The local server binds only to `127.0.0.1`, checks Host/Origin,
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
