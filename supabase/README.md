# AIRA backend — controlled prototype

Implemented 14 October; deployed to the confirmed AIRA-App-Tencent Supabase project on 15 October 2026. Project `yzcnccjlwgrkxokgjtkv` now has core migration `202610140001` plus realtime migration `202610160001`, RLS-protected app/session tables, `aira-api`, `aira-realtime`, `aira-worker`, private worker/signing secrets and a minute-based Cron job. The connected frontend is deployed to Firebase project `aira-app-tencent` at [aira-app-tencent.web.app](https://aira-app-tencent.web.app).

Hosted authorization rejection, local/Firebase CORS, authenticated worker execution, password authentication through the hosted Auth API and live OpenAI/ElevenLabs calls were verified. The preconfirmed synthetic test account and app profile were deleted and their absence verified. **Google OAuth remains incomplete. Email verification stays enabled at the user’s request, and the user reports it works; no independent SMTP/email-delivery test was performed. Only Forgot password is hidden.** The 16 October realtime call source and backend are deployed, with a private Jessica agent provisioned; a live provider WebSocket exchange and WebRTC token issuance passed on 16 October. These do not establish browser microphone/WebRTC or physical-device behavior. The Google Cloud console failed to load during OAuth setup. Browser/device flows remain to be tested. There is no external caregiver delivery adapter.

The confirmed environment uses `OPENAI_MODEL=gpt-4.1-mini`, ElevenLabs voice `La9lzDJ3mmfNhhQA06WM`, STT model `scribe_v2` and TTS model `eleven_multilingual_v2`. Provider keys stay in Edge Function secrets. Supabase Auth Site URL is `https://aira-app-tencent.web.app`; redirect URLs allow localhost port 8080 and this project's `web.app`/`firebaseapp.com` domains. CORS allows their exact origins. Email confirmation remains enabled and new passwords require 10 characters. The user explicitly confirmed on 16 October that verification is working and must stay enabled. Only the Forgot password entry is hidden; signup retains the check-your-email step. The user’s report is separate from this work’s API tests, which do not test email delivery.

The backend accepts Supabase's injected modern `SUPABASE_SECRET_KEYS` dictionary (default key), older `SUPABASE_SECRET_KEY`, or legacy `SUPABASE_SERVICE_ROLE_KEY`. Optional `AIRA_SUPABASE_SECRET_KEY_NAME` selects a named dictionary key. Modern secret keys are sent in `apikey`, while Auth verification retains the user's Bearer token.

## What is implemented

- Supabase Auth identity is checked server-side for every API request.
  Email/password and Google sign-in are configured through Supabase, not a
  parallel password database.
- Owner-scoped database reads, denied direct writes, server-managed staff
  assignments, verified caregiver links, audited protected dashboard access.
  User-editable Auth metadata never grants a role.
- Explicit consent choices, confirmed memories, one-time foreground reminders,
  invitation acceptance/decline, medication Taken/Skip/Snooze self-reports,
  deletion, and 24-hour content expiry.
- OpenAI Responses requests with an explicit environment-selected model and
  `store:false`. Replies are buffered and screened using strict structured
  output before release. Invalid/unavailable screening substitutes fixed support
  copy; unchecked replies are not displayed or spoken.
- A realtime ElevenLabs session route plus an `aira-realtime` custom-LLM gate reuse the same screened OpenAI path. Account/consent-bound session tokens expire after 15 minutes. The gate holds the full response until approved, then returns it to ElevenLabs for speech; expect additional latency. Provider WebSocket behavior is verified; browser microphone/WebRTC and physical-device behavior remain pending.
- ElevenLabs bounded transcription and speech remain available. Speech requires a signed five-minute
  approved-reply token bound to account, request and current consent version.
  The API accepts no arbitrary text-to-speech request.
- Transactional request/occurrence/action deduplication; automatic urgent
  **internal test** reports; nonurgent report approval by an assigned reviewer.
  Test delivery, acknowledgement and case resolution are separate states.
- Optional dated seven-day loneliness question (0–7 or Skip), separate
  self-reported feelings, and the same descriptive insights response for
  permitted owners/caregivers/admins.

## Set up another environment

The confirmed project above is already provisioned. Use these steps for another test environment; do not overwrite its existing secrets with blank example values.

1. Create a Supabase project for **development/testing**, choose a region
   deliberately, and record its project reference and URL. Keep its database
   password private.
2. In Auth, enable email/password, email confirmation and password recovery.
   Configure your own SMTP sender for confirmation/recovery. The current hosted project keeps confirmation enabled by the user’s confirmed choice, with verification reported working. Independently verify delivery when provisioning a new environment. Keep anonymous
   sign-in disabled for this implementation.
3. Create a Google OAuth web client in Google Cloud. Configure its consent
   screen and permitted audience, using only basic identity scopes (`openid`,
   `email`, `profile`). Use the exact Supabase callback
   shown in Auth → Google (normally
   `https://PROJECT_REF.supabase.co/auth/v1/callback`) as the Google authorized
   redirect. Put the Google client ID/secret in Supabase's provider settings,
   never Flutter.
4. In Supabase Auth URL configuration set Site URL to the final Firebase Hosting
   URL. Allow the exact local development and deployed callback/recovery URLs
   that the app uses. Test new/returning Google login, cancelled OAuth, email
   confirmation and recovery on the real hosting domain. See
   [Supabase Google setup](https://supabase.com/docs/guides/auth/social-login/auth-google).
5. Create an OpenAI API project and key, select an available Responses model
   supporting structured output, and set **`OPENAI_MODEL` explicitly**. A
   ChatGPT subscription is not an API credential. Optionally choose a separately
   tested `OPENAI_SAFETY_MODEL`; otherwise the same selected model performs
   screening. Configure provider usage limits.
6. Create an ElevenLabs API key and choose a permitted voice ID. Confirm that
   the configured speech models are available to your account. Defaults in the
   example are `scribe_v2` and `eleven_multilingual_v2`; those are integration
   starting points, not measured language/latency guarantees.
7. Copy `.env.example` to `.env`, fill its secrets locally, and generate
   independent random values of at least 32 characters for
   `AIRA_SPEECH_SIGNING_SECRET` and `AIRA_WORKER_SECRET`. Set
   `AIRA_ALLOWED_ORIGINS` to exact browser origins (comma separated; no
   wildcard). Do not paste keys into chat or commit this file.
8. Flutter needs only the **public Supabase URL and publishable/anon key**. The
   Supabase service-role key and OpenAI/ElevenLabs keys stay in Edge Function
   secrets. Firebase Hosting serves Flutter's static build; it does not run
   these functions.

## Local and hosted commands

Install the Supabase CLI and a Docker-compatible local runtime for the full
Supabase development stack. From the repository root:

```sh
supabase start
supabase db reset
supabase functions serve --env-file supabase/.env
```

`db reset` resets the local development database; do not aim it at production.
Local email confirmations can be inspected through Supabase's local mail UI.
`config.toml` allows `http://localhost:8080` redirects; run Flutter on that origin
or update both the allowed origins and Auth redirects. Its fallback Site URL
is the hosted app; use a local Site URL when testing a separate local-only stack.

After creating your **test** cloud project, apply the reviewed migration and
functions:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set --env-file supabase/.env
supabase functions deploy aira-api
supabase functions deploy aira-realtime
supabase functions deploy aira-worker
```

The function configuration sets `verify_jwt=false` because `aira-api` explicitly
validates the access token using Supabase Auth and supports current project
signing keys. This does **not** make application endpoints anonymous. The worker
instead requires a separate secret header and rejects missing/short secrets. See
[Supabase function authorization](https://supabase.com/docs/guides/functions/auth).

Record the migration version and deploy to a test project before inviting
anyone. Code rollback means redeploying the previous reviewed function sources;
database rollback requires a reviewed forward migration or database restore, not
deletion of migration history. Backups/provider retention are distinct from
application-level deletion.

## Realtime voice setup — source added 16 October

Flutter uses the locally bundled `@elevenlabs/client` **1.28.0** browser SDK. Audio connects to ElevenLabs; the provider calls `/functions/v1/aira-realtime/chat/completions` for conversational output. That function authenticates the provider bridge secret, verifies a signed live-session token, rechecks account/consent/call status and invokes the existing `aira-api` screened OpenAI pipeline. It discards provider system prompts and releases only a complete approved response or the existing fixed safe fallback. The approved text is returned in an OpenAI-compatible response/SSE envelope; raw model tokens are never streamed into speech. This buffering adds latency.

For a fresh environment, apply all migrations, deploy `aira-api` and `aira-realtime`, and configure:

- `ELEVENLABS_AGENT_ID`: the private, authenticated agent ID.
- `AIRA_CALL_SIGNING_SECRET` and `AIRA_REALTIME_BRIDGE_SECRET`: independent high-entropy server secrets, at least 32 characters; keep them out of Flutter and logs.
- Existing OpenAI/ElevenLabs keys, voice ID and explicit `OPENAI_MODEL` remain required.

`aira-voice-setup` is a one-time protected provisioning helper: deploy it explicitly, invoke it with the existing worker secret, save the returned agent ID as `ELEVENLABS_AGENT_ID`, then remove the helper deployment. It creates an agent; it is not a repeatable update operation. Its source selects the screened custom LLM with backup LLM disabled, `eleven_flash_v2` speech for the English agent, a 900-second call cap, patient turn-taking and authenticated token access. Current settings request `record_voice:false`, `retention_days:0`, `delete_transcript_and_pii:true`, `delete_audio:true` and `zero_retention_mode:false`. The provider rejected special zero-retention mode with a custom LLM. Zero-day retention schedules deletion; it is not proof of instant deletion or zero logging. The saved agent was checked for authentication, the custom LLM, no fallback, recording off and zero-day retention. Actual deletion behavior and account terms still need review before real use. The temporary `aira-voice-setup` deployment was removed after the test. Do not expose the worker or bridge secrets in shell history or browser configuration.

Start calls only after the user's action. Flutter receives a short-lived conversation token plus signed custom-LLM context; End stops local media immediately and invalidates server call state. Fresh consented face labels and explicit feelings travel through the context endpoint, not as camera frames. Clearing camera/analysis sends null; self-report stays separate from the facial estimate. The browser also bundles local face-api.js **0.22.2** and model assets. A video call combines realtime audio, Aira's animated mascot and the user's optional local camera; it is not remote generated video.

The chosen voice `La9lzDJ3mmfNhhQA06WM` works with the older TTS endpoint but the provider rejected it as an instant voice clone for this custom-LLM agent. A private agent is now provisioned with Jessica (`cgSgspJ2msm6clMCkdW9`) as the user-confirmed voice; the original voice remains configured for the older TTS endpoint. The realtime backend is deployed. A live provider WebSocket connection returned the greeting, a matching spoken reply and an interruption event; WebRTC token issuance, direct screened bridge output and End/token revocation also passed. Browser microphone/WebRTC, reconnect, echo, physical-device cleanup and actual retention behavior remain verification gates. [ElevenLabs retention guidance](https://elevenlabs.io/docs/eleven-agents/customization/privacy/retention) describes scheduled deletion, which is separate from AIRA’s database storage toggle. The bounded STT/TTS and provider WebSocket checks do not close those browser/device gates.

## Enable due work and retention cleanup

For a new linked project, use `python3 scripts/configure_worker.py --project-ref YOUR_PROJECT_REF --origin http://localhost:8080` from the repository root. Add repeated `--origin` options for confirmed Firebase URLs. It preserves matching private infrastructure secrets, configures Vault and extensions, and creates or updates one named Cron job. It refuses project/secret mismatches and never prints secret values. The manual equivalent follows.

Enable Supabase Cron (`pg_cron`) and `pg_net`. Store the project URL and the
same worker secret in Supabase Vault under `aira_project_url` and
`aira_worker_secret`. Use the dashboard to enter secret values. Then schedule
this SQL in the test project:

```sql
select cron.schedule(
  'aira-worker-every-minute',
  '* * * * *',
  $$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets
            where name = 'aira_project_url') || '/functions/v1/aira-worker',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-aira-worker-secret', (select decrypted_secret from vault.decrypted_secrets
                               where name = 'aira_worker_secret')
    ),
    body := '{}'::jsonb
  );
  $$
);
```

The worker only creates database events and writes `test_delivered` to an
authenticated internal inbox. There is **no** email/SMS/webhook destination
field or external messaging adapter. The outbox's `external_delivery` database
constraint is always false. A missing/revoked recipient prevents delivery; it
never picks someone else.

A minute-based cron can add up to roughly a minute before an event is created.
Foreground polling then finds the event. This is **not** a dependable medication
alarm or a background incoming-call service, and tighter timing targets have not been demonstrated. Invitation life is 30 seconds from creation,
social hours are 09:00–21:00 in the stored timezone, and a decline pauses
invitations for 24 hours. Medication occurrences do not use the social cap.
Physical expiry cleanup depends on Cron; all exposed content reads additionally
filter expiry. Inspect Cron failures and function logs without logging bodies.
[Supabase scheduling guide](https://supabase.com/docs/guides/functions/schedule-functions).

## API contract for Flutter

Base: `SUPABASE_URL/functions/v1/aira-api`. Send
`Authorization: Bearer <current Supabase access token>` and JSON content type.
SDK auth operations remain direct Supabase Auth calls. UUIDs are required for
idempotency IDs.

Errors: `{code,message,retryable,requestId}` with
400/401/403/404/409/413/429/503 status. Private responses use
`Cache-Control: no-store`. Database row fields are snake_case; request
wrapper/ID fields below are camelCase.

| Method/path                                      | Request and response                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GET /v1/me`                                     | `{profile,preferences,capabilities,roles}`. `profile.consent_version` is the current privacy version.                                                                                                                                                                                                                                        |
| `PATCH /v1/preferences`                          | Profile: `display_name`, `timezone`, `text_scale` (1–2), `reduced_motion`, `onboarded`, `locale:'en'`. Consent choices can use canonical `consents:{...}` or flat Flutter aliases below. Returns updated `{profile,preferences}`.                                                                                                            |
| `POST /v1/messages`                              | `{clientMessageId,text,mode,conversationId?,contextVersion?,context?:[{role,text}],introductionShown?,cueSummary?:{label,observedAt},selfReportedFeeling?}`. Returns `{conversationId,messageId,text,status,speechToken,privacyVersion,provider}`. Max 2,000 characters, 10 submissions/minute and 20/hour/account. `status` is approved/support/safe_fallback. |
| `GET /v1/messages/:clientMessageId/status` | Owner-scoped acknowledgement: `{status:'processing' or 'completed' or 'failed' or 'not_found',createdAt?}`. Delivered requires a server record; Read means an actual Aira reply returned, not human attention. |
| `POST /v1/audio/transcriptions`                  | `{audioBase64,mimeType,locale:'en'}` → `{text,editable:true,provider:'elevenlabs'}`. Max 5,000,000 decoded bytes; base MIME supports webm/mp4/wav/ogg/mpeg, with codec suffixes normalized.                                                                                                                                                  |
| `POST /v1/speech`                                | `{speechToken}` → `{audioBase64,mimeType:'audio/mpeg',provider:'elevenlabs'}`. Speech/transcription share a 40-request/hour/account limit.                                                                                                                                                                                                   |
| `GET /v1/memories`                               | `{memories:[{id,text,category,version,expires_at,...}]}`.                                                                                                                                                                                                                                                                                    |
| `POST /v1/memories`                              | `{text,category?,confirmed:true}` → `{memory}`. Categories preference/relationship/plan/other.                                                                                                                                                                                                                                               |
| `PATCH /v1/memories/:id`                         | `{text,expectedVersion}` → `{saved,privacyVersion,clearContext:true}`.                                                                                                                                                                                                                                                                       |
| `DELETE /v1/memories/:id`                        | `{saved,privacyVersion,clearContext:true}`. Clears previous transcript/context and invalidates speech tokens so forgotten material cannot remain in short-term retrieval.                                                                                                                                                                    |
| `GET /v1/medications` or `/v1/events/proposals`  | `{schedules:[{id,kind,label,instructions,due_at,timezone,version,recurrence:'once',...}]}`.                                                                                                                                                                                                                                                  |
| `POST /v1/medications`                           | `{label,instructions?,dueAt?,localTime?:'HH:mm',confirmed:true,recurrence?:'once'}` → `{schedule}`. `localTime` resolves the next time in the profile timezone.                                                                                                                                                                              |
| `POST /v1/events/proposals`                      | `{label? or topic, dueAt? or followupAt, confirmed:true}` → `{schedule}`. No plan is inferred complete.                                                                                                                                                                                                                                      |
| `PATCH /v1/medications/:id` or `/v1/events/:id`  | `{expectedVersion,label?,dueAt?,enabled?}` → `{schedule}`; atomically cancels old pending occurrences.                                                                                                                                                                                                                                       |
| `DELETE /v1/medications/:id` or `/v1/events/:id` | `{deleted:true}`; cancels dependent occurrences.                                                                                                                                                                                                                                                                                             |
| `GET /v1/events`                                 | `{events:[{id,kind,label,state,action_version,expires_at,...}]}` with pending/due/snoozed foreground records only.                                                                                                                                                                                                                           |
| `POST /v1/medication-occurrences/:id/respond` | `{action:'taken' or 'skip' or 'snooze',requestId,expectedVersion,nextNotifyAt?}` → `{event}`. Version is `action_version`; Taken is user self-report. |
| `POST /v1/invitations/:id/respond` | `{action:'accept' or 'decline',requestId,expectedVersion}` → `{event}`. Acceptance creates `event.conversation_id`; decline pauses social invitations for 24 hours. |
| `POST /v1/calls/session` | `{mode:'voice' or 'video'}` → `{conversationId,conversationToken,customLlmExtraBody:{aira_session_token},dynamicVariables:{aira_name},expiresAt}`. Authenticated, short-lived realtime session; no provider API key returned. |
| `PATCH /v1/calls/:id/context` | `{cueSummary?:{label,observedAt},selfReportedFeeling?}`. Both accept null to clear; fresh labels require current face consent, and explicit feelings take priority. |
| `POST /v1/calls` | `{mode:'voice' or 'video'}` → `{conversation}`. Start only after explicit acceptance. |
| `POST /v1/calls/:id/end`                         | Idempotent `{ended:true}`. Client must stop every media track and clear buffers locally.                                                                                                                                                                                                                                                     |
| `GET /v1/measurements/prompt`                    | `{prompt:{id,period_start,period_end,timezone,question_version,question,optional:true},response}`. May return `prompt:null` until next eligible week after expiry.                                                                                                                                                                           |
| `POST /v1/measurements/loneliness`               | `{promptId,lonelyDays:0..7,skipped:false,requestId,expectedVersion:0}` (or skipped true, no value). Edits use current response version. Returns `{response}`. Dates come only from the server prompt.                                                                                                                                        |
| `POST /v1/measurements/mood` | `{label:'happy' or 'okay' or 'sad' or 'worried' or 'tired'}`. Requires `mood_history` consent; records explicit self-report only. |
| `GET /v1/me/insights`                            | Shared insights shape below.                                                                                                                                                                                                                                                                                                                 |
| `DELETE /v1/conversations/:id`                   | `{deleted:true,clearContext:true}`. Separately approved memories remain.                                                                                                                                                                                                                                                                     |
| `DELETE /v1/me/data`                             | Purges owned app content and disables app access for the existing Auth identity. Client must sign out. Supabase Auth-account deletion is a separate administrative action; this route does not delete the login identity.                                                                                                                    |

Canonical consent keys are `conversation_storage`, `memory`, `social_reminders`,
`medication_reminders`, `monitoring`, `impact`, `mood_history`, `face_cues`,
`urgent_sharing`, `reviewed_sharing`, `admin_insights`. All start false. Flutter
aliases are `store_conversations`, `memory_enabled`, `monitoring_enabled`,
`impact_measurement`; other names stay unchanged. Unknown/role fields are
rejected. Changes invalidate speech tokens. Withdrawal purges category content
and blocks queued access.

Without conversation storage, the client sends at most ten recent turns with
**`contextVersion == profile.consent_version`**; the server persists no
transcript. Clear that buffer on logout, account change, conversation deletion
and memory edit/forget. A completed duplicate request can return `text:null` in
no-storage mode because the server cannot reconstitute a deleted reply; retain
the original response in the active client buffer, or invite an explicit fresh
message. Do not silently submit a new ID to retry a completed request. Provider
storage controls remain independent of AIRA's database storage toggle.

## Protected care views

Create separate Supabase test accounts. Trusted operators provision
`role_assignments` and `caregiver_links` through a reviewed server/admin
process; there is no public role or verified-contact setter. `role_assignments`
supports operator (no subject, counts only), reviewer (explicit subject), and
insights (explicit subject). Roles and relationships are independent of user
metadata. Caregiver scopes are urgent/reviewed/loneliness/conversations/mood,
with verified identity, test_recipient=true and no revocation. Only provision a
link **after the senior explicitly approves that scope**. Self-service caregiver
invitation/verification is not yet implemented.

| Endpoint                                 | Requirement/result                                                                                  |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `GET /v1/admin/overview`                 | Operator → `{queueCount,externalDelivery:false,mode:'test_only',staffedCoverage:'Not configured'}`. |
| `GET /v1/admin/subjects`                 | Returns `{seniors:[{id,display_name}]}` for explicit insights assignments.                          |
| `GET /v1/admin/incidents`                | Assigned reviewer + subject monitoring consent → `{incidents}`. No blanket reviewer access.         |
| `POST /v1/admin/incidents/:id/review` | `{state,reason,expectedVersion,approveReport?}`. State: reviewed, dismissed, followup or closed. Assigned reviewer and subject consent required. Returns `{incident,externalDelivery:false}`; report approval is separate from urgent automatic routing. |
| `GET /v1/admin/insights?subjectId=UUID`  | Explicit insights assignment **and** senior `admin_insights` consent.                               |
| `GET /v1/caregiver/seniors`              | Current verified links → `{seniors:[{id,display_name,scopes}]}`.                                    |
| `GET /v1/caregiver/seniors/:id/insights` | Category-scoped sharing only.                                                                       |
| `GET /v1/caregiver/reports`              | Consent-linked **internal** test inbox → `{reports,externalDelivery:false}`.                        |
| `POST /v1/caregiver/reports/:id/ack`     | Current recipient/scope check → `{acknowledged:true,resolved:false}`.                               |

Insights are
`{subjectId,definitionVersion,synthetic:false,generatedAt,retentionHours:24,categories,loneliness,conversations,mood,supportedSeniors}`.
`loneliness.periods` includes original prompt dates and its optional response;
baseline is first available non-skipped answer. No fabricated multiweek deltas
are returned. Conversation count requires a server-approved reply; senior/AIRA
initiation are separate. Duration is **null / not instrumented**, not zero. Mood
has self-report records and an empty inferred series; facial cues remain
transient. Synthetic charts belong to the clearly separate Flutter preview and
are not submitted to these real metrics.

## Verification

```sh
deno check supabase/functions/aira-api/index.ts supabase/functions/aira-realtime/index.ts supabase/functions/aira-worker/index.ts
deno test -A supabase/tests/
```

Tests include an isolated PostgreSQL 17 WASM database
(`@electric-sql/pglite@0.3.14`), using a minimal Auth stand-in. They execute the
migration, RLS, transaction functions and scheduled worker. They cover
cross-owner denial, direct mutation/RPC denial, no-storage privacy, memory
forget/context invalidation, request/action/worker deduplication, consent
withdrawal, urgent automatic test routing, nonurgent review, fixed weekly
periods, valid zero, and deletion. Provider calls in tests are mocked;
output-gate tests prove unsafe/malformed checker output does not escape the
route. These tests do not establish hosted Supabase Auth behavior, real provider
quality, medical accuracy or device accessibility.

### Live integration smoke test

On 16 October, 30 Deno tests and 43 Flutter tests passed. Browser UI checks verified the greeting/cards; the final frontend, including signup verification wording and media cache updates, is built and deployed to Firebase Hosting.

The 16 October live synthetic run passed Auth/API access and screened OpenAI (6.62 s), original-voice TTS (4.39 s), STT (2.01 s), WebRTC token issuance (1.90 s), and direct screened custom-LLM bridge output (5.78 s). An actual ElevenLabs WebSocket connection returned its greeting and a matching reply with 159,760 audio bytes, plus an interruption event; the whole connection lasted 10.9 s. End/token revocation and synthetic-account cleanup were verified. These are individual observations, not a latency guarantee. Private-agent auth, custom LLM with no fallback, `record_voice:false` and `retention_days:0` were confirmed in saved configuration.

The realtime test was an ad hoc provider WebSocket check plus WebRTC token issuance. It did **not** exercise browser microphone/WebRTC or a physical phone, and there is no committed realtime smoke script. The commands below run the existing bounded Auth/OpenAI/STT/TTS baseline only.

The 15 October 2026 synthetic run passed CORS, unauthenticated rejection, password sign-in through the hosted Auth API, profile/default-consent checks, staff-access denial, a screened approved OpenAI response, ElevenLabs MP3 synthesis and transcription of that synthetic audio. Cleanup removed the temporary Auth account and app profile and verified their absence.

Use Python 3 and an authenticated Supabase CLI with permission to read project API keys and administer test users. From the repository root:

```sh
# Plan only: no network, keys or accounts accessed.
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app

# Explicitly run against live services.
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app --run
```

Pass `--supabase /path/to/supabase` if the CLI is outside PATH. The script verifies the linked project and keeps Supabase credentials in memory; it never reads OpenAI/ElevenLabs keys. One run normally consumes three OpenAI requests plus one ElevenLabs synthesis and one transcription, with normal provider charges. It uses a random reserved `.invalid` email, explicitly confirms only that synthetic account through Auth Admin, sends no email, leaves global email-confirmation settings unchanged, and keeps all optional app consents off. No caregiver is contacted.

Account cleanup runs on success, failures and normal interruption. An ignored `supabase/.temp/live-smoke-RUN_ID.json` journal contains only the project/run ID and timestamp for recovery after a process or machine crash. To retry cleanup, use the run ID printed by the script:

```sh
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv --cleanup-run RUN_ID
```

Cleanup verifies the account's synthetic marker before deleting it. Keys, session tokens, generated text and audio are never printed or saved. The test verifies backend connectivity and response handling; it does not verify SMTP delivery, registration confirmation links, password-recovery email, Google OAuth, physical camera/microphone/speaker behavior, model accuracy or clinical outcomes.

## Known limits and next work

- Supabase provisioning, provider credentials and Firebase HTTPS deployment are complete for the confirmed project. A synthetic backend test verified hosted password authentication and live OpenAI/ElevenLabs calls. Confirmation remains enabled by the user’s instruction, with email verification reported working by the user. Independent email-delivery tests, Google OAuth and hosted browser/device end-to-end tests remain to do; only Forgot password is hidden.
- The safety classifier/rules are a conservative **unvalidated prototype**, not
  a clinical instrument. English urgency matching can miss wording; exact
  urgency evaluation, latency targets, reviewer staffing and local help
  resources remain release gates. The fixed support response makes no
  external-contact claim. Provider timeouts may take up to 25 seconds per step;
  TRD support-response latency is not yet met.
- Realtime provider WebSocket greeting/reply/audio and interruption-event handling passed. Browser microphone/WebRTC, realistic interruption/reconnect, echo, the 15-minute cap and actual provider deletion still need verification; saved privacy settings alone do not establish deletion timing. Recurring
  medication/routine schedules, push delivery, durable multi-day follow-ups and
  real recipient messaging are not implemented. Current schedules are confirmed
  **one-time** occurrences inside their 24-hour retention window.
- The backend stores no camera frames or face-model assets. Required live
  open-source facial-expression inference belongs to the Flutter/browser media
  implementation; model quality and licence checks are separate.
- Full caregiver invitation/verification, staff MFA enforcement, reviewer case
  assignment operations, correction reports, report retry/acknowledgement
  deadlines and manual-follow-up ownership need completion before a live care
  pilot.
- Real multiweek comparison/cohort metrics, active-minute timing, source-version
  comparisons and aggregate suppression are not implemented. Never use synthetic
  history as measured impact.
- This implementation uses stricter 24-hour incident/report expiry as well as
  24-hour content expiry. Content-free audit is seven days. Account/security
  rows remain until separate account deletion. Provider usage metadata is
  trimmed after 24 hours when new media usage arrives; configure broader
  operational cleanup for a pilot.
- Application `store:false` and no-media-persistence do not establish vendor
  zero retention. Review actual OpenAI/ElevenLabs project retention, processor
  terms, logs and backups before real senior data. Per-account limits exist; an
  operator-wide cost ceiling and abuse controls need configuring with providers
  before public signup.

Provider schemas checked against
[OpenAI Responses](https://developers.openai.com/api/docs/guides/migrate-to-responses),
[structured output](https://developers.openai.com/api/docs/guides/structured-outputs),
[ElevenLabs transcription](https://elevenlabs.io/docs/api-reference/speech-to-text/convert)
and
[speech conversion](https://elevenlabs.io/docs/api-reference/text-to-speech/convert).
`store:false` is an API setting, not a claim about every processor retention
category.

A message can include `selfReportedFeeling`
(happy/sad/worried/calm/mixed/okay/tired; case-insensitive). It is passed
separately from the camera estimate and explicitly takes priority. This
temporary correction is not persisted as a mood observation; mood history
requires its separate consent and endpoint.
