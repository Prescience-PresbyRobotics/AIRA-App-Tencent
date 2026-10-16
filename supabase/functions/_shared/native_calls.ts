import { ApiError, sameSecret, uuid } from "./domain.ts";
import { Database, type Env, jsonBody, requireEnv } from "./runtime.ts";

export type CallEntry = {
  role: "user" | "assistant";
  text: string;
  timeInCallSecs: number;
};
export function callEntries(value: unknown, provider = false): CallEntry[] {
  if (!Array.isArray(value) || value.length > 500) {
    throw new ApiError(
      400,
      "invalid_transcript",
      "This call transcript could not be saved.",
    );
  }
  const result: CallEntry[] = [];
  let length = 0;
  for (const entry of value) {
    const role = provider && entry?.role === "agent"
      ? "assistant"
      : entry?.role;
    const text = provider ? entry?.message : entry?.text;
    if (provider && (text === null || text === undefined || text === "")) {
      continue;
    }
    const seconds = provider ? entry?.time_in_call_secs : entry?.timeInCallSecs;
    if (
      !["user", "assistant"].includes(role) || typeof text !== "string" ||
      text.length > 8000 || !Number.isFinite(seconds) || seconds < 0 ||
      seconds > 3600
    ) {
      throw new ApiError(
        400,
        "invalid_transcript",
        "This call transcript could not be saved.",
      );
    }
    if (!text.trim()) continue;
    length += text.length;
    if (length > 200000) {
      throw new ApiError(413, "too_large", "This transcript is too large.");
    }
    result.push({
      role,
      text: text.trim(),
      timeInCallSecs: Math.floor(seconds),
    });
  }
  return result;
}
export function providerConversationId(value: unknown): string {
  if (typeof value !== "string" || !/^[A-Za-z0-9_-]{8,128}$/.test(value)) {
    throw new ApiError(
      400,
      "invalid_conversation",
      "The call connection could not be identified.",
    );
  }
  return value;
}
function cursor(value: string | null) {
  if (
    value !== null &&
    (!/^[1-9]\d{0,18}$/.test(value) || BigInt(value) > 9223372036854775807n)
  ) {
    throw new ApiError(400, "invalid_cursor", "Please refresh call history.");
  }
  return value;
}
const ownerFilter = (user: string, id: string) =>
  `user_id=eq.${user}&conversation_id=eq.${id}`;

// Identity is checked against the provider's recorded initiation data. Merely
// guessing a provider conversation id can never disclose somebody else's call.
export function providerTranscript(record: any, body: any, agentId: string) {
  const variables = body.conversation_initiation_client_data?.dynamic_variables;
  if (
    body.agent_id !== agentId || body.conversation_id !== record.provider_id ||
    variables?.aira_call_id !== record.conversation_id ||
    typeof variables?.aira_call_binding !== "string" ||
    !sameSecret(variables.aira_call_binding, record.call_binding)
  ) {
    throw new ApiError(
      403,
      "call_mismatch",
      "This provider conversation does not belong to this call.",
    );
  }
  return callEntries(body.transcript ?? [], true);
}

export async function syncCallTranscript(
  db: Database,
  get: Env,
  fetcher: typeof fetch,
  record: any,
) {
  if (
    !record.provider_id || record.source === "legacy_bridge" ||
    record.provider_status === "done" || record.sync_attempts >= 10
  ) return false;
  const profile = await db.one(
    "profiles",
    `id=eq.${record.user_id}&enabled=eq.true`,
  );
  if (
    !profile?.consents?.conversation_storage ||
    profile.consent_version !== record.consent_version
  ) {
    // A revoked or superseded row must not occupy the worker's bounded batch
    // forever. Only retire recovery metadata; never recreate deleted content.
    await db.patch(
      "call_transcripts",
      ownerFilter(record.user_id, record.conversation_id),
      {
        sync_attempts: 10,
        status: record.entries?.length ? "ready" : "unavailable",
      },
    );
    return false;
  }
  await db.patch(
    "call_transcripts",
    ownerFilter(record.user_id, record.conversation_id),
    {
      sync_attempts: (record.sync_attempts ?? 0) + 1,
      last_sync_at: new Date().toISOString(),
    },
  );
  const response = await fetcher(
    `https://api.elevenlabs.io/v1/convai/conversations/${
      encodeURIComponent(record.provider_id)
    }`,
    {
      headers: { "xi-api-key": requireEnv(get, "ELEVENLABS_API_KEY") },
      signal: AbortSignal.timeout(8000),
    },
  );
  if (!response.ok) {
    // Retention may have already removed the provider copy. Device captions,
    // if present, remain explicitly labelled as such and are never reclassified.
    if ((record.sync_attempts ?? 0) >= 9) {
      await db.patch(
        "call_transcripts",
        ownerFilter(record.user_id, record.conversation_id),
        {
          status: record.entries?.length ? "ready" : "unavailable",
        },
      );
    }
    return false;
  }
  const body = await response.json();
  const entries = providerTranscript(
    record,
    body,
    requireEnv(get, "ELEVENLABS_AGENT_ID"),
  );
  return await db.rpc("aira_save_call_transcript", {
    p_user: record.user_id,
    p_call: record.conversation_id,
    p_provider: record.provider_id,
    p_entries: entries,
    p_source: entries.length ? "elevenlabs" : "pending",
    p_status: entries.length
      ? "ready"
      : (body.status === "done" || body.status === "failed"
        ? "unavailable"
        : "pending"),
    p_provider_status: body.status,
  });
}

