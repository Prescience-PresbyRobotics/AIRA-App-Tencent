import { createHandler } from "../functions/aira-api/index.ts";
const USER = "d49f2c15-337f-4133-b9e8-54cf914d6fd3";
const OTHER = "43ee9271-2f32-46a0-844d-f6ae504ed4d5";
const get = (
  name: string,
) => ({
  SUPABASE_URL: "https://database.test",
  SUPABASE_SECRET_KEY: "sb_secret_test_only",
}[name] ?? "");
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
Deno.test("History API binds pagination and deletion to the authenticated owner", async () => {
  const calls: { path: string; body: any }[] = [];
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    if (url.pathname.endsWith("/profiles")) {
      return Response.json([{ id: USER, enabled: true, consents: {} }]);
    }
    calls.push({ path: url.pathname, body: JSON.parse(String(init?.body)) });
    if (url.pathname.endsWith("/aira_clear_chat_history")) {
      return Response.json(7);
    }
    return Response.json({ messages: [], nextCursor: null, privacyVersion: 6 });
  };
  const handler = createHandler(get, fetcher, async () => USER);
  const page = await handler(
    new Request(
      `https://app.test/aira-api/v1/history?before=123&userId=${OTHER}`,
    ),
  );
  assert(page.status === 200, "History request succeeds");
  assert(
    calls[0].body.p_user === USER && calls[0].body.p_before === "123" &&
      calls[0].body.p_limit === 50,
    "Caller cannot select another owner or unbounded size",
  );
  for (
    const cursor of [
      "0",
      "-1",
      "1.5",
      "9223372036854775808",
      "1),user_id.eq.other",
    ]
  ) {
    assert(
      (await handler(
        new Request(
          `https://app.test/aira-api/v1/history?before=${
            encodeURIComponent(cursor)
          }`,
        ),
      )).status === 400,
      "Invalid cursors rejected",
    );
  }
  assert(calls.length === 1, "Bad cursors do not reach privileged RPC");
  const deleted = await handler(
    new Request("https://app.test/aira-api/v1/history", { method: "DELETE" }),
  );
  assert(
    deleted.status === 200 && (await deleted.json()).privacyVersion === 7,
    "Deletion returns new context version",
  );
  assert(calls[1].body.p_user === USER, "Delete is owner-bound");
});

Deno.test("Message API persists delivered input before providers and excludes it from prior context", async () => {
  const request = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
  const events: string[] = [];
  const environment = (
    name: string,
  ) => ({ OPENAI_API_KEY: "test-only-key", OPENAI_MODEL: "test-model" }[name] ??
    get(name));
  const fetcher: typeof fetch = async (input, init) => {
    const url = new URL(String(input));
    const body = init?.body ? JSON.parse(String(init.body)) : null;
    if (url.pathname.endsWith("/profiles")) {
      return Response.json([{
        id: USER,
        enabled: true,
        consent_version: 3,
        consents: { conversation_storage: true },
      }]);
    }
    if (url.pathname.endsWith("/aira_reserve_message")) {
      return Response.json({
        duplicate: false,
        request: { id: request, conversation_id: request },
      });
    }
    if (url.pathname.endsWith("/aira_save_message_input")) {
      assert(
        body.p_user === USER && body.p_request === request &&
          body.p_input === "Hello again" && body.p_consent_version === 3,
        "Input persistence is bound to authenticated owner and consent version",
      );
      events.push("saved-input");
      return Response.json(true);
    }
    if (url.pathname.endsWith("/aira_shared_context")) {
      assert(
        body.p_exclude === request && body.p_user === USER &&
          body.p_version === 3,
        "Shared context excludes current input and old privacy epochs",
      );
      return Response.json({ memories: [], plans: [], recentConversation: [] });
    }
    if (url.hostname === "api.openai.com") {
      assert(
        events[0] === "saved-input",
        "Input is saved before any provider work",
      );
      events.push("provider");
      const text = body.text?.format?.name === "aira_screening"
        ? JSON.stringify({
          safe: true,
          concern: "none",
          immediate: false,
          selfDirected: false,
          current: false,
          quotedOrHistorical: false,
          evidence: "",
          reason: "benign fixture",
        })
        : JSON.stringify({
          reply: "Hello, lovely to hear from you.",
          actions: [],
        });
      return Response.json({
        status: "completed",
        output: [{ type: "message", content: [{ type: "output_text", text }] }],
      });
    }
    if (url.pathname.endsWith("/aira_finish_message")) {
      return Response.json(true);
    }
    throw new Error(`Unexpected endpoint ${url.pathname}`);
  };
  const response = await createHandler(environment, fetcher, async () => USER)(
    new Request("https://app.test/aira-api/v1/messages", {
      method: "POST",
      body: JSON.stringify({
        clientMessageId: request,
        text: "Hello again",
        contextVersion: 3,
      }),
    }),
  );
  assert(
    response.status === 200 &&
      (await response.json()).text === "Hello, lovely to hear from you.",
    "Checked reply completes normally",
  );
  assert(
    events.length === 4 && events[0] === "saved-input",
    "Input saved before the existing three provider checks",
  );
});
