# AIRA backend — controlled prototype

Canonical Supabase project: `yzcnccjlwgrkxokgjtkv`. Firebase: `aira-app-tencent`, hosted at [aira-app-tencent.web.app](https://aira-app-tencent.web.app). Never use the separate aira-mobile-app projects.

Current migrations are core `202610140001`, live sessions `202610160001`, durable/pending text history `202610160002`–`003`, native call archives `202610160004`, scheduled incoming calls `202610160005`, and new-account feature defaults `202610160006`. All app data is protected by owner/role checks and RLS. `aira-api` is the authenticated app API; `aira-worker` handles due database work and bounded transcript recovery. `aira-realtime` is retired and returns 410 for stale custom-LLM clients.

Main text chat uses OpenAI Responses with `gpt-4.1-mini` and buffered safety screening. Live calls use a native **ElevenLabs Agent**, with `deepseek-v41-flash` selected inside ElevenLabs, Scribe Realtime and Jessica/Flash v2. Calls never forward to AIRA's OpenAI endpoint; the native agent prompt/provider behavior replaces the text route's pre-release classifier for calls. Thinking filler is disabled. Separate approved-text playback retains voice `La9lzDJ3mmfNhhQA06WM`, `eleven_multilingual_v2`, and bounded `scribe_v2` transcription.

Email verification stays enabled by the user's 16 October instruction and is reported working by the user. Only Forgot password is hidden. New passwords require 10 characters. Google OAuth and independent email-delivery testing remain incomplete. Auth redirects/CORS allow the exact local and correct Firebase origins. There is no external caregiver messaging adapter.

Historical hosted checks verified password Auth, CORS, authorization denial, worker execution and the earlier provider paths. New source behavior and current live checks must be reported separately; physical microphone/phone acceptance is not established by generated audio.

The backend accepts Supabase's injected modern `SUPABASE_SECRET_KEYS` dictionary (default key), older `SUPABASE_SECRET_KEY`, or legacy `SUPABASE_SERVICE_ROLE_KEY`. Optional `AIRA_SUPABASE_SECRET_KEY_NAME` selects a named dictionary key. Modern secret keys are sent in `apikey`, while Auth verification retains the user's Bearer token.

## What is implemented

- Supabase Auth identity is checked server-side for every API request.
  Email/password and Google sign-in are configured through Supabase, not a
  parallel password database.
- Owner-scoped database reads, denied direct writes, server-managed staff
  assignments, verified caregiver links, audited protected dashboard access.
  User-editable Auth metadata never grants a role.
- Reviewable feature choices, confirmed memories, one-time medication/plan reminders,
  a separately chosen daily companion-call schedule, explicit acceptance/decline,
  medication Taken/Skip/Snooze self-reports and durable saved text/call archives.
  New profiles default all eleven feature flags on; existing choices stay unchanged.
  Other prototype categories retain their separate 24-hour expiry.
- OpenAI Responses requests with an explicit environment-selected model and
  `store:false`. Replies are buffered and screened using strict structured
  output before release. Invalid/unavailable screening substitutes fixed support
  copy; unchecked replies are not displayed or spoken.
- A private native ElevenLabs agent and short-lived WebRTC connection tokens. The
  server reserves owner-bound calls and nonces; no custom LLM payload or OpenAI call
  processing remains. Call transcripts are saved separately from the text thread,
  using validated provider transcripts with device captions as a labelled fallback.
  See the [live-call guide](../app/web/media/REALTIME-CALLS.md).
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

## Native ElevenLabs voice setup

Flutter uses the locally bundled `@elevenlabs/client` **1.28.0** browser SDK, with `webRtc.singlePeerConnection=false` for the reproduced WebKit negotiation issue. The provider runs the entire live conversation in its native Agents service. The source of the interaction prompt/configuration is [`functions/_shared/voice_agent.ts`](functions/_shared/voice_agent.ts): `deepseek-v41-flash`, Jessica (`cgSgspJ2msm6clMCkdW9`), Scribe Realtime, `eleven_flash_v2`, normal turn-taking, 900-second cap and a dynamic first greeting. The soft-timeout thinking cue is disabled (`timeout_seconds:-1`) and the prompt also forbids repeated thinking filler. Backup LLM selection is disabled; `custom_llm` is null.

Apply all migrations and deploy the app/worker functions. Live calls require server-side `ELEVENLABS_API_KEY` and `ELEVENLABS_AGENT_ID`. Agent setup also uses `ELEVENLABS_REALTIME_VOICE_ID`; ordinary playback uses its separate `ELEVENLABS_VOICE_ID`. OpenAI remains necessary for text chat only. Old `AIRA_CALL_SIGNING_SECRET` / `AIRA_REALTIME_BRIDGE_SECRET` values are not required by native calls; remove obsolete provider custom-LLM configuration during migration. Deploy the retired `aira-realtime` response when replacing an existing environment so old clients cannot continue using its OpenAI bridge.

`aira-voice-setup` is a temporary infrastructure helper:

1. Deploy it explicitly after configuring the existing `AIRA_WORKER_SECRET` and ElevenLabs key/voice secrets.
2. POST `{"action":"configure-native"}` with `x-aira-worker-secret` supplied securely in process memory. The helper updates `ELEVENLABS_AGENT_ID` if present, otherwise creates an agent. Save a newly returned ID in Edge Function secrets.
3. POST `{"action":"inspect"}` to read back sanitized model, voice, auth, fallback, first-message and privacy settings. Confirm the native model, `hasCustomLlm:false`, authentication on and thinking timeout disabled. No API keys are returned.
4. Remove the helper deployment with `supabase functions delete aira-voice-setup --project-ref YOUR_PROJECT_REF`. The checked-in helper source remains available for future deliberate updates.

Do not place the worker key in browser code, logs, command history or Git. The prompt is saved in ElevenLabs itself, so the agent can also be inspected in its dashboard; keep reviewed changes synchronized with `voice_agent.ts`.

The requested provider privacy configuration is `record_voice:false`, `retention_days:0`, `delete_transcript_and_pii:true`, `delete_audio:true`, `zero_retention_mode:false`. This requests scheduled deletion, not instant deletion or zero logging. The archive worker attempts to recover a completed transcript before provider deletion; device captions are a labelled fallback if the provider copy is unavailable. Verify actual provider account policy and deletion behavior independently. [ElevenLabs retention guidance](https://elevenlabs.io/docs/eleven-agents/customization/privacy/retention).

The call starts only after an outgoing-call action or acceptance of a scheduled incoming invitation. Flutter receives a short-lived conversation token and dynamic variables for the preferred name, greeting, call ID and random binding nonce. The provider's stored initiation data must match the configured agent, call ID and nonce before canonical transcript text is accepted. Call identifiers alone never authorize access to another person's transcript.

End stops local media immediately and closes server state. SDK captions are persisted under the owner while conversation saving remains enabled. A bounded worker later fetches at most five completed-call transcripts concurrently, retries at most ten times, and retires stale consent versions without recreating deleted rows. Individual transcript deletion, storage opt-out and account-data deletion prevent late recovery from restoring removed content.

Video combines native live audio, animated Aira and the optional local camera. face-api.js 0.22.2 runs locally; images are never uploaded. Fresh permitted expression labels and optional self-reported feelings can be transient native-agent context, with self-report taking priority. This is not a remote human or generated video feed. The separate protected call-context endpoint remains available for transient bookkeeping; it does not forward to OpenAI.

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

The worker creates database events, writes `test_delivered` to an authenticated
internal inbox and performs bounded ElevenLabs transcript recovery. There is
**no** email/SMS/webhook recipient destination or external caregiver messaging adapter. The outbox's `external_delivery` database
constraint is always false. A missing/revoked recipient prevents delivery; it
never picks someone else.

A minute-based Cron can add roughly a minute before an event is created. Foreground polling finds it; scheduled-call polling also generates the due invitation if Cron is late. This is **not** a dependable medication alarm or a background/phone incoming-call service.

Owner-chosen daily calls are separate from optional social invitations. The app currently chooses Singapore time (`Asia/Singapore`); the backend validates and preserves the selected IANA timezone, including daylight-saving transitions. No schedule exists until the owner chooses a time. A scheduled ring lasts two minutes from its due time; a late worker, expired ring or owner already in a live call becomes missed. Acceptance/decline is versioned and deduplicated, and only an accepted invitation can atomically reserve one voice call. Aira speaks first. Declining one occurrence does not cancel tomorrow's schedule. Pausing/editing cancels outstanding invitations; deleting removes the schedule. This explicit chosen time is honored independently of social quiet hours/caps. The app must stay open and visible; closed tabs and sleeping devices do not ring.

Ordinary social invitations still use their earlier 30-second lifetime, 09:00–21:00 stored-timezone hours, one-per-day cap and 24-hour decline pause. Medication occurrences remain separate. Physical expiry cleanup depends on Cron; exposed content reads also filter expiry. Inspect failures without logging message bodies. [Supabase scheduling guide](https://supabase.com/docs/guides/functions/schedule-functions).

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
| `GET /v1/history?before=<cursor>` | Owner-only saved text-chat messages, oldest-to-newest within each 50-message page; excludes voice/video. Returns `{messages,nextCursor,conversationId,privacyVersion}`; omit `before` for the latest page. |
| `DELETE /v1/history` | Deletes owned text-chat history and invalidates old context versions; returns `{deleted,privacyVersion}`. Call archives, memories and reminder controls remain separate. |
| `POST /v1/messages`                              | `{clientMessageId,text,mode,conversationId?,contextVersion?,context?:[{role,text}],introductionShown?,cueSummary?:{label,observedAt},selfReportedFeeling?}`. Returns `{conversationId,messageId,text,status,speechToken,privacyVersion,provider}`. Text mode only: max 2,000 characters, 10 submissions/minute and 20/hour/account; call turns do not consume these counters. Failed logical requests can retry with the same ID and a refreshed processing deadline. `status` is approved/support/safe_fallback. |
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
| `POST /v1/calls/session` | `{mode:'voice' or 'video',invitationId?}` → `{conversationId,conversationToken,dynamicVariables,expiresAt}`. Native ElevenLabs session; dynamic variables contain greeting/name/call binding. An incoming `invitationId` must be accepted, owned, unexpired and unused. No provider API key or custom LLM payload is returned. |
| `GET /v1/calls/history?before=<cursor>` | Separate owner-only call summaries, newest-first, 20/page: `{calls,nextCursor,privacyVersion}`. |
| `GET /v1/calls/:id/transcript` | `{call,messages,privacyVersion}` with labelled transcript source; may attempt one bounded provider recovery. |
| `POST /v1/calls/:id/transcript` | `{providerConversationId,entries:[{role,text,timeInCallSecs}]}`. Stores owner-bound device captions only if current saving permission permits. Canonical provider text is verified separately. |
| `DELETE /v1/calls/:id/transcript` | `{deleted:true}`; removes that archive and legacy call messages; late recovery cannot recreate it. |
| `GET /v1/call-schedule` | `{schedule,incomingCall,foregroundOnly:true}`. `schedule` is null or `{id,localTime,timeZone,enabled,version,nextCallAt}`. An incoming call includes ID, version, state, scheduled/expiry timestamps. |
| `PATCH /v1/call-schedule` | `{localTime:'HH:mm',timeZone,enabled,expectedVersion?}`. Create without version; existing schedule requires its current version. Returns updated schedule/incoming state. |
| `DELETE /v1/call-schedule` | JSON `{expectedVersion}`. Removes the owner schedule and pending invitations. |
| `POST /v1/scheduled-calls/:id/respond` | `{action:'accept' or 'decline',requestId,expectedVersion}` → `{invitation,startCall}`. A successful acceptance is followed by `/calls/session` with that invitation ID; start reservation is atomic and single use. |
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
`urgent_sharing`, `reviewed_sharing`, `admin_insights`. Migration `202610160006` defaults all eleven flags to true for new profiles, and onboarding visibly lets users change them. Existing account choices are not rewritten. Defaults do not provision roles, verify recipients, choose schedules or bypass browser device permissions. Flutter
aliases are `store_conversations`, `memory_enabled`, `monitoring_enabled`,
`impact_measurement`; other names stay unchanged. Unknown/role fields are
rejected. Changes invalidate speech tokens. Withdrawal purges category content
and blocks queued access.

Saved text chat and separate call transcripts persist until their respective deletion controls, conversation-saving opt-out, or account-data deletion. Clearing main text history does not delete call archives. Migration `202610160002_durable_history.sql` preserves only unexpired messages from owners who already opted in; previously expired/deleted content cannot be recovered. Their parent conversation and request records share durable retention to prevent cascading expiry. Migration `202610160003_pending_history.sql` also saves an opted-in user message before provider processing, so reopening during a reply restores it as Delivered. A recent pending reply is checked again until completion; only an actual saved reply changes it to Read. Other prototype categories keep their existing lifetimes. Conversation activity in the current dashboard is still limited to its 24-hour measurement window.

Account bootstrap restores the latest 50 saved messages and the active text thread. Earlier messages are loaded using an exclusive sequence cursor; new messages and equal timestamps cannot shift older pages. Migration `202610160004` moves the presentation of earlier saved voice/video messages into Settings → Call history; new calls are archived there directly. They do not appear in the main text timeline or its model context. Starting or ending a call does not clear the text history. Owner checks and RLS apply, and account/consent changes reject late history responses. The client keeps provider playback tokens only in memory, never in persisted history. The interface preview has no live replies and does not create a fake saved conversation.

Without conversation storage, the client sends at most ten recent turns with
**`contextVersion == profile.consent_version`**; the server persists no
transcript. Clear that buffer on logout, account change and conversation deletion. Memory edit/forget increments the privacy version: existing history stays visible, but older-version turns are omitted from future model context by both client and server. A completed duplicate request can return `text:null` in
no-storage mode because the server cannot reconstitute a deleted reply; retain
the original response in the active client buffer, or invite an explicit fresh
message. Do not silently submit a new ID to retry a completed request. Provider
storage controls remain independent of AIRA's database storage toggle.

## Protected care views

Open **Settings → Care connections → Caregiver view / Admin dashboard** (or desktop sidebar buttons). The screen is reachable without granting access; signed-in data still needs a verified link or staff assignment. **Explore the interface** exposes synthetic examples without account privileges.

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
are returned. Conversation count requires a completed saved text reply or captured call turns; senior/AIRA
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

### Live integration smoke tests

Current native-call release verification (16 October 2026): **72 Flutter tests and 42 Deno tests passed**, plus both JavaScript media lifecycle suites and a connected release web build. Supabase migrations004–006 and API/worker/retired-bridge functions are deployed; Firebase Hosting `aira-app-tencent` is updated. The private native agent settings were read back with `deepseek-v41-flash`, Jessica, no custom LLM or fallback, auth enabled and thinking filler disabled. A real browser WebRTC run with generated speech recognized the input and returned a spoken reply (16.1seconds for the entire fixture, not a response-latency benchmark). It then recovered the canonical provider transcript with ownership validation, verified that main text history contained no call turns, and sent a successful text message after hangup. A separate cloud check produced an invitation at the selected minute, accepted it and obtained a native session with Aira's scheduled opening greeting. Test accounts were removed and cleanup verified; the temporary setup function was deleted. Physical-device acceptance remains pending.

Historical 16 October checks of the earlier custom-LLM release passed 34 Deno and 59 Flutter tests, persisted text after browser-tab reopening and passed generated-speech WebRTC recognition/reply after the supported SDK compatibility fix. Earlier provider WebSocket/bridge timings and token checks belong to that retired architecture; they are not validation of the new native agent. Current release evidence should state which code/configuration was exercised.

The committed [`scripts/smoke_browser_audio.py`](../scripts/smoke_browser_audio.py) harness tests real browser WebRTC using generated speech, with no physical microphone/camera. See [the live-call guide](../app/web/media/REALTIME-CALLS.md). The separate baseline below tests Auth, screened OpenAI text and ordinary ElevenLabs STT/TTS:

```sh
# Plan only: no network, keys or accounts accessed.
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app

# Live synthetic test; normal provider charges apply.
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv \
  --origin https://aira-app-tencent.web.app --run
```

Use Python 3 and an authenticated Supabase CLI with test-user administration access; pass `--supabase /path/to/supabase` if needed. The linked project is checked and credentials remain in memory. The baseline verifies all new-account feature defaults, explicitly disables optional flags on the synthetic account, then makes one text request (normally three OpenAI requests), one synthesis and one transcription. It sends no email, preserves global verification settings and contacts no caregiver.

Cleanup runs on success, failures and normal interruption. An ignored `supabase/.temp/live-smoke-RUN_ID.json` journal holds only the project/run ID and timestamp. After a machine/process crash:

```sh
python3 scripts/smoke_live.py --project-ref yzcnccjlwgrkxokgjtkv --cleanup-run RUN_ID
```

Cleanup verifies synthetic identity markers before deletion. Keys, session tokens, generated text and audio are never printed or saved. These checks do not establish SMTP/verification delivery, Google OAuth, physical device behavior, clinical accuracy or production readiness.

## Known limits and next work

- Supabase provisioning, provider credentials and Firebase HTTPS deployment are complete for the confirmed project. A synthetic backend test verified hosted password authentication and live OpenAI/ElevenLabs calls. Confirmation remains enabled by the user’s instruction, with email verification reported working by the user. Independent email-delivery tests, Google OAuth and hosted browser/device end-to-end tests remain to do; only Forgot password is hidden.
- The safety classifier/rules are a conservative **unvalidated prototype**, not
  a clinical instrument. English urgency matching can miss wording; exact
  urgency evaluation, latency targets, reviewer staffing and local help
  resources remain release gates. The fixed support response makes no
  external-contact claim. Provider timeouts may take up to 25 seconds per step;
  TRD support-response latency is not yet met. This buffered classifier belongs to
  text chat; native live calls do not pass through it or automatically create its
  incident records. Native prompt instructions are not proven monitoring/prevention.
- Native-agent and physical-device behavior need separate verification, including
  realistic interruptions, echo, the 15-minute cap and actual provider deletion.
  Saved settings do not establish deletion timing. Owner-chosen daily companion
  calls are implemented as foreground invitations; recurring medication/routine
  schedules, push/background calls and real recipient messaging remain absent.
  Medication and plan schedules still use confirmed one-time 24-hour occurrences.
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
  24-hour expiry for memories, reminders and wellbeing content. Opted-in conversation history instead lasts until deleted as described above. Content-free audit is seven days. Account/security
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
