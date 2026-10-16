import {
  ApiError,
  boundedText,
  exactOrigin,
  outputAllowed,
  preferences,
  qualifiesUrgent,
  SAFE_FALLBACK,
  safeContext,
  signSpeech,
  SUPPORT_REPLY,
  uuid,
  verifySpeech,
  weeklyPeriod,
} from "../_shared/domain.ts";
import {
  authenticate,
  Database,
  type Env,
  env,
  jsonBody,
  supabaseServerKey,
} from "../_shared/runtime.ts";
import { FIRST_GREETING, Providers } from "../_shared/providers.ts";
import {
  callContext,
  conversationToken,
  realtimeConfigured,
  signCall,
} from "../_shared/realtime.ts";
const consentAliases: Record<string, string> = {
  store_conversations: "conversation_storage",
  memory_enabled: "memory",
  social_reminders: "social_reminders",
  medication_reminders: "medication_reminders",
  impact_measurement: "impact",
  monitoring_enabled: "monitoring",
  face_cues: "face_cues",
  mood_history: "mood_history",
  urgent_sharing: "urgent_sharing",
  reviewed_sharing: "reviewed_sharing",
  admin_insights: "admin_insights",
};
const nowFilter = () => encodeURIComponent(new Date().toISOString());
const owned = (user: string) =>
  `user_id=eq.${user}&expires_at=gt.${nowFilter()}`;
const requireConsent = (profile: any, key: string) => {
  if (profile.consents[key] !== true) {
    throw new ApiError(
      403,
      "consent_required",
      `Enable ${key.replaceAll("_", " ")} in Settings first.`,
    );
  }
};
function clientPreferences(p: any) {
  return {
    ...Object.fromEntries(
      Object.entries(consentAliases).map((
        [a, b],
      ) => [a, p.consents[b] === true]),
    ),
    onboarded: p.onboarded,
    text_scale: Number(p.text_scale),
    reduced_motion: p.reduced_motion,
  };
}
function adaptPreferences(body: Record<string, any>) {
  const patch: Record<string, any> = {};
  const consents = { ...body.consents };
  for (const [key, value] of Object.entries(body)) {
    if (consentAliases[key]) consents[consentAliases[key]] = value;
    else if (key === "locale") {
      if (value !== "en") {
        throw new ApiError(
          400,
          "english_only",
          "The first version supports English.",
        );
      }
    } else if (key !== "consents") patch[key] = value;
  }
  if (Object.keys(consents).length) patch.consents = consents;
  return preferences(patch);
}
function capability(get: Env) {
  return {
    text: !!get("OPENAI_API_KEY") && !!get("OPENAI_MODEL"),
    voice: !!get("ELEVENLABS_API_KEY") && !!get("ELEVENLABS_VOICE_ID") &&
      get("AIRA_SPEECH_SIGNING_SECRET").length >= 32,
    continuousVoice: realtimeConfigured(get),
    externalCaregiverDelivery: false,
    reminders: "foreground_only",
    retentionHours: 24,
    conversationRetention: "until_deleted",
    language: "en",
  };
}
function conflict(rows: any[]) {
  if (!rows.length) {
    throw new ApiError(
      409,
      "state_conflict",
      "This item changed or expired. Refresh and try again.",
    );
  }
  return rows[0];
}
function version(body: any) {
  if (!Number.isInteger(body.expectedVersion) || body.expectedVersion < 1) {
    throw new ApiError(
      400,
      "version_required",
      "The current item version is required.",
    );
  }
  return body.expectedVersion;
}
function base64(bytes: Uint8Array) {
  let text = "";
  for (let i = 0; i < bytes.length; i += 8192) {
    text += String.fromCharCode(...bytes.subarray(i, i + 8192));
  }
  return btoa(text);
}

function nextLocalTime(value: unknown, timeZone: string): string {
  if (typeof value !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(value)) {
    throw new ApiError(400, "invalid_time", "Choose a time for the reminder.");
  }
  const format = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  });
  const start = Math.ceil(Date.now() / 60000) * 60000;
  for (let i = 1; i < 1440; i++) {
    const d = new Date(start + i * 60000);
    if (format.format(d) === value) return d.toISOString();
  }
  throw new ApiError(
    400,
    "invalid_time",
    "Choose a time within the next 24 hours.",
  );
}

