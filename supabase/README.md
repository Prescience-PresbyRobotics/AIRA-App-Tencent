# AIRA backend — controlled prototype

Implemented 14 October; deployed to the confirmed AIRA-App-Tencent Supabase project on 15 October 2026. Project `yzcnccjlwgrkxokgjtkv` has migration `202610140001`, 16 RLS-protected app tables, `aira-api`, `aira-worker`, private worker/signing secrets and a minute-based Cron job. Hosted authentication rejection, localhost CORS and authenticated worker execution were verified. **Live provider calls, end-to-end user login, Google OAuth and external email sender setup remain unverified.** There is no external caregiver delivery adapter.

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
- ElevenLabs transcription and speech. Speech requires a signed five-minute
  approved-reply token bound to account, request and current consent version.
  The API accepts no arbitrary text-to-speech request.
- Transactional request/occurrence/action deduplication; automatic urgent
  **internal test** reports; nonurgent report approval by an assigned reviewer.
  Test delivery, acknowledgement and case resolution are separate states.
- Optional dated seven-day loneliness question (0–7 or Skip), separate
  self-reported feelings, and the same descriptive insights response for
  permitted owners/caregivers/admins.

## Set up your projects

1. Create a Supabase project for **development/testing**, choose a region
   deliberately, and record its project reference and URL. Keep its database
   password private.
2. In Auth, enable email/password, email confirmation and password recovery.
   Configure your own SMTP sender before public registration. Keep anonymous
   sign-in disabled for this implementation.
3. Create a Google OAuth web client in Google Cloud. Configure its consent
   screen, permitted audience and test accounts. Use the exact Supabase callback
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
`config.toml` uses `http://localhost:8080`; run Flutter on that origin or update
both the allowed origins and Auth redirects.

After creating your **test** cloud project, apply the reviewed migration and
functions:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set --env-file supabase/.env
supabase functions deploy aira-api
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
| `POST /v1/messages`                              | `{clientMessageId,text,mode,conversationId?,contextVersion?,context?:[{role,text}],cueSummary?:{label,observedAt},selfReportedFeeling?}`. Returns `{conversationId,messageId,text,status,speechToken,privacyVersion,provider}`. Max 2,000 characters, 10 submissions/minute and 20/hour/account. `status` is approved/support/safe_fallback. |
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
deno check supabase/functions/aira-api/index.ts supabase/functions/aira-worker/index.ts
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

## Known limits and next work

- Supabase provisioning is complete for the confirmed project. Email/Google callbacks, provider credentials, Firebase HTTPS deployment and end-to-end device testing remain to do. No live provider calls have been verified.
- The safety classifier/rules are a conservative **unvalidated prototype**, not
  a clinical instrument. English urgency matching can miss wording; exact
  urgency evaluation, latency targets, reviewer staffing and local help
  resources remain release gates. The fixed support response makes no
  external-contact claim. Provider timeouts may take up to 25 seconds per step;
  TRD support-response latency is not yet met.
- Continuous ElevenLabs calls, interruptions/reconnect, recurring
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
