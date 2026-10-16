# AIRA-App-Tencent

A warm, English-first AI companion built with **Flutter, Supabase and Firebase Hosting**. The [hosted prototype](https://aira-app-tencent.web.app) has an account-free interface preview and connected email accounts.

Canonical repository: [Prescience-PresbyRobotics/AIRA-App-Tencent](https://github.com/Prescience-PresbyRobotics/AIRA-App-Tencent). `aira-mobile-app` is a separate project; never use its repository or cloud resources.

## Current setup

- **Firebase:** `aira-app-tencent`, serving [aira-app-tencent.web.app](https://aira-app-tencent.web.app).
- **Supabase:** `yzcnccjlwgrkxokgjtkv`, URL `https://yzcnccjlwgrkxokgjtkv.supabase.co`.
- **Email:** registration/login with verification enabled. The user reports verification works; independent email-delivery testing remains separate. Only the Forgot password entry is hidden. New passwords require 10 characters. Google OAuth still needs configuration.
- **Main text chat:** OpenAI Responses with `OPENAI_MODEL=gpt-4.1-mini`, permitted context/memory, input/output screening and approved-reply speech playback.
- **Live voice/video:** the private native ElevenLabs agent runs the interaction prompt inside ElevenLabs, using `deepseek-v41-flash`, Scribe Realtime recognition and Jessica (`cgSgspJ2msm6clMCkdW9`) with Flash v2 speech. Calls make no request to AIRA's OpenAI conversation endpoint. Automatic thinking filler is disabled.
- **Ordinary message playback:** the separate ElevenLabs TTS route retains voice `La9lzDJ3mmfNhhQA06WM`, `eleven_multilingual_v2`, and bounded `scribe_v2` transcription.
- **Worker:** a minute-based Cron job creates due invitations, cleans expired prototype content and recovers completed-call transcripts. There is no external caregiver delivery adapter.

This is a functional prototype. Source-level implementation, automated tests and prior live checks are distinguished below; neither generated audio nor a deployed build proves physical microphone, phone or clinical readiness.

## Try the interface

Choose **Explore the interface** in the hosted app for an account-free preview. To run locally, install Flutter stable and Python 3, then from this project folder:

```sh
python3 scripts/check_app.py --build
python3 -m http.server 8080 --bind 127.0.0.1 --directory app/build/web
```

Open **http://localhost:8080**. Review the feature switches, continue, and try Chat, About me, Settings, care-view examples and the call screen. Aira asks your preferred name in the first conversation. Preview data is labelled synthetic, stays in memory and disappears on reload; preview never creates a real AI reply or provider call. Camera preview needs browser permission.

For iterative development:

```sh
cd app
flutter pub get
flutter run -d web-server --web-port 8080
```

The check script runs Flutter in a temporary copy to avoid an apostrophe-path test-loader issue, then copies successful output to `app/build/web`. Pass `--flutter /path/to/flutter/bin/flutter` when needed.

## Use the new call and care settings

- **Caregiver/admin:** open **Settings → Care connections → Caregiver view** or **Admin dashboard**. Desktop navigation also includes these views. Preview mode displays clearly labelled examples. In a signed-in account, caregiver data requires a verified owner-approved link; admin data requires an assigned staff role. Opening the screen does not grant access. A trusted project administrator must provision those records as described in [the backend guide](supabase/README.md#protected-care-views).
- **Call transcripts:** open **Settings → Call history**. Voice/video transcripts are separate from the main text thread and never become its model input. They persist while Save conversations is enabled and can be deleted individually. The archive labels provider transcripts versus device-caption fallbacks.
- **Incoming calls:** open **Settings → Calls from AIRA**, choose a daily time in **Singapore time**, and keep the app open and visible. Accept or decline the incoming invitation; Aira speaks first after acceptance. The schedule can be paused, edited or removed. Closed tabs, sleeping devices and background phone calls are not supported.
- **Feature defaults:** new accounts start with all eleven privacy, memory, reminder, wellbeing and care-sharing switches on, visibly reviewable during onboarding. Existing account choices stay unchanged. No default creates a call/medication schedule, grants a role, verifies a caregiver, sends a notification, or bypasses browser camera/microphone permission.

## What is implemented

| Area | Current behavior |
| --- | --- |
| Interface | Compact cream/forest/coral Flutter UI, Larger text option, device text scaling and usable touch targets. About me/Settings open focused management pages. |
| Mascot | Waves, hops, blinks, stretches, listens, thinks and reacts while speaking; reduced-motion support. Eyebrows are removed. |
| Text | Saved history restores across browser sessions with pagination. Delivered/Read, timestamps, pending-only typing and retry states. Calls no longer consume text-message quota; retry resumes a failed logical request. |
| Voice | Continuous native ElevenLabs WebRTC with familiar call controls, microphone level/input selection, mute, sound and connection duration. There is no custom OpenAI call bridge or automatic “Hmm, let me think” filler. |
| Video | Live audio, animated Aira and a local camera inset. Bundled face-api.js 0.22.2 estimates expressions locally, with face boxes and unknown/no-face states. No remote human or generated video stream. |
| Memory and wellbeing | Saved/forgotten memories, one-time plans and medication reminders, optional dated weekly check-ins and separate self-reported feelings. |
| Calls from AIRA | One owner-chosen daily schedule; a two-minute foreground incoming invitation, gentle optional ringtone, explicit Accept/Decline, first speech from Aira. Late/busy occurrences are missed instead of ringing unexpectedly later. |
| Care | Protected role/link-scoped dashboards, descriptive metrics and review decisions. Qualifying text flags route to an internal test inbox; no actual caregiver contact. Native calls use the agent prompt/provider behavior, not the text route's pre-release safety classifier. |
| Privacy | Saved chat/call text stays until deletion or storage opt-out; other prototype categories keep their separate expiry. RLS, owner checks and cancellation guards remain. |

Facial expressions are uncertain estimates, not diagnoses or reliable measures of how someone feels. Camera frames stay local. Only a fresh permitted label and optional self-reported feeling may be sent as transient agent context; words take priority. See [the model card](app/web/media/MODEL-CARD.md).

## Connect the services

The confirmed environment is connected. For team access or a separate environment, follow [the backend setup guide](supabase/README.md).

1. Configure Supabase Auth, migrations and Edge Functions. Keep email confirmation enabled; finish Google OAuth using the Supabase callback. Allow exact local/Firebase redirect URLs and CORS origins.
2. Store `OPENAI_API_KEY` and explicit `OPENAI_MODEL` for main text chat in Supabase Edge secrets. A ChatGPT subscription is separate from API access.
3. Store `ELEVENLABS_API_KEY`, `ELEVENLABS_AGENT_ID`, ordinary-playback `ELEVENLABS_VOICE_ID` and setup-time `ELEVENLABS_REALTIME_VOICE_ID`. The native agent prompt/settings live in `supabase/functions/_shared/voice_agent.ts`. The temporary `aira-voice-setup` helper can create or update it with `configure-native`; remove the helper deployment afterwards. Live calls no longer require custom-LLM bridge/signing secrets.
4. Use Firebase project `aira-app-tencent`, selected in `.firebaserc`.
5. Copy `config/app.example.json` to ignored `config/app.local.json` and fill only the public Supabase URL and publishable/anon key. Never put server/provider secrets in Flutter.

Manage keys in [Supabase Edge Function Secrets](https://supabase.com/dashboard/project/yzcnccjlwgrkxokgjtkv/functions/secrets); do not paste secrets into chat or commit them. This machine's ignored local configuration is not part of the team repository.

For a fresh linked worker configuration:

```sh
python3 scripts/configure_worker.py --project-ref YOUR_PROJECT_REF \
  --origin http://localhost:8080 --origin https://YOUR_FIREBASE_PROJECT_ID.web.app
```

The script preserves matching credentials in ignored `supabase/.env.infrastructure`, configures Vault and one Cron job, and refuses project/secret mismatches. Build the connected app with:

```sh
python3 scripts/check_app.py --build --config config/app.local.json
```

For connected hot reload, run from `app/`:

```sh
flutter run -d web-server --web-port 8080 --dart-define-from-file=../config/app.local.json
```

## Deploy updates

Apply reviewed Supabase migrations and deploy Edge Functions using [the backend instructions](supabase/README.md). Then build and publish to the separate Firebase project:

```sh
npm install -g firebase-tools
firebase login
python3 scripts/check_app.py --build --config config/app.local.json
firebase deploy --only hosting --project aira-app-tencent
```

HTTPS is required for microphone/camera outside localhost. Firebase hosts the Flutter web build; it does not produce signed iOS/Android apps or background call delivery. [Firebase Hosting](https://firebase.google.com/docs/hosting/quickstart), [Flutter web deployment](https://docs.flutter.dev/deployment/web).

## Verification

```sh
python3 scripts/check_app.py --build
node app/web/media/test/media_lifecycle_test.cjs
node app/web/media/test/realtime_lifecycle_test.cjs
node app/web/media/test/model_smoke_test.cjs
deno check supabase/functions/aira-api/index.ts supabase/functions/aira-realtime/index.ts supabase/functions/aira-worker/index.ts
deno test --allow-read supabase/tests/
```

Tests exercise owner/RLS boundaries, consent changes, request/worker deduplication, pending history, call transcript isolation/deletion, failed-message retries, scheduled-call timezone handling and single acceptance, account defaults, call lifecycle and actual bundled face-model execution. Model checks are not accuracy/clinical validation.

Current native-call release verification (16 October 2026): **72 Flutter tests and 42 Deno tests passed**, plus both JavaScript media lifecycle suites and a connected release web build. Supabase migrations004–006 and API/worker/retired-bridge functions are deployed; Firebase Hosting `aira-app-tencent` is updated. The private native agent settings were read back with `deepseek-v41-flash`, Jessica, no custom LLM or fallback, auth enabled and thinking filler disabled. A real browser WebRTC run with generated speech recognized the input and returned a spoken reply (16.1seconds for the entire fixture, not a response-latency benchmark). It then recovered the canonical provider transcript with ownership validation, verified that main text history contained no call turns, and sent a successful text message after hangup. A separate cloud check produced an invitation at the selected minute, accepted it and obtained a native session with Aira's scheduled opening greeting. Test accounts were removed and cleanup verified; the temporary setup function was deleted. Physical-device acceptance remains pending.

Historical verification of the earlier 16 October release passed 59 Flutter and 34 Deno tests. Its generated-speech browser WebRTC test reproduced a connection failure and passed after using `webRtc: { singlePeerConnection: false }`. It also verified saved chat after closing/reopening a tab. Those results concerned the earlier screened custom-LLM call path and are not acceptance evidence for the replacement native agent. The supported SDK compatibility setting remains in the current source.

Use [the live-call test guide](app/web/media/REALTIME-CALLS.md) for the repeatable synthetic browser test. It uses generated speech through the real SDK and never opens a physical microphone/camera. The separate bounded text/STT/TTS baseline is:

```sh
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app --run
```

Omit `--run` for a plan without network access. The live baseline verifies new-account defaults, explicitly disables optional features on its synthetic account, then tests screened OpenAI text, ElevenLabs speech and transcription. Normal provider charges apply. It sends no email, makes no caregiver contact, keeps keys/audio/text out of output and removes the marked account in cleanup. It does not verify registration email, Google OAuth or physical audio devices.

## Work still needed

- Google OAuth and independent email-delivery/account-flow checks; keep verification enabled and Forgot password hidden as requested.
- Physical microphone/headphone/camera testing on desktop, iPhone Safari and Android Chrome, including permissions, echo, interruptions, reconnect and accessibility.
- Operational validation of native-agent behavior, 15-minute call caps and actual provider deletion timing. Zero-day scheduled deletion is not instant deletion or zero logging.
- Push/background incoming calls, dependable medication alarms and recurring medication/routine scheduling. Daily foreground companion calls are implemented separately.
- Self-service verified caregiver linking, staff provisioning/MFA, care operations and actual recipient delivery. No real caregiver has been contacted.
- Genuine multiweek/cohort measurement and clinical/safety evaluation. Synthetic charts are never evidence of benefit; the native call prompt is not a proven monitoring or prevention system.
