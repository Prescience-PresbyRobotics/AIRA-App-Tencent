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

Opening the screen preloads local JavaScript only. The user's Start action requests
an authenticated server session; `Conversation.startSession` receives:

```js
{
  conversationToken,
  connectionType: 'webrtc',
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
this as no provider logging or immediate deletion. The pre-Start disclosure names
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

Camera and facial analysis require their own actions; analysis starts only after
`face_cues` consent is saved. A fresh single-face estimate can be sent through the
protected call-context endpoint (label and timestamp only). Unknown, stale, no-face,
multiple-face and disabled states clear that estimate. A correction is sent as
`selfReportedFeeling`, separate from the model result; clearing the stated feeling
sends null. Both are ephemeral context, not automatically recorded mood measurements.

## Verification and limits

`realtime_lifecycle_test.cjs` runs the real adapter against a controlled SDK and
microphone: explicit capture, exact WebRTC options, captions, mute/unmute, late
permission after End, late connection cleanup, background cancellation and guard
restoration. `media_lifecycle_test.cjs` covers local camera/analysis lifecycle and
mirrored cover-crop box projection. The model smoke test executes actual bundled
weights and checks normalized boxes and cleared frame buffers. These automated
checks are not evidence of a real provider connection.

`app/test/call_screen_test.dart` verifies UI acceptance, real connection timing,
late tokens/connections, live captions, mute, background restart, analysis consent,
and separate self-report/context clearing. Native iOS/Android Flutter media adapters
remain unimplemented: use the browser build. Live provider transport, browser/device
microphone/audio permissions and iPhone Safari/Android Chrome need deployment/device
verification; report those separately from local mock tests.

Live verification on 16 October: the private agent settings were read back, a WebRTC
connection token was issued, and a synthetic provider WebSocket conversation received
a greeting plus a screened OpenAI reply with matching speech audio. End revoked
the app session and the synthetic account was removed. Jessica is the user-confirmed
live voice. These checks do not verify a physical browser microphone, WebRTC media
transport or camera device. The UI and final Firebase assets were checked separately.
