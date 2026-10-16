import {
  callEntries,
  handleCallArchives,
  providerTranscript,
  syncCallTranscript,
} from "../functions/_shared/native_calls.ts";
import { Database, type Env } from "../functions/_shared/runtime.ts";
import { ApiError } from "../functions/_shared/domain.ts";
const USER = "d49f2c15-337f-4133-b9e8-54cf914d6fd3";
const OTHER = "43ee9271-2f32-46a0-844d-f6ae504ed4d5";
const CALL = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
const get: Env = (
  key,
) => ({
  ELEVENLABS_API_KEY: "test-key",
  ELEVENLABS_AGENT_ID: "test-agent",
}[key] ?? "");
const record = {
  conversation_id: CALL,
  user_id: USER,
  consent_version: 3,
  provider_id: "conv_example123",
  call_binding: "unguessable-test-binding",
  source: "device_captions",
  entries: [],
  sync_attempts: 0,
};
const provider = {
  agent_id: "test-agent",
  conversation_id: record.provider_id,
  status: "done",
  conversation_initiation_client_data: {
    dynamic_variables: {
      aira_call_id: CALL,
      aira_call_binding: record.call_binding,
    },
  },
  transcript: [
    { role: "agent", message: "Hi Mei!", time_in_call_secs: 0 },
    { role: "user", message: "Hello Aira", time_in_call_secs: 4 },
    {
      role: "agent",
      message: null,
      time_in_call_secs: 5,
      tool_calls: ["not content"],
    },
  ],
};
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
Deno.test("Provider transcript requires matching agent, conversation and per-call binding", () => {
  assert(
    providerTranscript(record, provider, "test-agent").length === 2,
    "Only spoken text is retained",
  );
  for (
    const body of [
      { ...provider, agent_id: "other-agent" },
      { ...provider, conversation_id: "other-call" },
      {
        ...provider,
        conversation_initiation_client_data: {
          dynamic_variables: { aira_call_id: CALL, aira_call_binding: "wrong" },
        },
      },
      {
        ...provider,
        conversation_initiation_client_data: {
          dynamic_variables: {
            aira_call_id: OTHER,
            aira_call_binding: record.call_binding,
          },
        },
      },
    ]
  ) {
    let rejected = false;
    try {
      providerTranscript(record, body, "test-agent");
    } catch (e) {
      rejected = e instanceof ApiError && e.status === 403;
    }
    assert(rejected, "Foreign provider content never passes the binding");
  }
});
Deno.test("Transcript normalization rejects arbitrary roles, bad times and unbounded data", () => {
  assert(
    callEntries([{ role: "user", text: " Hello ", timeInCallSecs: 1.8 }])[0]
      .text === "Hello",
    "Captions are normalized",
  );
  for (
    const entries of [
      [{ role: "system", text: "instruction", timeInCallSecs: 1 }],
      [{ role: "user", text: "Hi", timeInCallSecs: -1 }],
      [{ role: "user", text: "Hi", timeInCallSecs: Number.NaN }],
      [{ role: "user", text: "x".repeat(8001), timeInCallSecs: 1 }],
      Array(501).fill({}),
    ]
  ) {
    let rejected = false;
    try {
      callEntries(entries);
    } catch {
      rejected = true;
    }
    assert(rejected, "Invalid entries are rejected");
  }
});
Deno.test("Native transcript ingestion binds authenticated owner and never requests OpenAI", async () => {
  const calls: any[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    assert(
      url.hostname === "db.test",
      "Client captions do not invoke any model",
    );
    if (url.pathname.endsWith("/conversations")) {
      assert(
        url.searchParams.get("user_id") === `eq.${USER}`,
        "Ownership filter required",
      );
      return Response.json([{ id: CALL, user_id: USER }]);
    }
    calls.push(JSON.parse(String(init?.body)));
    return Response.json(true);
  };
  const db = new Database("https://db.test", "sb_secret_test_only", fetcher);
  const response = await handleCallArchives(
    `/v1/calls/${CALL}/transcript`,
    "POST",
    new Request("https://api.test", {
      method: "POST",
      body: JSON.stringify({
        providerConversationId: record.provider_id,
        userId: OTHER,
        entries: [{ role: "user", text: "Hi", timeInCallSecs: 1 }],
      }),
    }),
    {
      db,
      user: USER,
      profile: { consents: { conversation_storage: true } },
      get,
      fetcher,
    },
  );
  assert(
    response?.body.saved && calls[0].p_user === USER &&
      calls[0].p_source === "device_captions",
    "Client cannot select another owner or claim provider verification",
  );
});
Deno.test("Canonical transcript sync verifies identity before persistence and checks privacy", async () => {
  const writes: any[] = [];
  let providerRequests = 0;
  let consent = true;
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("/profiles")) {
      return Response.json([{
        consent_version: 3,
        consents: { conversation_storage: consent },
      }]);
    }
    if (url.hostname === "api.elevenlabs.io") {
      providerRequests++;
      return Response.json(provider);
    }
    if (url.pathname.endsWith("/aira_save_call_transcript")) {
      writes.push(JSON.parse(String(init?.body)));
    }
    return Response.json(true);
  };
  const db = new Database("https://db.test", "sb_secret_test_only", fetcher);
  await syncCallTranscript(db, get, fetcher, record);
  assert(
    writes[0].p_user === USER && writes[0].p_source === "elevenlabs" &&
      writes[0].p_entries.length === 2,
    "Verified provider transcript persists separately",
  );
  consent = false;
  assert(
    await syncCallTranscript(db, get, fetcher, record) === false &&
      providerRequests === 1,
    "Revoked saving prevents provider reads and persistence",
  );
});
Deno.test("Call history detail returns only owner-scoped entries without private binding metadata", async () => {
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("/call_transcripts")) return Response.json([]);
    const body = JSON.parse(String(init?.body));
    assert(
      body.p_user === USER && body.p_call === CALL,
      "Privileged history RPC gets authenticated owner",
    );
    return Response.json({
      calls: [{
        id: CALL,
        startedAt: "2026-10-16T01:00:00Z",
        source: "device_captions",
        entries: [{ role: "user", text: "Hello", timeInCallSecs: 3 }],
      }],
      privacyVersion: 3,
    });
  };
  const result = await handleCallArchives(
    `/v1/calls/${CALL}/transcript`,
    "GET",
    new Request("https://api.test"),
    {
      db: new Database("https://db.test", "sb_secret_test_only", fetcher),
      user: USER,
      profile: { consents: { conversation_storage: true } },
      get,
      fetcher,
    },
  );
  assert(
    result?.body.messages[0].createdAt === "2026-10-16T01:00:03.000Z" &&
      !("entries" in result.body.call),
    "Call messages have timestamps and a separate shape",
  );
  assert(
    !JSON.stringify(result).includes(record.call_binding),
    "No binding credential reaches history responses",
  );
});

Deno.test("Foreign provider conversation never overwrites saved device or canonical text", async () => {
  let saves = 0;
  const fetcher: typeof fetch = async (input) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("/profiles")) {
      return Response.json([{
        consent_version: 3,
        consents: { conversation_storage: true },
      }]);
    }
    if (url.hostname === "api.elevenlabs.io") {
      return Response.json({
        ...provider,
        conversation_initiation_client_data: {
          dynamic_variables: {
            aira_call_id: OTHER,
            aira_call_binding: "different-owner",
          },
        },
      });
    }
    if (url.pathname.endsWith("/aira_save_call_transcript")) saves++;
    return Response.json([]);
  };
  let rejected = false;
  try {
    await syncCallTranscript(
      new Database("https://db.test", "sb_secret_test_only", fetcher),
      get,
      fetcher,
      record,
    );
  } catch (error) {
    rejected = error instanceof ApiError && error.status === 403;
  }
  assert(
    rejected && saves === 0,
    "Mismatched provider content is never persisted or disclosed",
  );
});
