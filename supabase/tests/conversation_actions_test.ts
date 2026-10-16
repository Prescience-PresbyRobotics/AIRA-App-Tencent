import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import {
  futureTime,
  handleNativeCallTool,
  nextLocalTime,
  validateAction,
} from "../functions/_shared/conversation_actions.ts";
import { Database } from "../functions/_shared/runtime.ts";
const A = "d49f2c15-337f-4133-b9e8-54cf914d6fd3",
  B = "43ee9271-2f32-46a0-844d-f6ae504ed4d5";
function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}
async function fails(work: () => Promise<unknown>, includes: string) {
  try {
    await work();
  } catch (error) {
    assert(String(error).includes(includes), `Wrong failure ${error}`);
    return;
  }
  throw Error(`Expected ${includes}`);
}
Deno.test("Reminder time accepts next-year dates and includes today's clock-minute tomorrow", () => {
  const now = Date.parse("2026-10-16T02:30:23Z");
  assert(
    nextLocalTime("10:30", "Asia/Singapore", now) ===
      "2026-10-17T02:30:00.000Z",
    "Current minute must select tomorrow rather than fall outside loop",
  );
  assert(
    nextLocalTime("10:31", "Asia/Singapore", now) ===
      "2026-10-16T02:31:00.000Z",
    "Next minute is valid",
  );
  assert(
    futureTime("2026-12-25T08:00:00+08:00", now) === "2026-12-25T00:00:00.000Z",
    "More than 24h allowed",
  );
});
Deno.test("Actions require attributable words, bounded types and an explicit reminder time", () => {
  const base = {
    kind: "memory",
    key: "favorite-plant",
    sourceQuote: "I love roses",
    text: "Loves roses",
    category: "preference",
  };
  assert(
    validateAction(base, "I love roses!").key === "favorite-plant",
    "Grounded fact is valid",
  );
  for (
    const action of [
      { ...base, sourceQuote: "Aira loves roses" },
      { ...base, kind: "admin" },
      { ...base, kind: "event", label: "Lunch", dueAt: "tomorrow" },
      { ...base, recurrence: "daily" },
    ]
  ) {
    let rejected = false;
    try {
      validateAction(action, "I love roses!");
    } catch {
      rejected = true;
    }
    assert(rejected, "Ungrounded or ambiguous mutation is refused");
  }
});
Deno.test({
  name:
    "Shared context and automatic notes isolate owners, consent epochs and deletion; medicine edits recur durably",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = new PGlite();
    try {
      await db.exec(
        "create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon,service_role;",
      );
      for (
        const name of [
          "202610140001_aira_core.sql",
          "202610160001_realtime_calls.sql",
          "202610160002_durable_history.sql",
          "202610160003_pending_history.sql",
          "202610160004_native_call_archives.sql",
          "202610160005_scheduled_calls.sql",
          "202610160006_feature_defaults.sql",
          "202610160007_shared_conversation_actions.sql",
          "202610160008_display_preferences_context.sql",
        ]
      ) {
        await db.exec(
          (await Deno.readTextFile(
            new URL(`../migrations/${name}`, import.meta.url),
          )).replace("create extension if not exists pgcrypto;", ""),
        );
      }
      const q = async (sql: string, args: any[] = []) =>
        (await db.query<any>(sql, args)).rows;
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      const conv = (await q(
        "insert into conversations(user_id,mode,expires_at) values($1,'text','infinity') returning id",
        [A],
      ))[0].id;
      const native =
        (await q("select aira_reserve_call($1,'voice',1) r", [A]))[0].r;
      await q(
        "update realtime_sessions set call_binding=$1 where conversation_id=$2",
        [native.callBinding, native.conversation.id],
      );
      const memory = {
        kind: "memory",
        key: "favorite-plant",
        text: "Enjoys growing tomatoes",
        sourceQuote: "I grow tomatoes",
        category: "preference",
      };
      const saved = (await q("select aira_conversation_action($1,1,$2,$3) r", [
        A,
        conv,
        memory,
      ]))[0].r;
      assert(saved.status === "saved", "Fact saved");
      const repeated =
        (await q("select aira_conversation_action($1,1,$2,$3) r", [
          A,
          conv,
          memory,
        ]))[0].r;
      assert(
        repeated.id === saved.id && repeated.status === "already_saved",
        "Same fact is deduplicated",
      );
      const corrected =
        (await q("select aira_conversation_action($1,1,$2,$3) r", [A, conv, {
          ...memory,
          text: "Enjoys growing roses",
          sourceQuote: "Actually roses",
        }]))[0].r;
      assert(
        corrected.id === saved.id && corrected.status === "updated",
        "Corrections update semantic fact",
      );
      await fails(
        () =>
          q("select aira_conversation_action($1,1,$2,$3)", [B, conv, memory]),
        "forbidden",
      );
      await fails(
        () =>
          q("select aira_conversation_action($1,1,$2,$3,'wrong')", [
            A,
            native.conversation.id,
            memory,
          ]),
        "forbidden",
      );
      const req = (await q("select aira_reserve_message($1,$2,$3,'text') r", [
        A,
        crypto.randomUUID(),
        conv,
      ]))[0].r.request;
      await q(
        "select aira_finish_message($1,$2,'I painted a boat','A blue boat?',1)",
        [A, req.id],
      );
      await q(
        "select aira_save_call_transcript($1,$2,'provider-call',$3,'device_captions','ready',null)",
        [A, native.conversation.id, [{
          role: "user",
          text: "My dog is called Pepper",
          timeInCallSecs: 2,
        }]],
      );
      let context = (await q("select aira_shared_context($1,1) r", [A]))[0].r;
      assert(
        context.recentConversation.some((turn: any) =>
          turn.mode === "voice" && turn.text.includes("Pepper")
        ),
        "Call context reaches text model",
      );
      assert(
        context.recentConversation.some((turn: any) =>
          turn.mode === "text" && turn.text.includes("boat")
        ),
        "Text context reaches native call model",
      );
      assert(
        context.memories[0].text.includes("roses"),
        "Latest fact available across channels",
      );
      await q("select aira_preferences($1,$2)", [A, {
        text_scale: 1.2,
        reduced_motion: true,
        display_name: "Casey",
        timezone: "Asia/Singapore",
      }]);
      const displayVersion =
        (await q("select consent_version from profiles where id=$1", [A]))[0]
          .consent_version;
      assert(
        displayVersion === 1,
        "Display/name/timezone updates must preserve retained chat/call context",
      );
      const unchangedContext =
        (await q("select aira_shared_context($1,1) r", [A]))[0].r;
      assert(
        unchangedContext.recentConversation.length ===
          context.recentConversation.length,
        "Harmless preferences do not erase shared model context",
      );
      const foreign = (await q("select aira_shared_context($1,1) r", [B]))[0].r;
      assert(
        foreign.recentConversation.length === 0 &&
          foreign.memories.length === 0,
        "No other owner content",
      );
      const due = new Date(Date.now() + 7 * 86400000).toISOString();
      const medicine = {
        kind: "medication",
        key: "usual-medicine-morning",
        label: "My existing medicine",
        instructions: "My usual prescribed amount",
        dueAt: due,
        recurrence: "daily",
        sourceQuote: "Remind me about my usual medicine every morning",
      };
      const med = (await q("select aira_conversation_action($1,1,$2,$3) r", [
        A,
        conv,
        medicine,
      ]))[0].r;
      assert(med.status === "saved", "Chat medicine created beyond 24 hours");
      const med2 =
        (await q("select aira_conversation_action($1,1,$2,$3) r", [A, conv, {
          ...medicine,
          label: "My morning medicine",
        }]))[0].r;
      assert(
        med2.status === "updated" && med2.id === med.id,
        "Medicine can be updated by conversation",
      );
      const edited =
        (await q("select aira_schedule_edit($1,$2,'medication',2,$3) r", [
          A,
          med.id,
          {
            instructions: "As printed on my packet",
            due_at: new Date(Date.now() + 10 * 86400000).toISOString(),
          },
        ]))[0].r;
      assert(
        edited.instructions === "As printed on my packet" &&
          edited.expires_at === "infinity",
        "Manual medicine edits and retention work",
      );
      await q(
        "update schedules set due_at=now()-interval '1 minute' where id=$1",
        [med.id],
      );
      await q("select aira_worker_tick()");
      await q("select aira_worker_tick()");
      assert(
        (await q("select * from foreground_events where schedule_id=$1", [
          med.id,
        ])).length === 1,
        "Daily medicine produces one occurrence per due time",
      );
      const advanced =
        (await q("select * from schedules where id=$1", [med.id]))[0];
      assert(
        Date.parse(advanced.due_at) > Date.now() && advanced.version === 4,
        "Daily medicine advances to next local time",
      );
      const occurrence =
        (await q("select * from foreground_events where schedule_id=$1", [
          med.id,
        ]))[0];
      await q("select aira_event_action($1,$2,'taken',$3,1,null)", [
        A,
        occurrence.id,
        crypto.randomUUID(),
      ]);
      assert(
        (await q("select state from foreground_events where id=$1", [
          occurrence.id,
        ]))[0].state === "taken",
        "Advancing the next daily time does not invalidate today's Taken response",
      );
      const search =
        (await q("select aira_shared_context($1,1,'dog Pepper') r", [A]))[0].r;
      assert(
        search.recentConversation.some((turn: any) =>
          turn.text.includes("Pepper")
        ),
        "Full-text terms retrieve words separated in older call text",
      );
      await q("select aira_update_call_context($1,$2,1,$3)", [
        A,
        native.conversation.id,
        { recentUserCaptions: ["I grow roses"] },
      ]);
      await q("select aira_update_call_context($1,$2,1,$3)", [
        A,
        native.conversation.id,
        { cueSummary: null, selfReportedFeeling: "happy" },
      ]);
      const liveContext = (await q(
        "select context from realtime_sessions where conversation_id=$1",
        [native.conversation.id],
      ))[0].context;
      assert(
        liveContext.recentUserCaptions[0] === "I grow roses" &&
          liveContext.selfReportedFeeling === "happy",
        "Atomic face context merges preserve spoken action evidence",
      );
      await q("select aira_memory_edit($1,$2,2,null)", [A, saved.id]);
      context = (await q("select aira_shared_context($1,2) r", [A]))[0].r;
      assert(
        context.recentConversation.length === 0 &&
          context.memories.length === 0,
        "Forgotten memory cannot reappear from old text/calls",
      );
      await fails(() =>
        q("select aira_conversation_action($1,1,$2,$3,$4)", [
          A,
          native.conversation.id,
          memory,
          native.callBinding,
        ]), "state_conflict");
      await q("select aira_delete_call_transcript($1,$2)", [
        A,
        native.conversation.id,
      ]);
      assert(
        (await q("select consent_version from profiles where id=$1", [A]))[0]
          .consent_version === 3,
        "Transcript deletion revokes stale model context",
      );
      await db.exec(
        `set role authenticated;select set_config('request.jwt.claim.sub','${B}',false);`,
      );
      assert(
        (await q("select * from memories")).length === 0 &&
          (await q("select * from schedules")).length === 0,
        "RLS isolates notes and schedules",
      );
      await fails(
        () => q("select aira_shared_context($1,3)", [A]),
        "permission denied",
      );
    } finally {
      await db.close();
    }
  },
});
Deno.test("Native save tool validates per-call ownership and user-caption evidence without OpenAI", async () => {
  let writes = 0;
  const call = "44ee9271-2f32-46a0-844d-f6ae504ed4d5",
    binding = "binding-only-for-this-call-1234567890";
  const fetcher: typeof fetch = async (url, init) => {
    assert(
      String(url).startsWith("https://db.test/"),
      "Native calls never use OpenAI",
    );
    if (String(url).includes("/realtime_sessions?")) {
      return Response.json([{
        user_id: A,
        consent_version: 2,
        call_binding: binding,
        context: { recentUserCaptions: ["I grow tomatoes"] },
      }]);
    }
    if (String(url).includes("/profiles?")) {
      return Response.json([{
        consent_version: 2,
        consents: { memory: true },
      }]);
    }
    if (String(url).includes("/aira_conversation_action")) {
      const body = JSON.parse(String(init?.body));
      assert(
        body.p_user === A && body.p_binding === binding &&
          body.p_conversation === call,
        "Model cannot choose a foreign user",
      );
      writes++;
      return Response.json({
        kind: "memory",
        label: "Enjoys tomatoes",
        status: "saved",
      });
    }
    throw Error("Unexpected request");
  };
  const db = new Database("https://db.test", "test-key", fetcher);
  const payload = {
    callId: call,
    callBinding: binding,
    userId: B,
    action: "remember",
    key: "favorite-plant",
    text: "Enjoys tomatoes",
    category: "preference",
    sourceQuote: "I grow tomatoes",
  };
  const request = (body: unknown) =>
    new Request("https://api.test", {
      method: "POST",
      body: JSON.stringify(body),
    });
  const result = await handleNativeCallTool(request(payload), db);
  assert(
    result.status === "saved" && writes === 1,
    "Grounded action saved exactly once",
  );
  await fails(
    () =>
      handleNativeCallTool(request({ ...payload, callBinding: "wrong" }), db),
    "Please start a new call",
  );
  const ungrounded = await handleNativeCallTool(
    request({ ...payload, sourceQuote: "Aira says you like roses" }),
    db,
  );
  assert(
    ungrounded.status === "needs_confirmation" && writes === 1,
    "Assistant or facial guesses cannot mutate memory",
  );
});

