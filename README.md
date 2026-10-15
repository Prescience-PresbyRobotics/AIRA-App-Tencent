# AIRA-App-Tencent

A warm, English-first AI companion built with **Flutter, Supabase and Firebase Hosting**.

This is a functional prototype with a [hosted app](https://aira-app-tencent.web.app), a local interface preview and a deployed Supabase backend. **Hosted password authentication and live OpenAI/ElevenLabs APIs passed a synthetic smoke test. Google login and public registration email delivery still need setup.** Browser/device flows remain to be tested; the app is not yet ready for production use.

Canonical repository: [Prescience-PresbyRobotics/AIRA-App-Tencent](https://github.com/Prescience-PresbyRobotics/AIRA-App-Tencent). `aira-mobile-app` is a separate project; do not use its repository or cloud resources.

## Setup status — 15 October 2026

- Supabase project: `yzcnccjlwgrkxokgjtkv`, URL `https://yzcnccjlwgrkxokgjtkv.supabase.co`, already linked to the canonical repository.
- Migration `202610140001` applied; all 16 app tables have RLS enabled. `aira-api` and `aira-worker` deployed with server-side authorization.
- Firebase project: **AIRA-App-Tencent**, ID `aira-app-tencent`, hosted at [aira-app-tencent.web.app](https://aira-app-tencent.web.app). HTTPS, static assets and SPA fallback were verified; deployed JavaScript matches the connected local build.
- Email confirmation remains enabled; new passwords require 10 characters. Auth Site URL is `https://aira-app-tencent.web.app`; redirects allow localhost port 8080 and this project's `web.app`/`firebaseapp.com` domains. Custom SMTP and Google OAuth remain unconfigured; the Google Cloud console failed to load during OAuth setup.
- Private worker/signing secrets, exact local/Firebase CORS origins and one minute-based Cron job are configured. Authenticated worker execution returned HTTP 200; unauthenticated API/worker calls returned 401. No external caregiver delivery occurs.
- Provider keys are stored in Supabase Edge secrets. `OPENAI_MODEL=gpt-4.1-mini`; ElevenLabs voice ID is `La9lzDJ3mmfNhhQA06WM`, with `scribe_v2` transcription and `eleven_multilingual_v2` speech synthesis.
- A live synthetic test passed password authentication through the hosted Auth API, profile/consent checks, denied staff access, screened OpenAI text, ElevenLabs synthesis and transcription. Its preconfirmed temporary Auth account and app profile were removed and their absence verified.
- This machine has ignored `config/app.local.json` for a connected web build. Team members must configure their own local file; no private provider or worker secret belongs in the web app.

## Try the interface

Open the [hosted prototype](https://aira-app-tencent.web.app) and choose **Explore the interface** for an account-free preview. To build it locally, install the Flutter stable SDK and Python 3, make sure `flutter` is on your PATH, then run these commands from this project folder:

```sh
python3 scripts/check_app.py --build
python3 -m http.server 8080 --bind 127.0.0.1 --directory app/build/web
```

Open **http://localhost:8080** and choose **Explore the interface**. No account or API key is needed. Enter a preferred name, choose optional permissions, and try Chat, About me, Settings, caregiver/admin examples and the call screen.

Preview data stays in memory and disappears on exit/reload. Dashboard history is explicitly synthetic. Chat never fabricates a live AI reply when services are missing. On video, Start call → Camera → optional facial analysis uses the actual bundled model; it needs camera permission and a compatible browser. Recording in preview does not upload to a speech provider.

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
| Design | Responsive cream/forest/coral Flutter UI, original animated vector companion, compact default, optional Larger text, mobile navigation and desktop sidebar. Larger text preserves the original font size and roomy spacing; signed-in preferences persist and device text scaling remains supported. |
| Accounts | Supabase email registration, verification, login, recovery and Google OAuth UI. Hosted password authentication is verified through the API; public email delivery and Google OAuth setup remain incomplete. |
| Text | Authenticated OpenAI Responses integration with short-term context, approved memories and buffered reply screening. No API secret in the browser. |
| Voice | ElevenLabs transcription → editable transcript → screened OpenAI reply → ElevenLabs speech. Tap-to-speak, 45-second/5 MB recording limit. |
| Video | Character call plus local camera, separately consented open-source face-api.js expression inference and visible estimates/unknown states. Corrections take priority in conversation. |
| Personal information | Explicitly saved/forgotten memories, one-time plan follow-ups, confirmed medication reminders and optional dated weekly check-ins. |
| Reminders | Scheduled database worker, foreground polling, accept/decline and Taken/Skip/Snooze. No background delivery. |
| Care | Protected caregiver/admin screens, shared metrics, review decisions and report acknowledgement. Urgent qualifying flags route automatically to an **internal test inbox** with consent/link checks; nonurgent reports require review. |
| Privacy | Default-off consent choices, server authorization, RLS, request deduplication, account/turn cancellation guards, bounded media capture and 24-hour prototype content expiry. |
| Hosting | Connected Flutter web build deployed on Firebase Hosting with HTTPS and SPA fallback; Supabase functions are deployed. |

Facial estimates are uncertain expression labels, not a diagnosis or a reliable measurement of how someone feels. Their model weights, licenses, processing rules and known limits are documented in [the model card](app/web/media/MODEL-CARD.md). Frames stay local; only a fresh label/time may accompany a permitted conversation request. User-reported feelings remain separate.

## Connect the services

The confirmed test environment above is connected. For team access or another environment:

1. **Supabase:** use the confirmed project above. Configure an SMTP sender and Google OAuth. The schema, Edge Functions and scheduled worker are already deployed there; use [the backend setup guide](supabase/README.md) when provisioning another environment.
2. **OpenAI:** the confirmed project's key and `gpt-4.1-mini` model are configured. For a new environment, add a key and explicit `OPENAI_MODEL` to Supabase Edge Function secrets. A ChatGPT subscription is separate from API access.
3. **ElevenLabs:** the confirmed project uses voice `La9lzDJ3mmfNhhQA06WM`. For another environment, configure a permitted voice ID and API key using the names in `supabase/.env.example`.
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

The current target is mobile browsers and desktop web. Android/iOS packages, app-store signing, native media adapters and background notifications are later work; they are not produced by Firebase Hosting.

## Verification

```sh
python3 scripts/check_app.py --build
node app/web/media/test/media_lifecycle_test.cjs
node app/web/media/test/model_smoke_test.cjs
deno check supabase/functions/aira-api/index.ts supabase/functions/aira-worker/index.ts
deno test -A supabase/tests/
```

Tests cover preview/auth layouts, consent and cleanup, late replies, account isolation, retry IDs, weekly missing-versus-zero responses, call/media lifecycle, protected dashboard data, API authorization, real PostgreSQL migration/RLS behavior and output gating. Automated model checks execute the bundled model; they are not accuracy or clinical validation.

The 15 October check passed Flutter analysis, all 30 Flutter tests, all 17 backend tests and a connected web build. Media lifecycle/model smoke tests passed in the earlier implementation check; media code was unchanged. Hosted RLS, authorization rejection, configured CORS, worker execution and Firebase assets were verified. Install Node.js for the media checks and Deno 2 for the backend checks. The Deno database test downloads the source-pinned PGlite package on first use.

To repeat the successful live integration smoke test, sign in to the Supabase CLI with project admin access and run:

```sh
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app --run
```

Omit `--run` to inspect the plan without accessing the network. A live run incurs normal provider charges: one app message (normally three OpenAI requests), one ElevenLabs synthesis and one transcription. It creates a marked synthetic account without sending email, keeps optional consents off, and removes the account in cleanup. Keys, tokens and audio are not printed or saved. If interrupted before cleanup completes, use the printed `--cleanup-run` command; details are in the [backend guide](supabase/README.md). The verified test covered hosted password authentication and provider APIs, not registration/confirmation emails, password-recovery delivery, Google OAuth or browser microphone/speaker behavior.

## Work still needed

- Custom SMTP and email registration/confirmation/recovery tests; Google OAuth setup and new/returning account tests. Retry the Google Cloud console to finish OAuth configuration.
- Browser end-to-end chat/call testing on the hosted app; the successful provider smoke used synthetic audio through the backend API.
- Physical camera/microphone testing on iPhone Safari and Android Chrome, assistive technology and senior usability checks.
- Continuous voice conversation/interruption, recurring routines, background invitations and reliable medication alarms.
- Self-service verified caregiver linking and staff provisioning. Prototype access is configured by a trusted administrator.
- Connected call-duration and genuine multiweek/cohort metrics; the controlled 24-hour retention cannot establish long-term impact. Synthetic dashboard history is not evidence of benefit.
- Agreed pilot retention, provider controls, evaluated urgency rules, staffed review and actual caregiver delivery. No real caregiver has been contacted.

This README describes the current code and setup, including the remaining implementation work.
