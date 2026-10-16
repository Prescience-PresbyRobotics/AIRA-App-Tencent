# AIRA-App-Tencent

A warm, English-first AI companion built with **Flutter, Supabase and Firebase Hosting**.

This is a functional prototype with a [hosted app](https://aira-app-tencent.web.app), a local interface preview and a deployed Supabase backend. **Live Auth, screened OpenAI, ElevenLabs STT/TTS and spoken-audio WebSocket/WebRTC tests passed on 16 October. The browser WebRTC test uses generated speech through the real SDK; a physical microphone and phone calls still need device testing. Google login still needs setup. Email verification stays enabled; the user reports it is working.** This is a tested prototype, not a production-ready service.

Canonical repository: [Prescience-PresbyRobotics/AIRA-App-Tencent](https://github.com/Prescience-PresbyRobotics/AIRA-App-Tencent). `aira-mobile-app` is a separate project; do not use its repository or cloud resources.

## Setup status — 16 October 2026

- Supabase project: `yzcnccjlwgrkxokgjtkv`, URL `https://yzcnccjlwgrkxokgjtkv.supabase.co`, already linked to the canonical repository.
- Core migration `202610140001`, realtime migration `202610160001` and history migrations `202610160002` / `202610160003` support the API, realtime gate, saved chat and worker. The core tables and new realtime-session table use RLS with server-side authorization.
- Firebase project: **AIRA-App-Tencent**, ID `aira-app-tencent`, hosted at [aira-app-tencent.web.app](https://aira-app-tencent.web.app). HTTPS, static assets and SPA fallback were verified on the hosted build. The final 16 October frontend is built and deployed; verification details appear below.
- Email confirmation stays enabled by the user’s 16 October instruction: verification is working according to the user. Only the **Forgot password** entry is hidden. This is user-reported delivery success, not an independent SMTP/email-delivery test. New passwords require 10 characters. Auth Site URL is `https://aira-app-tencent.web.app`; redirects allow localhost port 8080 and this project's `web.app`/`firebaseapp.com` domains. Google OAuth remains unconfigured; the Google Cloud console failed to load during setup. A custom SMTP sender has not been configured by this work; that does not negate the user’s successful verification report.
- Private worker/signing secrets, exact local/Firebase CORS origins and one minute-based Cron job are configured. Authenticated worker execution returned HTTP 200; unauthenticated API/worker calls returned 401. No external caregiver delivery occurs.
- Provider keys are stored in Supabase Edge secrets. `OPENAI_MODEL=gpt-4.1-mini`; ElevenLabs voice ID is `La9lzDJ3mmfNhhQA06WM`, with `scribe_v2` transcription and `eleven_multilingual_v2` speech synthesis.
- The 16 October source adds an authenticated ElevenLabs realtime agent session, the `aira-realtime` custom-LLM gate and a locally bundled `@elevenlabs/client` 1.28.0 bridge. Saved private-agent configuration was verified to require authentication, use the screened custom LLM with no fallback, disable voice recording and set `retention_days:0`. The 15-minute cap and scheduled deletion policy still need operational/device checks; zero-day retention is not proof of instant deletion or zero logging. The provider rejected special zero-retention mode with the custom LLM; the original cloned voice is also incompatible with this agent. A private agent is now provisioned with Jessica (`cgSgspJ2msm6clMCkdW9`) as the user-confirmed voice, and the realtime backend is deployed. Generated speech was recognized and answered over both WebSocket and the actual browser WebRTC SDK. A reproduced WebKit connection failure was fixed with the official SDK option `webRtc: { singlePeerConnection: false }`. Physical microphone/device testing remains pending. The temporary provisioning function was removed after testing.
- A live synthetic test on 15 October passed password authentication through the hosted Auth API, profile/consent checks, denied staff access, screened OpenAI text, ElevenLabs synthesis and transcription. Its preconfirmed temporary Auth account and app profile were removed and their absence verified.
- This machine has ignored `config/app.local.json` for a connected web build. Team members must configure their own local file; no private provider or worker secret belongs in the web app.

## Try the interface

Open the [hosted prototype](https://aira-app-tencent.web.app) and choose **Explore the interface** for an account-free preview. To build it locally, install the Flutter stable SDK and Python 3, make sure `flutter` is on your PATH, then run these commands from this project folder:

```sh
python3 scripts/check_app.py --build
python3 -m http.server 8080 --bind 127.0.0.1 --directory app/build/web
```

Open **http://localhost:8080** and choose **Explore the interface**. No account or API key is needed. Choose optional permissions, then try Chat, About me, Settings, caregiver/admin examples and the call screen. Aira asks your name in the first conversation; onboarding does not ask it again.

Preview data stays in memory and disappears on exit/reload. Dashboard history is explicitly synthetic. Chat never fabricates a live AI reply when services are missing. The preview does not connect a real voice provider. Local camera preview and separately enabled facial analysis use the bundled model and require camera permission and a compatible browser. They do not establish that a live call works.

For iterative development:

```sh
cd app
flutter pub get
flutter run -d web-server --web-port 8080
```

The build/check script runs checks in a temporary copy to avoid a Flutter test-loader issue with apostrophes in folder paths. It copies the successful web build back to `app/build/web`. Dependencies are downloaded on the first run. To use a Flutter executable outside your PATH, pass `--flutter /path/to/flutter/bin/flutter`.

## What is implemented

| Area | Current behavior |
| --- | --- |
| Design | Responsive cream/forest/coral Flutter UI, original animated vector companion, compact default, optional Larger text, mobile navigation and desktop sidebar. Compact uses 0.78× base text; Larger uses the previous default 0.9×. Device text scaling still applies, with minimum touch targets preserved; accessibility testing remains a release gate. Signed-in preferences persist. |
| Accounts | Supabase email registration/login UI and Google OAuth entry. Hosted password authentication is verified through the API. The user reports email verification works and confirmed it should stay enabled; signup directs users to check their email. Only Forgot password is hidden. Google OAuth setup remains incomplete. |
| Text | Saved signed-in text and call replies restore after reopening the app, with earlier-history pagination and explicit clear/opt-out controls. Aira opens with a name question, then follows a warm, one-question-at-a-time prompt. Actual message timestamps, server-acknowledged Delivered, Read after an AI reply, pending-only typing and retry states. OpenAI Responses uses permitted context/memory and buffered screening. |
| Voice | Tap to connect to a private ElevenLabs WebRTC call, with actual microphone level, input selection/recovery, sound/mic controls, captions and connected duration. The SDK compatibility setting fixes a reproduced browser connection failure. Generated spoken input passed browser recognition and reply-audio checks. Replies are buffered until approved; physical-device checks remain. |
| Video | Familiar full-screen call controls, expressive Aira (greeting wave, listening nods, thinking, talking, playful hop, tap reactions) and a local camera inset; pinned face-api.js 0.22.2 provides separately consented expression estimates/unknown states. Explicit feelings take priority. No human or generated remote video feed. |
| Personal information | Explicitly saved/forgotten memories, one-time plan follow-ups, confirmed medication reminders and optional dated weekly check-ins. |
| Reminders | Scheduled database worker, foreground polling, accept/decline and Taken/Skip/Snooze. No background delivery. |
| Care | Protected caregiver/admin screens, shared metrics, review decisions and report acknowledgement. Urgent qualifying flags route automatically to an **internal test inbox** with consent/link checks; nonurgent reports require review. |
| Privacy | Saved conversation text stays until deleted or Save conversations is turned off. New onboarding selects saving with clear wording; existing opt-outs remain off. Other optional consents default off. Server authorization, RLS and cancellation guards remain; other prototype content keeps its 24-hour expiry. |
| Hosting | Connected Flutter web build deployed on Firebase Hosting with HTTPS and SPA fallback; Supabase functions are deployed. |

Facial estimates are uncertain expression labels, not a diagnosis or a reliable measurement of how someone feels. Their model weights, licenses, processing rules and known limits are documented in [the model card](app/web/media/MODEL-CARD.md). Frames stay local; only a fresh label/time may accompany a permitted conversation request. User-reported feelings remain separate.

## Connect the services

The confirmed test environment above is connected. For team access or another environment:

1. **Supabase:** use the confirmed project above. Google OAuth remains to configure. Keep email confirmation enabled as the user requested. The user reports verification works; this work has not independently tested its email delivery. Only Forgot password is hidden; signup keeps the check-your-email step. The schema, Edge Functions and scheduled worker are already deployed there; use [the backend setup guide](supabase/README.md) when provisioning another environment.
2. **OpenAI:** the confirmed project's key and `gpt-4.1-mini` model are configured. For a new environment, add a key and explicit `OPENAI_MODEL` to Supabase Edge Function secrets. A ChatGPT subscription is separate from API access.
3. **ElevenLabs:** the confirmed project uses voice `La9lzDJ3mmfNhhQA06WM`. Realtime calls additionally need an authenticated agent, `ELEVENLABS_AGENT_ID`, `AIRA_CALL_SIGNING_SECRET` and `AIRA_REALTIME_BRIDGE_SECRET` on the server. Follow the [backend setup guide](supabase/README.md); verify saved provider privacy settings before real use.
4. **Firebase:** use project `aira-app-tencent`, selected in `.firebaserc`. Do not select `aira-mobile-app`. Firebase hosts the Flutter web files; Supabase remains the authentication/database/backend service.
5. **Public app configuration:** copy `config/app.example.json` to `config/app.local.json`, then fill in the Supabase URL and publishable/anon key. Those values are designed for the client. Keep service-role, OpenAI, ElevenLabs, worker and signing secrets out of this file.
6. **Redirects and origins:** allow the exact local and Firebase origins in Supabase Auth and `AIRA_ALLOWED_ORIGINS`. Google uses the Supabase Auth callback, not the Flutter URL. Test verification/recovery and new/returning Google accounts on the final domain. [Official Google setup](https://supabase.com/docs/guides/auth/social-login/auth-google).

Manage provider keys directly in [Supabase → Edge Functions → Secrets](https://supabase.com/dashboard/project/yzcnccjlwgrkxokgjtkv/functions/secrets), using `OPENAI_API_KEY`, `ELEVENLABS_API_KEY` and `ELEVENLABS_VOICE_ID`. These are already configured in the confirmed project. Do not paste secret values into chat or commit them. The app only needs the public Supabase URL and publishable/anon key.

To configure the worker for a fresh linked project or append the confirmed Firebase origins:

```sh
python3 scripts/configure_worker.py --project-ref YOUR_PROJECT_REF \
  --origin http://localhost:8080 --origin https://YOUR_FIREBASE_PROJECT_ID.web.app
```

The script preserves credentials in ignored `supabase/.env.infrastructure` with owner-only permissions, checks the linked project, and configures one named Cron job. It does not change provider keys. Keep that private local file available when rerunning the script; it refuses to overwrite unmatched existing credentials.

Build a connected web app from the root:

```sh
python3 scripts/check_app.py --build --config config/app.local.json
python3 -m http.server 8080 --bind 127.0.0.1 --directory app/build/web
```

For connected hot reload from `app/`:

```sh
flutter run -d web-server --web-port 8080 --dart-define-from-file=../config/app.local.json
```

## Deploy updates

Install the Firebase CLI and sign in with access to `aira-app-tencent`. The included `firebase.json` points at `app/build/web`; rebuild with the intended public configuration before deploying:

```sh
npm install -g firebase-tools
firebase login
python3 scripts/check_app.py --build --config config/app.local.json
firebase deploy --only hosting --project aira-app-tencent
```

Updates appear at [aira-app-tencent.web.app](https://aira-app-tencent.web.app); add a custom domain later if desired. HTTPS is required for camera/microphone outside localhost. [Firebase Hosting guide](https://firebase.google.com/docs/hosting/quickstart), [Flutter web deployment](https://docs.flutter.dev/deployment/web).

Calls use OpenAI **`gpt-4.1-mini`** through Responses to compose replies, **ElevenLabs Scribe Realtime** to recognize speech, and **Jessica / Flash v2** to speak. There is no OpenAI Realtime or OpenAI audio model in this integration. Balanced turn-taking and a fixed “Hmm, let me think” cue make screened-reply waits visible/audible. [ElevenLabs SDK](https://elevenlabs.io/docs/eleven-agents/libraries/java-script), [upstream compatibility fix](https://github.com/elevenlabs/packages/pull/963), [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini).

The current target is mobile browsers and desktop web. Android/iOS packages, app-store signing, native media adapters and background notifications are later work; they are not produced by Firebase Hosting.

## Verification

```sh
python3 scripts/check_app.py --build
node app/web/media/test/media_lifecycle_test.cjs
node app/web/media/test/model_smoke_test.cjs
deno check supabase/functions/aira-api/index.ts supabase/functions/aira-realtime/index.ts supabase/functions/aira-worker/index.ts
deno test -A supabase/tests/
```

Tests cover preview/auth layouts, consent and cleanup, late replies, account isolation, retry IDs, weekly missing-versus-zero responses, call/media lifecycle, protected dashboard data, API authorization, real PostgreSQL migration/RLS behavior and output gating. Automated model checks execute the bundled model; they are not accuracy or clinical validation.

Latest 16 October checks: **59 Flutter tests and 34 Deno tests passed**, along with both JavaScript media lifecycle suites. Browser checks verified that closing and reopening the app restores the same saved conversation. The final frontend with the redesigned call UI, richer mascot and persistent history is deployed to Firebase Hosting. Public app/voice-adapter files match the verified local build. The deployed API was also checked to persist Delivered before model completion, then return Read only with the saved reply. Hosted RLS, authorization rejection, CORS and worker execution were checked separately. Install Node.js for media checks and Deno 2 for backend checks; the database test downloads source-pinned PGlite on first use.

Live synthetic checks on 16 October passed Auth/API access, screened OpenAI (6.62 s), original-voice TTS (4.39 s), STT (2.01 s), WebRTC token issuance (1.90 s) and a direct screened call-bridge reply (5.78 s). An actual ElevenLabs **WebSocket** connection received the greeting, a matching reply with 159,760 audio bytes and an interruption event; the whole connection took 10.9 s. End invalidated the call token, and synthetic-account cleanup was verified. These are single-run observations, not latency guarantees or a browser microphone/WebRTC end-to-end test.

A later generated-speech WebSocket test passed recognition and spoken response. The repeatable browser test `scripts/smoke_browser_audio.py` then passed **actual WebRTC input, transcription and reply audio** (22.7 s total including connection, greeting and test speech; not a response-latency benchmark). It reproduced the old browser error before the compatibility fix and passed afterwards. The test substitutes generated audio for the physical microphone and requires audio after a meaningful reply, excluding the greeting/thinking cue. See [the live-call test guide](app/web/media/REALTIME-CALLS.md). All synthetic accounts were removed; the temporary setup function was deleted.

The command below repeats only the older bounded Auth/OpenAI/STT/TTS baseline.

To repeat the existing bounded integration smoke test, sign in to the Supabase CLI with project admin access and run:

```sh
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app --run
```

Omit `--run` to inspect the plan without accessing the network. A live run incurs normal provider charges: one app message (normally three OpenAI requests), one ElevenLabs synthesis and one transcription. It creates a marked synthetic account without sending email, keeps optional consents off, and removes the account in cleanup. Keys, tokens and audio are not printed or saved. If interrupted before cleanup completes, use the printed `--cleanup-run` command; details are in the [backend guide](supabase/README.md). The verified test covered hosted password authentication and provider APIs, not registration/confirmation emails, password-recovery delivery, Google OAuth or browser microphone/speaker behavior.

## Work still needed

- Finish Google OAuth setup and account-flow tests. Keep email verification enabled as requested; the user reports it works, while independent email-delivery testing remains to do. Only the Forgot password entry is hidden by choice.
- Physical-microphone and speaker/headphone checks on the hosted app. Generated-audio browser WebRTC testing verifies the SDK and provider path but not the computer’s microphone selection, acoustic echo or OS permissions.
- Physical camera/microphone testing on iPhone Safari and Android Chrome, assistive technology and senior usability checks.
- Verify device interruption/reconnect, the 15-minute limit, actual provider deletion behavior and pre-speech latency under realistic load; saved settings alone do not prove deletion timing. Recurring routines, background invitations and reliable medication alarms remain unimplemented.
- Self-service verified caregiver linking and staff provisioning. Prototype access is configured by a trusted administrator.
- Connected call-duration and genuine multiweek/cohort metrics; saved chats do not change the separate 24-hour impact-data policy or establish long-term benefit. Synthetic dashboard history is not evidence of benefit.
- Agreed pilot retention, provider controls, evaluated urgency rules, staffed review and actual caregiver delivery. No real caregiver has been contacted.

This README describes the current code and setup, including the remaining implementation work.