export async function syncPendingCallTranscripts(
  db: Database,
  get: Env,
  fetcher: typeof fetch = fetch,
  limit = 5,
) {
  const records = await db.request(
    `call_transcripts?select=*,conversations!inner(ended_at)&conversations.ended_at=not.is.null&provider_id=not.is.null&sync_attempts=lt.10&and=(or(provider_status.is.null,provider_status.neq.done),or(last_sync_at.is.null,last_sync_at.lt.${
      encodeURIComponent(new Date(Date.now() - 60000).toISOString())
    }))&order=created_at.desc&limit=${Math.min(limit, 5)}`,
  );
  const outcomes = await Promise.allSettled(
    records.map((record: any) => syncCallTranscript(db, get, fetcher, record)),
  );
  return outcomes.filter((outcome) =>
    outcome.status === "fulfilled" && outcome.value
  ).length;
}

export async function handleCallArchives(
  path: string,
  method: string,
  req: Request,
  context: {
    db: Database;
    user: string;
    profile: any;
    get: Env;
    fetcher: typeof fetch;
  },
): Promise<{ body: any; status?: number } | null> {
  const { db, user, profile, get, fetcher } = context;
  if (path === "/v1/calls/history" && method === "GET") {
    const page = await db.rpc("aira_call_history", {
      p_user: user,
      p_before: cursor(new URL(req.url).searchParams.get("before")),
      p_call: null,
    });
    return { body: page };
  }
  const match = path.match(/^\/v1\/calls\/([^/]+)\/transcript$/);
  if (!match) return null;
  const id = uuid(match[1]);
  if (method === "DELETE") {
    await db.rpc("aira_delete_call_transcript", { p_user: user, p_call: id });
    const latest = await db.one("profiles", `id=eq.${user}&enabled=eq.true`);
    return { body: { deleted: true, privacyVersion: latest?.consent_version } };
  }
  if (method === "GET") {
    // Recovery is bounded to one provider lookup, only for an owner's archive.
    const record = profile.consents.conversation_storage
      ? await db.one("call_transcripts", ownerFilter(user, id))
      : null;
    if (
      record &&
      (!record.last_sync_at ||
        Date.parse(record.last_sync_at) < Date.now() - 10000)
    ) {
      await syncCallTranscript(db, get, fetcher, record).catch(() => false);
    }
    const page = await db.rpc("aira_call_history", {
      p_user: user,
      p_before: null,
      p_call: id,
    });
    const call = page.calls[0];
    if (!call) {
      throw new ApiError(
        404,
        "not_found",
        "This call transcript is unavailable.",
      );
    }
    const entries = call.entries ?? [];
    delete call.entries;
    return {
      body: {
        call,
        messages: entries.map((entry: CallEntry, index: number) => ({
          ...entry,
          id: `${id}-${index}`,
          createdAt: new Date(
            Date.parse(call.startedAt) + entry.timeInCallSecs * 1000,
          ).toISOString(),
        })),
        privacyVersion: page.privacyVersion,
      },
    };
  }
  if (method === "POST") {
    const body = await jsonBody(req, 262144);
    const provider = providerConversationId(body.providerConversationId);
    const entries = callEntries(body.entries ?? []);
    const call = await db.one(
      "conversations",
      `id=eq.${id}&user_id=eq.${user}&mode=in.(voice,video)`,
    );
    if (!call) {
      throw new ApiError(404, "not_found", "This call is unavailable.");
    }
    // These recent user captions are ephemeral evidence for owner-bound native
    // save tools, including when durable archive storage is disabled.
    await db.rpc("aira_update_call_context", {
      p_user: user,
      p_call: id,
      p_version: profile.consent_version,
      p_context: {
        recentUserCaptions: entries.filter((entry) => entry.role === "user")
          .slice(-20).map((entry) => entry.text.slice(0, 2000)),
      },
    });
    if (!profile.consents.conversation_storage) {
      return { body: { saved: false, reason: "storage_disabled" } };
    }
    const saved = await db.rpc("aira_save_call_transcript", {
      p_user: user,
      p_call: id,
      p_provider: provider,
      p_entries: entries,
      p_source: entries.length ? "device_captions" : "pending",
      p_status: entries.length ? "ready" : "pending",
      p_provider_status: null,
    });
    // The SDK's final events are saved first. A worker retrieves the canonical
    // provider transcript separately, without delaying hangup or the next chat.
    return {
      body: { saved, source: entries.length ? "device_captions" : "pending" },
    };
  }
  return null;
}