Deno.test("Text action extraction keeps provider drafts separate from confirmed save receipts", async () => {
  const { createHandler } = await import("../functions/aira-api/index.ts");
  const call = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
  let writes = 0, screens = 0;
  const fetcher: typeof fetch = async (input, init) => {
    const url = String(input),
      body = init?.body ? JSON.parse(String(init.body)) : null;
    if (url.includes("/profiles?")) {
      return Response.json([{
        id: A,
        consent_version: 1,
        display_name: "Casey",
        consents: { memory: true, conversation_storage: true },
      }]);
    }
    if (url.includes("/aira_reserve_message")) {
      return Response.json({
        request: { id: call, conversation_id: call },
        duplicate: false,
      });
    }
    if (
      url.includes("/aira_save_message_input") ||
      url.includes("/aira_finish_message")
    ) return Response.json(true);
    if (url.includes("/aira_shared_context")) {
      return Response.json({
        memories: [],
        plans: [],
        recentConversation: [],
        timezone: "Asia/Singapore",
        now: new Date().toISOString(),
      });
    }
    if (url.includes("/aira_conversation_action")) {
      writes++;
      assert(
        body.p_user === A && body.p_version === 1 &&
          body.p_action.sourceQuote === "I love mangoes",
        "Only attributable owner action reaches storage",
      );
      return Response.json({
        kind: "memory",
        id: call,
        label: "Loves mangoes",
        status: "saved",
      });
    }
    if (url === "https://api.openai.com/v1/responses") {
      let result;
      if (body.text.format.name === "aira_screening") {
        screens++;
        result = {
          safe: true,
          concern: "none",
          immediate: false,
          selfDirected: false,
          current: false,
          quotedOrHistorical: false,
          evidence: "",
          reason: "safe fixture",
        };
      } else {
        assert(
          body.text.format.strict === true,
          "Structured actions are schema-constrained",
        );
        result = {
          reply: "Mangoes! Sunshine with a peel, hehe.",
          actions: [{
            kind: "memory",
            key: "favorite-fruit",
            sourceQuote: "I love mangoes",
            text: "Loves mangoes",
            category: "preference",
            label: "",
            dueAt: "",
            instructions: "",
            recurrence: "once",
          }],
        };
      }
      return Response.json({
        status: "completed",
        output: [{
          type: "message",
          content: [{ type: "output_text", text: JSON.stringify(result) }],
        }],
      });
    }
    throw Error(`Unexpected endpoint ${url}`);
  };
  const get = (
    key: string,
  ) => ({
    SUPABASE_URL: "https://db.test",
    SUPABASE_SECRET_KEY: "sb_secret_test",
    OPENAI_API_KEY: "test",
    OPENAI_MODEL: "test",
  }[key] ?? "");
  const result = await createHandler(get, fetcher, async () => A)(
    new Request("https://api.test/aira-api/v1/messages", {
      method: "POST",
      body: JSON.stringify({ text: "I love mangoes", clientMessageId: call }),
    }),
  );
  const body = await result.json();
  assert(
    result.status === 200 && writes === 1 && screens === 2 &&
      body.actions[0].status === "saved" &&
      body.text.includes("Remembered: Loves mangoes"),
    "Only successful persistence produces a durable save receipt",
  );
});