export function createHandler(
  get: Env = env,
  fetcher: typeof fetch = fetch,
  resolveUser = authenticate,
) {
  return async function handler(req: Request): Promise<Response> {
    const requestId = crypto.randomUUID();
    const origin = req.headers.get("origin");
    const allowed = get("AIRA_ALLOWED_ORIGINS").split(",").map((x) => x.trim())
      .filter(Boolean);
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
      "Vary": "Origin",
      "X-Content-Type-Options": "nosniff",
    };
    if (origin && exactOrigin(origin, allowed)) {
      headers["Access-Control-Allow-Origin"] = origin;
    }
    const respond = (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), { status, headers });
    try {
      if (!exactOrigin(origin, allowed)) {
        throw new ApiError(
          403,
          "origin_denied",
          "This app address is not allowed.",
        );
      }
      if (req.method === "OPTIONS") {
        return new Response(null, {
          status: 204,
          headers: {
            ...headers,
            "Access-Control-Allow-Headers":
              "authorization, apikey, content-type, x-client-info",
            "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
            "Access-Control-Max-Age": "600",
          },
        });
      }
      const user = await resolveUser(req, get, fetcher);
      const db = new Database(
        get("SUPABASE_URL"),
        supabaseServerKey(get),
        fetcher,
      );
      const p = await db.one("profiles", `id=eq.${user}&enabled=eq.true`);
      if (!p) {
        throw new ApiError(
          403,
          "account_disabled",
          "This account is unavailable.",
        );
      }
      const url = new URL(req.url);
      const path = url.pathname.replace(/^.*\/aira-api/, "");
      const method = req.method;
      const live = new Providers(get, fetcher);
      const audit = async (action: string, subject = user) =>
        await db.insert("audit_events", {
          actor_id: user,
          subject_id: subject,
          action,
        });
      async function role(roleName: string, subject?: string) {
        const r = await db.one(
          "role_assignments",
          `user_id=eq.${user}&role=eq.${roleName}&enabled=eq.true${
            subject ? `&subject_id=eq.${uuid(subject)}` : ""
          }`,
        );
        if (!r) {
          throw new ApiError(
            403,
            "role_required",
            "You do not have access to this view.",
          );
        }
        return r;
      }
      async function readInsights(
        subject: string,
        categories = ["loneliness", "conversations", "mood"],
      ) {
        const profile = await db.one(
          "profiles",
          `id=eq.${subject}&enabled=eq.true`,
        );
        if (!profile) {
          throw new ApiError(404, "not_found", "This profile is unavailable.");
        }
        const permitted = categories.filter((c) =>
          c === "mood"
            ? profile.consents.mood_history === true
            : profile.consents.impact === true
        );
        const [prompts, responses, conversations, mood] = await Promise.all([
          permitted.includes("loneliness")
            ? db.request(
              `measurement_prompts?${owned(subject)}&order=period_start.asc`,
            )
            : [],
          permitted.includes("loneliness")
            ? db.request(`loneliness_responses?${owned(subject)}`)
            : [],
          permitted.includes("conversations")
            ? db.request(
              `conversations?${
                owned(subject)
              }&completed=eq.true&accepted_at=gt.${
                encodeURIComponent(
                  new Date(Date.now() - 86400000).toISOString(),
                )
              }`,
            )
            : [],
          permitted.includes("mood")
            ? db.request(
              `mood_observations?${owned(subject)}&order=created_at.asc`,
            )
            : [],
        ]);
        const periods = prompts.map((prompt: any) => ({
          ...prompt,
          response: responses.find((r: any) => r.prompt_id === prompt.id) ??
            null,
        }));
        return {
          subjectId: subject,
          definitionVersion: "aira-impact-v1",
          synthetic: false,
          generatedAt: new Date().toISOString(),
          retentionHours: 24,
          categories: permitted,
          loneliness: {
            periods,
            baseline: periods.find((x: any) =>
              x.response && !x.response.skipped
            ) ?? null,
            changeFromBaseline: null,
            changeFromPrevious: null,
            note:
              "Prototype data expires after 24 hours. No multiweek benefit is measured.",
          },
          conversations: {
            count: conversations.length,
            seniorInitiated: conversations.filter((x: any) =>
              x.initiator === "senior"
            ).length,
            airaInitiated: conversations.filter((x: any) =>
              x.initiator === "aira"
            ).length,
            durationMinutes: null,
            durationStatus: "Timing instrumentation not implemented",
          },
          mood: {
            selfReported: mood,
            inferred: [],
            inferredStatus: "Live camera estimates are not stored",
          },
          supportedSeniors: conversations.length ? 1 : 0,
        };
      }
      if (path === "/v1/me" && method === "GET") {
        return respond({
          profile: p,
          preferences: clientPreferences(p),
          capabilities: capability(get),
          roles: await db.request(
            `role_assignments?user_id=eq.${user}&enabled=eq.true`,
          ),
        });
      }
      if (path === "/v1/preferences" && method === "PATCH") {
        const updated = await db.rpc("aira_preferences", {
          p_user: user,
          p_patch: adaptPreferences(await jsonBody(req)),
        });
        return respond({
          profile: updated,
          preferences: clientPreferences(updated),
        });
      }
      if (path === "/v1/me/data" && method === "DELETE") {
        await db.rpc("aira_purge", { p_user: user });
        return respond({
          deleted: true,
          accountDeleted: false,
          message:
            "App access disabled and application content removed. Supabase Auth identity remains; administrator deletion is a separate action.",
        });
      }
      if (path === "/v1/history" && method === "GET") {
        const before = url.searchParams.get("before");
        if (
          before !== null &&
          (!/^[1-9]\d{0,18}$/.test(before) ||
            BigInt(before) > 9223372036854775807n)
        ) {
          throw new ApiError(
            400,
            "invalid_cursor",
            "Please refresh your conversation history.",
          );
        }
        return respond(
          await db.rpc("aira_chat_history", {
            p_user: user,
            p_before: before,
            p_limit: 50,
          }),
        );
      }
      if (path === "/v1/history" && method === "DELETE") {
        const privacyVersion = await db.rpc("aira_clear_chat_history", {
          p_user: user,
        });
        return respond({ deleted: true, privacyVersion });
      }
      const messageStatus = path.match(/^\/v1\/messages\/([^/]+)\/status$/);
      if (messageStatus && method === "GET") {
        const request = await db.one(
          "message_requests",
          `user_id=eq.${user}&client_id=eq.${
            uuid(messageStatus[1])
          }&expires_at=gt.${nowFilter()}`,
        );
        return respond({
          status: request?.status ?? "not_found",
          createdAt: request?.created_at ?? null,
        });
      }
      if (path === "/v1/messages" && method === "POST") {
        const b = await jsonBody(req);
        const text = boundedText(b.text);
        let selfReportedFeeling: string | undefined;
        if (
          b.selfReportedFeeling !== undefined && b.selfReportedFeeling !== null
        ) {
          if (
            typeof b.selfReportedFeeling !== "string" ||
            !["happy", "sad", "worried", "calm", "mixed", "okay", "tired"]
              .includes(b.selfReportedFeeling.toLowerCase())
          ) {
            throw new ApiError(
              400,
              "invalid_feeling",
              "Choose one of the available feelings.",
            );
          }
          selfReportedFeeling = b.selfReportedFeeling.toLowerCase();
        }
        const mode = b.mode ?? "text";
        if (!["text", "voice", "video"].includes(mode)) {
          throw new ApiError(400, "invalid_mode", "Invalid conversation mode.");
        }
        const reserved = await db.rpc("aira_reserve_message", {
          p_user: user,
          p_client: uuid(b.clientMessageId, "clientMessageId"),
          p_conversation: b.conversationId ? uuid(b.conversationId) : null,
          p_mode: mode,
        });
        const r = reserved.request;
        if (reserved.duplicate) {
          const saved = await db.one(
            "messages",
            `request_id=eq.${r.id}&user_id=eq.${user}&role=eq.assistant&approved=eq.true&expires_at=gt.${nowFilter()}`,
          );
          return respond({
            conversationId: r.conversation_id,
            messageId: r.id,
            text: saved?.text ?? null,
            status: r.status,
            duplicate: true,
            speechToken: null,
          }, r.status === "processing" ? 202 : 200);
        }
        if (p.consents.conversation_storage) {
          const saved = await db.rpc("aira_save_message_input", {
            p_user: user,
            p_request: r.id,
            p_input: text,
            p_consent_version: p.consent_version,
          });
          if (!saved) {
            throw new ApiError(
              409,
              "preferences_changed",
              "Your privacy choices changed. Please send your message again.",
            );
          }
        }
        let answer = SAFE_FALLBACK;
        let status = "safe_fallback";
        let inputFlag: any = null;
        let outputFlag: any = null;
        let candidate = "";
        try {
          inputFlag = await live.screen(text, "user");
          if (inputFlag.concern === "self_harm") {
            answer = SUPPORT_REPLY;
            status = "support";
          } else {
            // After forgetting a memory, prior context is not accepted: every memory edit bumps consent_version.
            // Client context is allowed only when it names the current privacy version.
            let context = b.contextVersion === p.consent_version
              ? safeContext(b.context)
              : [];
            if (p.consents.conversation_storage) {
              const history = await db.request(
                `messages?user_id=eq.${user}&conversation_id=eq.${r.conversation_id}&expires_at=gt.${nowFilter()}&context_version=eq.${p.consent_version}&request_id=neq.${r.id}&order=history_order.desc&limit=10`,
              );
              context = history.reverse().map((m: any) => ({
                role: m.role,
                content: m.text,
              }));
            }
            if (!context.length && b.introductionShown === true) {
              context = [{ role: "assistant", content: FIRST_GREETING }];
            }
            const memories = p.consents.memory
              ? await db.request(
                `memories?${
                  owned(user)
                }&confirmed=eq.true&order=created_at.desc&limit=20`,
              )
              : [];
            let cue: string | undefined;
            if (
              p.consents.face_cues && b.cueSummary &&
              typeof b.cueSummary.label === "string" &&
              [
                "neutral",
                "happy",
                "sad",
                "angry",
                "fearful",
                "disgusted",
                "surprised",
                "unknown",
              ].includes(b.cueSummary.label) &&
              Math.abs(Date.now() - Date.parse(b.cueSummary.observedAt)) < 15000
            ) {
              cue = b.cueSummary.label;
            }
            candidate = await live.reply(
              [...context, { role: "user", content: text }],
              memories.map((m: any) => m.text),
              cue,
              selfReportedFeeling,
              p.display_name,
            );
            outputFlag = await live.screen(candidate, "assistant");
            if (outputAllowed(outputFlag)) {
              answer = boundedText(candidate, 4000);
              status = "approved";
            }
          }
        } catch {
          /* Fail closed. Never include unchecked provider output in responses, logs or TTS. */
        }
        if (inputFlag && inputFlag.concern !== "none") {
          await db.rpc("aira_incident", {
            p_user: user,
            p_request: r.id,
            p_source: "user",
            p_reason: inputFlag.concern,
            p_excerpt: text,
            p_priority: qualifiesUrgent(inputFlag, text) ? "urgent" : "review",
            p_synthetic: false,
          });
        }
        if (outputFlag && !outputAllowed(outputFlag)) {
          await db.rpc("aira_incident", {
            p_user: user,
            p_request: r.id,
            p_source: "assistant",
            p_reason: outputFlag.concern,
            p_excerpt: candidate,
            p_priority: "review",
            p_synthetic: false,
          });
        }
        const finished = await db.rpc("aira_finish_message", {
          p_user: user,
          p_request: r.id,
          p_input: text,
          p_output: answer,
          p_consent_version: p.consent_version,
        });
        if (!finished) {
          throw new ApiError(
            409,
            "preferences_changed",
            "Your privacy choices changed. Please send your message again.",
          );
        }
        let speechToken: string | null = null;
        if (get("AIRA_SPEECH_SIGNING_SECRET").length >= 32) {
          speechToken = await signSpeech({
            user,
            version: p.consent_version,
            requestId: r.id,
            text: answer,
            exp: Date.now() + 300000,
          }, get("AIRA_SPEECH_SIGNING_SECRET"));
        }
        return respond({
          conversationId: r.conversation_id,
          messageId: r.id,
          text: answer,
          status,
          speechToken,
          privacyVersion: p.consent_version,
          provider: status === "approved"
            ? "openai"
            : "local_reviewed_fallback",
        });
      }
      if (path === "/v1/audio/transcriptions" && method === "POST") {
        const b = await jsonBody(req, 8000000);
        if (
          typeof b.audioBase64 !== "string" || b.audioBase64.length > 7000000
        ) {
          throw new ApiError(
            413,
            "audio_too_large",
            "Please record a shorter message.",
          );
        }
        b.mimeType = typeof b.mimeType === "string"
          ? b.mimeType.split(";")[0].trim().toLowerCase()
          : "";
        if (
          !["audio/webm", "audio/mp4", "audio/wav", "audio/ogg", "audio/mpeg"]
            .includes(b.mimeType)
        ) {
          throw new ApiError(
            400,
            "audio_format",
            "This audio format is unsupported.",
          );
        }
        let bytes: Uint8Array;
        try {
          bytes = Uint8Array.from(atob(b.audioBase64), (c) => c.charCodeAt(0));
        } catch {
          throw new ApiError(
            400,
            "invalid_audio",
            "The recording could not be read.",
          );
        }
        if (bytes.length > 5000000 || !bytes.length) {
          throw new ApiError(
            413,
            "audio_too_large",
            "Record up to 5 MB per turn.",
          );
        }
        await db.rpc("aira_media_limit", {
          p_user: user,
          p_kind: "transcription",
        });
        const text = await live.transcribe(
          new File([bytes.slice().buffer], `turn.${b.mimeType.split("/")[1]}`, {
            type: b.mimeType,
          }),
        );
        bytes.fill(0);
        return respond({ text, editable: true, provider: "elevenlabs" });
      }
      if (path === "/v1/speech" && method === "POST") {
        const b = await jsonBody(req);
        const token = boundedText(b.speechToken, 14000, "speechToken");
        const approved = await verifySpeech(
          token,
          get("AIRA_SPEECH_SIGNING_SECRET"),
          user,
          p.consent_version,
        );
        const r = await db.one(
          "message_requests",
          `id=eq.${approved.requestId}&user_id=eq.${user}&status=eq.completed&expires_at=gt.${nowFilter()}`,
        );
        if (!r) {
          throw new ApiError(
            403,
            "reply_unavailable",
            "This reply is no longer available.",
          );
        }
        await db.rpc("aira_media_limit", { p_user: user, p_kind: "speech" });
        const audio = await live.speak(approved.text);
        return respond({
          audioBase64: base64(new Uint8Array(audio)),
          mimeType: "audio/mpeg",
          provider: "elevenlabs",
        });
      }
      if (path === "/v1/memories" && method === "GET") {
        return respond({
          memories: p.consents.memory
            ? await db.request(`memories?${owned(user)}&order=created_at.desc`)
            : [],
        });
      }
      if (path === "/v1/memories" && method === "POST") {
        requireConsent(p, "memory");
        const b = await jsonBody(req);
        if (b.confirmed !== true) {
          throw new ApiError(
            400,
            "confirmation_required",
            "Confirm this memory before saving.",
          );
        }
        const category = b.category ?? "preference";
        if (
          !["preference", "relationship", "plan", "other"].includes(category)
        ) {
          throw new ApiError(
            400,
            "invalid_category",
            "Choose a valid memory category.",
          );
        }
        return respond({
          memory: await db.insert("memories", {
            user_id: user,
            text: boundedText(b.text, 500),
            category,
            confirmed: true,
          }),
        }, 201);
      }
      let match = path.match(/^\/v1\/memories\/([^/]+)$/);
      if (match && ["PATCH", "DELETE"].includes(method)) {
        requireConsent(p, "memory");
        const id = uuid(match[1]);
        const body = method === "PATCH" ? await jsonBody(req) : null;
        const privacyVersion = await db.rpc("aira_memory_edit", {
          p_user: user,
          p_id: id,
          p_version: body ? version(body) : 0,
          p_text: body ? boundedText(body.text, 500) : null,
        });
        return respond({ saved: true, privacyVersion, clearContext: true });
      }
      match = path.match(/^\/v1\/conversations\/([^/]+)$/);
      if (match && method === "DELETE") {
        await db.remove(
          "conversations",
          `id=eq.${uuid(match[1])}&user_id=eq.${user}`,
        );
        return respond({ deleted: true, clearContext: true });
      }
      const scheduleList = path === "/v1/medications"
        ? "medication"
        : path === "/v1/events/proposals"
        ? "event"
        : null;
      if (scheduleList && method === "GET") {
        return respond({
          schedules: await db.request(
            `schedules?${owned(user)}&kind=eq.${scheduleList}&order=due_at.asc`,
          ),
        });
      }
      if (scheduleList && method === "POST") {
        requireConsent(
          p,
          scheduleList === "medication"
            ? "medication_reminders"
            : "social_reminders",
        );
        const b = await jsonBody(req);
        const due = new Date(
          b.dueAt ?? b.followupAt ?? nextLocalTime(b.localTime, p.timezone),
        );
        if (
          !Number.isFinite(due.getTime()) || due.getTime() <= Date.now() ||
          due.getTime() >= Date.now() + 86400000
        ) {
          throw new ApiError(
            400,
            "invalid_time",
            "Prototype reminders must be within the next 24 hours.",
          );
        }
        if (b.confirmed !== true) {
          throw new ApiError(
            400,
            "confirmation_required",
            "Review and confirm the reminder first.",
          );
        }
        if (b.recurrence && b.recurrence !== "once") {
          throw new ApiError(
            400,
            "recurrence_unavailable",
            "Recurring reminders are not enabled yet.",
          );
        }
        return respond({
          schedule: await db.insert("schedules", {
            user_id: user,
            kind: scheduleList,
            label: boundedText(b.label ?? b.topic, 300),
            instructions: typeof b.instructions === "string"
              ? b.instructions.slice(0, 500)
              : "",
            due_at: due.toISOString(),
            timezone: p.timezone,
            confirmed: true,
          }),
        }, 201);
      }
      match = path.match(/^\/v1\/(medications|events)\/([^/]+)$/);
      if (match && ["PATCH", "DELETE"].includes(method)) {
        const id = uuid(match[2]);
        const kind = match[1] === "medications" ? "medication" : "event";
        if (method === "DELETE") {
          await db.remove(
            "schedules",
            `id=eq.${id}&user_id=eq.${user}&kind=eq.${kind}`,
          );
          return respond({ deleted: true });
        }
        const b = await jsonBody(req);
        const change: any = { version: version(b) + 1 };
        if (b.label !== undefined) change.label = boundedText(b.label, 300);
        if (b.enabled !== undefined) {
          if (typeof b.enabled !== "boolean") {
            throw new ApiError(
              400,
              "invalid_input",
              "Enabled must be true or false.",
            );
          }
          change.enabled = b.enabled;
        }
        if (b.dueAt !== undefined) {
          const due = new Date(b.dueAt);
          if (
            !Number.isFinite(due.getTime()) || due.getTime() <= Date.now() ||
            due.getTime() >= Date.now() + 86400000
          ) {
            throw new ApiError(
              400,
              "invalid_time",
              "Use a time within 24 hours.",
            );
          }
          change.due_at = due.toISOString();
        }
        const updated = await db.rpc("aira_schedule_edit", {
          p_user: user,
          p_id: id,
          p_kind: kind,
          p_version: b.expectedVersion,
          p_patch: change,
        });
        return respond({ schedule: updated });
      }
      if (path === "/v1/events" && method === "GET") {
        return respond({
          events: await db.request(
            `foreground_events?${
              owned(user)
            }&state=in.(pending,snoozed)&notify_at=lte.${nowFilter()}&order=created_at.asc&limit=50`,
          ),
        });
      }
      match = path.match(
        /^\/v1\/(invitations|medication-occurrences)\/([^/]+)\/respond$/,
      );
      if (match && method === "POST") {
        const b = await jsonBody(req);
        return respond({
          event: await db.rpc("aira_event_action", {
            p_user: user,
            p_id: uuid(match[2]),
            p_action: b.action,
            p_request: uuid(b.requestId),
            p_version: version(b),
            p_snooze: b.nextNotifyAt ?? null,
          }),
        });
      }
      if (path === "/v1/calls/session" && method === "POST") {
        if (!realtimeConfigured(get)) {
          throw new ApiError(
            503,
            "not_configured",
            "Live calls are not configured yet.",
          );
        }
        const b = await jsonBody(req);
        if (!["voice", "video"].includes(b.mode)) {
          throw new ApiError(400, "invalid_mode", "Choose voice or video.");
        }
        let reservation;
        try {
          reservation = await db.rpc("aira_reserve_call", {
            p_user: user,
            p_mode: b.mode,
            p_consent_version: p.consent_version,
          });
        } catch (e) {
          if (e instanceof ApiError && e.code === "rate_limited") {
            throw new ApiError(
              429,
              "call_limit",
              "End your other call before starting a new one.",
            );
          }
          throw e;
        }
        const { conversation, session } = reservation;
        try {
          const expires = Date.parse(session.expires_at);
          const token = await conversationToken(get, fetcher);
          return respond({
            conversationId: conversation.id,
            conversationToken: token,
            customLlmExtraBody: {
              aira_session_token: await signCall({
                user,
                conversation: conversation.id,
                version: session.consent_version,
                expires,
              }, get("AIRA_CALL_SIGNING_SECRET")),
            },
            dynamicVariables: { aira_name: p.display_name || "friend" },
            expiresAt: new Date(expires).toISOString(),
          }, 201);
        } catch (e) {
          // Attempt both cleanup operations even if either database request fails.
          // The worker also removes expired/revoked sessions on its next tick.
          await Promise.allSettled([
            db.remove(
              "realtime_sessions",
              `conversation_id=eq.${conversation.id}&user_id=eq.${user}`,
            ),
            db.patch(
              "conversations",
              `id=eq.${conversation.id}&user_id=eq.${user}&ended_at=is.null`,
              { ended_at: new Date().toISOString() },
            ),
          ]);
          throw e;
        }
      }
      const contextMatch = path.match(/^\/v1\/calls\/([^/]+)\/context$/);
      if (contextMatch && method === "PATCH") {
        const id = uuid(contextMatch[1]);
        const session = await db.one(
          "realtime_sessions",
          `conversation_id=eq.${id}&user_id=eq.${user}&expires_at=gt.${nowFilter()}`,
        );
        if (!session || session.consent_version !== p.consent_version) {
          throw new ApiError(
            409,
            "call_expired",
            "Please start a new call after changing privacy choices.",
          );
        }
        await db.patch(
          "realtime_sessions",
          `conversation_id=eq.${id}&user_id=eq.${user}`,
          {
            context: callContext(
              await jsonBody(req),
              p.consents.face_cues === true,
            ),
          },
        );
        return respond({ updated: true });
      }
      if (path === "/v1/calls" && method === "POST") {
        const b = await jsonBody(req);
        if (!["voice", "video"].includes(b.mode)) {
          throw new ApiError(
            400,
            "invalid_mode",
            "Choose voice or video.",
          );
        }
        return respond({
          conversation: await db.insert("conversations", {
            user_id: user,
            mode: b.mode,
          }),
        }, 201);
      }
      match = path.match(/^\/v1\/calls\/([^/]+)\/end$/);
      if (match && method === "POST") {
        await db.patch(
          "conversations",
          `id=eq.${uuid(match[1])}&user_id=eq.${user}&ended_at=is.null`,
          { ended_at: new Date().toISOString() },
        );
        await db.remove(
          "realtime_sessions",
          `conversation_id=eq.${uuid(match[1])}&user_id=eq.${user}`,
        );
        return respond({ ended: true });
      }
      if (path === "/v1/measurements/prompt" && method === "GET") {
        requireConsent(p, "impact");
        const prompt = await db.rpc("aira_prompt", { p_user: user });
        if (!prompt) {
          return respond({
            prompt: null,
            response: null,
            message:
              "Your next optional weekly question will be available after seven days.",
          });
        }
        const response = await db.one(
          "loneliness_responses",
          `prompt_id=eq.${prompt.id}&${owned(user)}`,
        );
        return respond({
          prompt: {
            ...prompt,
            question:
              `Thinking about ${prompt.period_start} to ${prompt.period_end}, on how many of those seven days did you feel lonely?`,
            optional: true,
          },
          response,
        });
      }
      if (path === "/v1/measurements/loneliness" && method === "POST") {
        requireConsent(p, "impact");
        const b = await jsonBody(req);
        const skip = b.skipped === true;
        if (
          !skip &&
          (!Number.isInteger(b.lonelyDays) || b.lonelyDays < 0 ||
            b.lonelyDays > 7)
        ) {
          throw new ApiError(
            400,
            "invalid_answer",
            "Choose 0 to 7 days, or skip.",
          );
        }
        if (!Number.isInteger(b.expectedVersion) || b.expectedVersion < 0) {
          throw new ApiError(
            400,
            "invalid_version",
            "Include the current answer version.",
          );
        }
        return respond({
          response: await db.rpc("aira_loneliness", {
            p_user: user,
            p_prompt: uuid(b.promptId),
            p_days: skip ? null : b.lonelyDays,
            p_skip: skip,
            p_request: uuid(b.requestId),
            p_version: b.expectedVersion,
          }),
        });
      }
      if (path === "/v1/measurements/mood" && method === "POST") {
        requireConsent(p, "mood_history");
        const b = await jsonBody(req);
        if (!["happy", "okay", "sad", "worried", "tired"].includes(b.label)) {
          throw new ApiError(
            400,
            "invalid_mood",
            "Choose an available feeling.",
          );
        }
        return respond({
          observation: await db.insert("mood_observations", {
            user_id: user,
            label: b.label,
            source: "self_report",
          }),
        }, 201);
      }
      if (path === "/v1/me/insights" && method === "GET") {
        return respond(
          await readInsights(user),
        );
      }
      if (path === "/v1/admin/subjects" && method === "GET") {
        const assignments = await db.request(
          `role_assignments?user_id=eq.${user}&role=eq.insights&enabled=eq.true&subject_id=not.is.null`,
        );
        const ids = assignments.map((x: any) => uuid(x.subject_id));
        return respond({
          seniors: ids.length
            ? await db.request(
              `profiles?select=id,display_name&id=in.(${
                ids.join(",")
              })&enabled=eq.true`,
            )
            : [],
        });
      }
      if (path === "/v1/caregiver/seniors" && method === "GET") {
        const links = await db.request(
          `caregiver_links?caregiver_id=eq.${user}&verified=eq.true&revoked_at=is.null`,
        );
        const seniors = [];
        for (const link of links) {
          const senior = await db.one(
            "profiles",
            `select=id,display_name&id=eq.${link.senior_id}&enabled=eq.true`,
          );
          if (senior) seniors.push({ ...senior, scopes: link.scopes });
        }
        return respond({ seniors });
      }
      if (path === "/v1/admin/overview" && method === "GET") {
        await role("operator");
        const rows = await db.request(
          "incidents?select=state&expires_at=gt." + nowFilter(),
        );
        return respond({
          queueCount: rows.length,
          externalDelivery: false,
          mode: "test_only",
          staffedCoverage: "Not configured",
        });
      }
      if (path === "/v1/admin/incidents" && method === "GET") {
        const assignments = await db.request(
          `role_assignments?user_id=eq.${user}&role=eq.reviewer&enabled=eq.true&subject_id=not.is.null`,
        );
        if (!assignments.length) {
          throw new ApiError(
            403,
            "role_required",
            "No review cases are assigned to you.",
          );
        }
        const subjects = assignments.map((x: any) => uuid(x.subject_id));
        const profiles = await db.request(
          `profiles?id=in.(${subjects.join(",")})&enabled=eq.true`,
        );
        const eligible = profiles.filter((x: any) => x.consents.monitoring).map(
          (x: any) => x.id,
        );
        if (!eligible.length) return respond({ incidents: [] });
        await audit("review_queue_read");
        return respond({
          incidents: await db.request(
            `incidents?user_id=in.(${
              eligible.join(",")
            })&expires_at=gt.${nowFilter()}&order=created_at.desc`,
          ),
        });
      }
      match = path.match(/^\/v1\/admin\/incidents\/([^/]+)\/review$/);
      if (match && method === "POST") {
        const b = await jsonBody(req);
        const incident = await db.one(
          "incidents",
          `id=eq.${uuid(match[1])}&expires_at=gt.${nowFilter()}`,
        );
        if (!incident) {
          throw new ApiError(
            404,
            "not_found",
            "Case unavailable.",
          );
        }
        await role("reviewer", incident.user_id);
        const senior = await db.one(
          "profiles",
          `id=eq.${incident.user_id}&enabled=eq.true`,
        );
        if (!senior?.consents.monitoring) {
          throw new ApiError(
            403,
            "consent_required",
            "Monitoring consent is unavailable.",
          );
        }
        if (
          !["dismissed", "reviewed", "followup", "closed"].includes(b.state)
        ) throw new ApiError(400, "invalid_state", "Choose a review result.");
        const reason = boundedText(b.reason, 500);
        const updated = conflict(
          await db.patch(
            "incidents",
            `id=eq.${incident.id}&version=eq.${version(b)}`,
            {
              state: b.state,
              review_reason: reason,
              version: b.expectedVersion + 1,
            },
          ),
        );
        if (["dismissed", "closed"].includes(b.state)) {
          await db.patch(
            "test_report_outbox",
            `incident_id=eq.${incident.id}&state=eq.queued`,
            { state: "cancelled" },
          );
        }
        if (
          b.approveReport === true &&
          ["reviewed", "followup"].includes(b.state) &&
          senior.consents.reviewed_sharing
        ) {
          const links = await db.request(
            `caregiver_links?senior_id=eq.${senior.id}&verified=eq.true&test_recipient=eq.true&revoked_at=is.null`,
          );
          for (
            const link of links.filter((l: any) =>
              l.scopes.includes("reviewed")
            )
          ) {
            const existing = await db.one(
              "test_report_outbox",
              `incident_id=eq.${incident.id}&recipient_id=eq.${link.caregiver_id}`,
            );
            if (!existing) {
              await db.insert("test_report_outbox", {
                incident_id: incident.id,
                user_id: senior.id,
                recipient_id: link.caregiver_id,
                dispatch_basis: "reviewer_approval",
                consent_version: senior.consent_version,
              });
            }
          }
        }
        await audit("incident_reviewed", senior.id);
        return respond({ incident: updated, externalDelivery: false });
      }
      if (path === "/v1/caregiver/reports" && method === "GET") {
        const links = await db.request(
          `caregiver_links?caregiver_id=eq.${user}&verified=eq.true&test_recipient=eq.true&revoked_at=is.null`,
        );
        const reports = [];
        for (const link of links) {
          const senior = await db.one(
            "profiles",
            `id=eq.${link.senior_id}&enabled=eq.true`,
          );
          if (!senior?.consents.monitoring) continue;
          const rows = await db.request(
            `test_report_outbox?recipient_id=eq.${user}&user_id=eq.${link.senior_id}&expires_at=gt.${nowFilter()}&state=in.(test_delivered,acknowledged)`,
          );
          for (const r of rows) {
            const scope = r.dispatch_basis === "urgent_policy"
              ? "urgent"
              : "reviewed";
            if (
              link.scopes.includes(scope) && senior.consents[
                scope === "urgent" ? "urgent_sharing" : "reviewed_sharing"
              ]
            ) {
              const incident = await db.one(
                "incidents",
                `id=eq.${r.incident_id}&expires_at=gt.${nowFilter()}`,
              );
              reports.push({
                ...r,
                incident,
                label: "Test report — no external delivery",
              });
            }
          }
        }
        await audit("caregiver_reports_read");
        return respond({ reports, externalDelivery: false });
      }
      match = path.match(/^\/v1\/caregiver\/reports\/([^/]+)\/ack$/);
      if (match && method === "POST") {
        const report = await db.one(
          "test_report_outbox",
          `id=eq.${
            uuid(match[1])
          }&recipient_id=eq.${user}&expires_at=gt.${nowFilter()}`,
        );
        if (!report) {
          throw new ApiError(
            404,
            "not_found",
            "Report unavailable.",
          );
        }
        const link = await db.one(
          "caregiver_links",
          `senior_id=eq.${report.user_id}&caregiver_id=eq.${user}&verified=eq.true&revoked_at=is.null`,
        );
        const senior = await db.one(
          "profiles",
          `id=eq.${report.user_id}&enabled=eq.true`,
        );
        const scope = report.dispatch_basis === "urgent_policy"
          ? "urgent"
          : "reviewed";
        if (
          !link?.scopes.includes(scope) || !senior?.consents.monitoring ||
          !senior.consents[
            scope === "urgent" ? "urgent_sharing" : "reviewed_sharing"
          ]
        ) {
          throw new ApiError(
            403,
            "access_denied",
            "This report is no longer shared.",
          );
        }
        if (report.state !== "acknowledged") {
          conflict(
            await db.patch(
              "test_report_outbox",
              `id=eq.${report.id}&state=eq.test_delivered`,
              {
                state: "acknowledged",
                acknowledged_at: new Date().toISOString(),
              },
            ),
          );
        }
        await audit("test_report_acknowledged", report.user_id);
        return respond({ acknowledged: true, resolved: false });
      }
      match = path.match(/^\/v1\/caregiver\/seniors\/([^/]+)\/insights$/);
      if (match && method === "GET") {
        const subject = uuid(match[1]);
        const link = await db.one(
          "caregiver_links",
          `senior_id=eq.${subject}&caregiver_id=eq.${user}&verified=eq.true&revoked_at=is.null`,
        );
        if (!link) {
          throw new ApiError(
            403,
            "access_denied",
            "No verified sharing link.",
          );
        }
        await audit("caregiver_insights_read", subject);
        return respond(
          await readInsights(
            subject,
            ["loneliness", "conversations", "mood"].filter((c) =>
              link.scopes.includes(c)
            ),
          ),
        );
      }
      if (path === "/v1/admin/insights" && method === "GET") {
        const subject = uuid(url.searchParams.get("subjectId"));
        await role("insights", subject);
        const senior = await db.one(
          "profiles",
          `id=eq.${subject}&enabled=eq.true`,
        );
        if (!senior?.consents.admin_insights) {
          throw new ApiError(
            403,
            "consent_required",
            "Admin insight sharing is not enabled.",
          );
        }
        await audit("admin_insights_read", subject);
        return respond(await readInsights(subject));
      }
      throw new ApiError(
        404,
        "not_found",
        "This feature is not available yet.",
      );
    } catch (error) {
      const e = error instanceof ApiError ? error : new ApiError(
        503,
        "temporarily_unavailable",
        "AIRA could not complete that request. Please try again.",
      );
      return respond({
        code: e.code,
        message: e.message,
        retryable: e.status >= 500 || e.status === 429,
        requestId,
      }, e.status);
    }
  };
}
if (import.meta.main) Deno.serve(createHandler());
