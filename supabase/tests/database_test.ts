// Runs real PostgreSQL semantics in WASM. Auth schema is a minimal test stand-in;
// hosted Supabase Auth, Edge gateway and real RLS JWT behavior still need staging proof.
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
const A = "d49f2c15-337f-4133-b9e8-54cf914d6fd3",
  B = "43ee9271-2f32-46a0-844d-f6ae504ed4d5",
  C = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
function assert(v: unknown, msg = "Assertion failed") {
  if (!v) throw new Error(msg);
}
async function database() {
  const db = new PGlite();
  await db.exec(
    `create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon,service_role;`,
  );
  for (
    const name of [
      "202610140001_aira_core.sql",
      "202610160001_realtime_calls.sql",
      "202610160002_durable_history.sql",
      "202610160003_pending_history.sql",
      "202610160004_native_call_archives.sql",
    ]
  ) {
    const migration = await Deno.readTextFile(
      new URL(`../migrations/${name}`, import.meta.url),
    );
    await db.exec(migration.replace(
      "create extension if not exists pgcrypto;",
      "-- pgcrypto not required by the tested functions; gen_random_uuid is PostgreSQL built-in.",
    ));
  }

  return db;
}
async function fails(fn: () => Promise<unknown>, message: string) {
  try {
    await fn();
  } catch (e) {
    assert(
      String(e).includes(message),
      `Expected ${message}, received ${String(e)}`,
    );
    return;
  }
  throw new Error(`Expected ${message}`);
}
Deno.test({
  name:
    "Database ownership, privacy, deduplication, reminders and consent-gated test reports",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    try {
      await db.query("insert into auth.users(id) values($1),($2),($3)", [
        A,
        B,
        C,
      ]);
      const q = async (sql: string, args: any[] = []) =>
        (await db.query<any>(sql, args)).rows;
      await q(
        `select aira_preferences($1,'{"consents":{"memory":true,"medication_reminders":true,"monitoring":true,"urgent_sharing":true,"reviewed_sharing":true,"impact":true}}')`,
        [A],
      );
      const memory = (await q(
        "insert into memories(user_id,text) values($1,$2) returning id",
        [A, "Enjoys gardening"],
      ))[0];
      await db.exec(
        `set role authenticated;select set_config('request.jwt.claim.sub','${B}',false);`,
      );
      assert(
        (await q("select * from memories")).length === 0,
        "Other user cannot read memory",
      );
      let denied = false;
      try {
        await q("update profiles set enabled=true where id=$1", [B]);
      } catch {
        denied = true;
      }
      assert(denied, "Client cannot write profile security fields");
      denied = false;
      try {
        await q("select aira_purge($1)", [A]);
      } catch {
        denied = true;
      }
      assert(denied, "Client cannot call service RPC as another owner");
      await db.exec("reset role;");
      const client = crypto.randomUUID();
      const r =
        (await q("select aira_reserve_message($1,$2,null,$3) as result", [
          A,
          client,
          "text",
        ]))[0].result;
      const r2 =
        (await q("select aira_reserve_message($1,$2,null,$3) as result", [
          A,
          client,
          "text",
        ]))[0].result;
      assert(
        r.request.id === r2.request.id && r2.duplicate,
        "Retry returns one logical request",
      );
      await q("select aira_finish_message($1,$2,$3,$4,2)", [
        A,
        r.request.id,
        "hello",
        "Welcome",
      ]);
      assert(
        (await q("select * from messages")).length === 0,
        "Storage disabled never stores transcript",
      );
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":true}}')`,
        [A],
      );
      const stored =
        (await q("select aira_reserve_message($1,$2,null,$3) as result", [
          A,
          crypto.randomUUID(),
          "text",
        ]))[0].result;
      await q("select aira_finish_message($1,$2,$3,$4,3)", [
        A,
        stored.request.id,
        "hello",
        "Hello",
      ]);
      assert(
        (await q("select * from messages")).length === 2,
        "Opted-in transcript stores both sides",
      );
      await q("select aira_memory_edit($1,$2,1,null)", [A, memory.id]);
      assert(
        (await q("select * from messages")).length === 2,
        "Forgetting preserves the visible conversation archive",
      );
      assert(
        (await q(
          "select * from messages where context_version=(select consent_version from profiles where id=$1)",
          [A],
        )).length === 0,
        "Forgetting excludes old archived turns from future model context",
      );
      assert(
        (await q("select consent_version from profiles where id=$1", [A]))[0]
          .consent_version === 4,
        "Forgetting invalidates speech and client context",
      );
      const schedule = (await q(
        `insert into schedules(user_id,kind,label,due_at,timezone,confirmed) values($1,'medication','Synthetic test medication',now()-interval '1 minute','Asia/Singapore',true) returning id`,
        [A],
      ))[0];
      await q("select aira_worker_tick()");
      await q("select aira_worker_tick()");
      const events = await q(
        "select * from foreground_events where schedule_id=$1",
        [schedule.id],
      );
      assert(events.length === 1, "Worker retry creates one occurrence");
      const requestId = crypto.randomUUID();
      await q(`select aira_event_action($1,$2,'taken',$3,1,null)`, [
        A,
        events[0].id,
        requestId,
      ]);
      await q(`select aira_event_action($1,$2,'taken',$3,1,null)`, [
        A,
        events[0].id,
        requestId,
      ]);
      assert(
        (await q("select action_version from foreground_events where id=$1", [
          events[0].id,
        ]))[0].action_version === 2,
        "Repeated action does not duplicate self-report",
      );
      await q(
        `insert into caregiver_links(senior_id,caregiver_id,verified,scopes) values($1,$2,true,array['urgent','reviewed'])`,
        [A, C],
      );
      const incident = (await q(
        `select aira_incident($1,$2,'test','test current danger','Synthetic fixture','urgent',true) id`,
        [A, r.request.id],
      ))[0].id;
      assert(
        (await q("select * from test_report_outbox where incident_id=$1", [
          incident,
        ])).length === 1,
        "Urgent queues before review",
      );
      await q("select aira_worker_tick()");
      const report =
        (await q("select * from test_report_outbox where incident_id=$1", [
          incident,
        ]))[0];
      assert(
        report.state === "test_delivered" && !report.external_delivery,
        "Worker has internal test delivery only",
      );
      const review = (await q(
        `select aira_incident($1,$2,'test','ambiguous concern','Synthetic fixture','review',true) id`,
        [A, stored.request.id],
      ))[0].id;
      assert(
        (await q("select * from test_report_outbox where incident_id=$1", [
          review,
        ])).length === 0,
        "Nonurgent report waits for reviewer",
      );
      await q(
        `select aira_preferences($1,'{"consents":{"monitoring":false,"conversation_storage":false}}')`,
        [A],
      );
      assert(
        (await q("select * from incidents")).length === 0,
        "Monitoring withdrawal removes cases and outbox",
      );
      const withheld = (await q(
        `select aira_incident($1,$2,'user','self_harm','Must never persist','urgent',false) id`,
        [A, r.request.id],
      ))[0];
      assert(withheld.id === null, "No monitoring consent means no incident");
      const prompt = (await q("select aira_prompt($1) p", [A]))[0].p;
      const again = (await q("select aira_prompt($1) p", [A]))[0].p;
      assert(prompt.id === again.id, "Prompt retry has fixed period");
      const answerId = crypto.randomUUID();
      await q("select aira_loneliness($1,$2,0,false,$3,0)", [
        A,
        prompt.id,
        answerId,
      ]);
      await q("select aira_loneliness($1,$2,0,false,$3,0)", [
        A,
        prompt.id,
        answerId,
      ]);
      assert(
        (await q("select * from loneliness_responses")).length === 1,
        "Zero is valid and retries do not double count",
      );
      const answered = (await q("select * from loneliness_responses"))[0];
      assert(
        answered.lonely_days === 0 && !answered.skipped,
        "Missing is not zero",
      );
      await q(
        `update measurement_prompts set expires_at=now()-interval '1 second' where id=$1`,
        [prompt.id],
      );
      assert(
        (await q("select aira_prompt($1) p", [A]))[0].p === null,
        "Expiry does not create overlapping daily check-ins",
      );
      await q("select aira_purge($1)", [A]);
      assert(
        (await q("select enabled from profiles where id=$1", [A]))[0]
          .enabled === false,
        "Deletion disables old-token app access",
      );
      assert(
        (await q("select * from schedules where user_id=$1", [A])).length === 0,
        "Deletion cancels scheduled work",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name:
    "Live-call reservation enforces ownership, two active slots, mode, privacy version and worker cleanup",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: any[] = []) =>
      (await db.query<any>(sql, args)).rows;
    const reserve = async (
      user: string,
      mode: unknown = "voice",
      version: unknown = 1,
    ) =>
      (await q("select aira_reserve_call($1,$2,$3) result", [
        user,
        mode,
        version,
      ]))[0].result;
    try {
      await q("insert into auth.users(id) values($1),($2),($3)", [A, B, C]);
      assert(
        (await q(
          "select relrowsecurity from pg_class where oid='public.realtime_sessions'::regclass",
        ))[0].relrowsecurity,
      );
      for (const mode of ["text", "invalid", null]) {
        await fails(() => reserve(A, mode), "invalid_mode");
      }
      for (const version of [0, 2, null]) {
        await fails(() => reserve(A, "voice", version), "state_conflict");
      }
      await q("update profiles set enabled=false where id=$1", [C]);
      await fails(() => reserve(C), "forbidden");
      await fails(() => reserve(crypto.randomUUID()), "forbidden");
      assert(
        (await q("select * from conversations")).length === 0,
        "Rejected reservations do not create orphan conversations",
      );

      await db.exec("set role service_role;");
      const first = await reserve(A);
      const second = await reserve(A, "video");
      await fails(() => reserve(A), "rate_limited");
      await db.exec("reset role;");
      assert(
        first.conversation.user_id === A && first.session.user_id === A,
        "Reservation is bound to its trusted owner",
      );
      assert(
        first.conversation.id === first.session.conversation_id &&
          first.conversation.initiator === "senior",
      );
      assert(
        first.session.consent_version === 1 &&
          second.conversation.mode === "video",
      );
      assert(
        Date.parse(first.session.expires_at) -
            Date.parse(first.conversation.accepted_at) === 15 * 60000,
        "Database sets exactly 15 minutes, independently of caller input",
      );
      assert(
        (await q("select * from conversations where user_id=$1", [A]))
          .length === 2,
        "A full cap does not create an orphan",
      );

      for (const viewer of [A, B]) {
        await db.exec(
          `set role authenticated;select set_config('request.jwt.claim.sub','${viewer}',false);`,
        );
        await fails(
          () => q("select * from realtime_sessions"),
          "permission denied",
        );
        await fails(() => reserve(A), "permission denied");
        await fails(() => q("select aira_worker_tick()"), "permission denied");
        await fails(
          () => q("select aira_worker_tick_core()"),
          "permission denied",
        );
        await db.exec("reset role;");
      }
      // PGlite serializes its one connection; this verifies admission outcomes.
      // The row FOR UPDATE in the RPC provides cross-connection serialization in Postgres.
      const attempts = await Promise.allSettled([
        reserve(B),
        reserve(B),
        reserve(B),
      ]);
      assert(
        attempts.filter((r) => r.status === "fulfilled").length === 2,
        "Only two queued starts acquire slots",
      );
      assert(
        attempts.filter((r) =>
          r.status === "rejected" && String(r.reason).includes("rate_limited")
        ).length === 1,
      );

      await q(
        "update realtime_sessions set expires_at=now()-interval '1 second',context='{\"selfReportedFeeling\":\"sad\"}' where conversation_id=$1",
        [first.conversation.id],
      );
      const replacement = await reserve(A);
      await q("update conversations set ended_at=now() where id=$1", [
        second.conversation.id,
      ]);
      await reserve(A);
      const tick = (await q("select aira_worker_tick() result"))[0].result;
      assert(
        tick.events === 0 && tick.testReports === 0 &&
          tick.externalDelivery === false,
        "Worker retains its existing result contract",
      );
      assert(
        (await q(
          "select * from realtime_sessions where conversation_id=any($1)",
          [[first.conversation.id, second.conversation.id]],
        )).length === 0,
        "One worker tick physically deletes expired and ended session context",
      );
      assert(
        (await q("select ended_at from conversations where id=$1", [
          first.conversation.id,
        ]))[0].ended_at !== null,
        "Expired live conversations are ended",
      );
      assert(
        (await q("select * from realtime_sessions where conversation_id=$1", [
          replacement.conversation.id,
        ])).length === 1,
        "Valid active call survives cleanup",
      );

      await q(
        'select aira_preferences($1,\'{"consents":{"face_cues":false}}\')',
        [A],
      );
      await fails(() => reserve(A, "voice", 1), "state_conflict");
      const current = await reserve(A, "voice", 2);
      await q("select aira_worker_tick()");
      const remaining = await q(
        "select * from realtime_sessions where user_id=$1",
        [A],
      );
      assert(
        remaining.length === 1 &&
          remaining[0].conversation_id === current.conversation.id,
        "Revoked contexts are deleted while the current privacy version survives",
      );
      await q("update profiles set enabled=false where id=$1", [B]);
      await db.exec("set role service_role;");
      await q("select aira_worker_tick()");
      await fails(
        () => q("select aira_worker_tick_core()"),
        "permission denied",
      );
      await db.exec("reset role;");
      assert(
        (await q("select * from realtime_sessions where user_id=$1", [B]))
          .length === 0,
        "The service-role worker removes disabled accounts' ephemeral context",
      );
      await q("select aira_purge($1)", [A]);
      assert(
        (await q("select * from realtime_sessions where user_id=$1", [A]))
          .length === 0,
        "User purge cascades into live sessions",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name:
    "Live message allowance requires an owned, unexpired session and stays bounded",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: any[] = []) =>
      (await db.query<any>(sql, args)).rows;
    try {
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      const call =
        (await q("select aira_reserve_call($1,'voice',1) result", [A]))[0]
          .result;
      const id = call.conversation.id;
      await q(
        "insert into message_requests(user_id,client_id,conversation_id,created_at) select $1,gen_random_uuid(),$2,now()-interval '2 minutes' from generate_series(1,20)",
        [A, id],
      );
      const message = (user: string) =>
        q("select aira_reserve_message($1,$2,$3,'voice') result", [
          user,
          crypto.randomUUID(),
          id,
        ]);
      await db.exec(
        `set role authenticated;select set_config('request.jwt.claim.sub','${A}',false);`,
      );
      await fails(() => message(A), "permission denied");
      await db.exec("reset role;");
      await fails(() => message(B), "conversation_not_found");
      const success = (await message(A))[0].result;
      assert(
        success.request.conversation_id === id,
        "Valid live call can exceed text allowance",
      );
      await q(
        "update realtime_sessions set expires_at=now()-interval '1 second' where conversation_id=$1",
        [id],
      );
      await fails(() => message(A), "conversation_not_found");
      await q("delete from realtime_sessions where conversation_id=$1", [id]);
      await fails(() => message(A), "conversation_not_found");
      const textAfterCall =
        (await q("select aira_reserve_message($1,$2,null,'text') result", [
          A,
          crypto.randomUUID(),
        ]))[0].result;
      assert(
        textAfterCall.request.status === "processing",
        "Spoken turns never exhaust text chat quota",
      );
      await q(
        "insert into realtime_sessions(conversation_id,user_id,consent_version) values($1,$2,1)",
        [id, A],
      );
      await q(
        "insert into message_requests(user_id,client_id,conversation_id,created_at) select $1,gen_random_uuid(),$2,now()-interval '2 minutes' from generate_series(1,99)",
        [A, id],
      );
      await fails(() => message(A), "rate_limited");
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name: "Saved history is durable, paginated, owner-isolated and deletable",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: unknown[] = []) =>
      (await db.query<any>(sql, args)).rows;
    try {
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":true}}')`,
        [A],
      );
      for (let i = 0; i < 3; i++) {
        const r =
          (await q(`select aira_reserve_message($1,$2,null,'text') value`, [
            A,
            crypto.randomUUID(),
          ]))[0].value;
        await q("select aira_finish_message($1,$2,$3,$4,2)", [
          A,
          r.request.id,
          `User ${i}`,
          `Aira ${i}`,
        ]);
      }
      const rows = await q(
        "select text,expires_at::text expiry from messages order by history_order",
      );
      assert(
        rows.length === 6 && rows.every((r: any) => r.expiry === "infinity"),
        "Opted-in transcripts have no timer expiry",
      );
      // Simulate age without altering the permanent retention decision.
      await q(`update conversations set accepted_at=now()-interval '30 days'`);
      await q(
        `update message_requests set created_at=now()-interval '30 days'`,
      );
      await q(`update messages set created_at=now()-interval '30 days'`);
      await q("select aira_worker_tick()");
      assert(
        (await q("select * from messages")).length === 6,
        "Worker does not expire saved chats or cascade their parents",
      );
      const first =
        (await q("select aira_chat_history($1,null,3) value", [A]))[0].value;
      assert(
        first.messages.map((m: any) => m.text).join("|") ===
          "Aira 1|User 2|Aira 2",
        "Newest page is returned in chronological order",
      );
      const second = (await q("select aira_chat_history($1,$2,3) value", [
        A,
        first.nextCursor,
      ]))[0].value;
      assert(
        second.messages.map((m: any) => m.text).join("|") ===
          "User 0|Aira 0|User 1",
        "Exclusive cursor preserves equal-timestamp messages",
      );
      assert(second.nextCursor === null, "Last page has no cursor");
      assert(
        (await q("select aira_chat_history($1,null,3) value", [B]))[0].value
          .messages.length === 0,
        "Other owner never sees history",
      );
      await db.exec(
        `set role authenticated;select set_config('request.jwt.claim.sub','${B}',false);`,
      );
      assert(
        (await q("select * from messages")).length === 0,
        "Direct RLS reads also isolate history",
      );
      await fails(
        () => q("select aira_chat_history($1,null,3)", [A]),
        "permission denied",
      );
      await db.exec("reset role;");
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":false}}')`,
        [A],
      );
      assert(
        (await q("select * from messages")).length === 0,
        "Turning storage off removes saved content",
      );
      assert(
        (await q("select * from conversations where expires_at='infinity'"))
          .length === 0,
        "Opt-out bounds metadata retention",
      );
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":true}}')`,
        [A],
      );
      assert(
        (await q("select aira_chat_history($1,null,3) value", [A]))[0].value
          .messages.length === 0,
        "Re-enabling does not resurrect deleted history",
      );
      const r =
        (await q(`select aira_reserve_message($1,$2,null,'text') value`, [
          A,
          crypto.randomUUID(),
        ]))[0].value;
      await q("select aira_finish_message($1,$2,$3,$4,4)", [
        A,
        r.request.id,
        "After opt-in",
        "Saved again",
      ]);
      const deleted =
        (await q("select aira_clear_chat_history($1) version", [A]))[0];
      assert(
        deleted.version === 5 &&
          (await q("select * from messages")).length === 0,
        "Clear history deletes parents and invalidates old call/context tokens",
      );
      assert(
        (await q("select consents from profiles where id=$1", [A]))[0].consents
          .conversation_storage,
        "Clear history preserves the future saving preference",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name:
    "Delivered outgoing text survives reload before the checked reply finishes",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: unknown[] = []) =>
      (await db.query<any>(sql, args)).rows;
    try {
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":true}}')`,
        [A],
      );
      const r =
        (await q(`select aira_reserve_message($1,$2,null,'text') value`, [
          A,
          crypto.randomUUID(),
        ]))[0].value;
      await q("select aira_save_message_input($1,$2,$3,2)", [
        A,
        r.request.id,
        "Delivered before reply",
      ]);
      const waiting =
        (await q("select aira_chat_history($1,null,50) value", [A]))[0].value
          .messages;
      assert(
        waiting.length === 1 && waiting[0].text === "Delivered before reply" &&
          waiting[0].delivery === "delivered" &&
          waiting[0].requestStatus === "processing",
        "Reload shows the actual delivered user message before assistant output exists",
      );
      await q("select aira_save_message_input($1,$2,$3,2)", [
        A,
        r.request.id,
        "Delivered before reply",
      ]);
      await q("select aira_finish_message($1,$2,$3,$4,2)", [
        A,
        r.request.id,
        "Delivered before reply",
        "Checked reply",
      ]);
      const completed =
        (await q("select aira_chat_history($1,null,50) value", [A]))[0].value
          .messages;
      assert(
        completed.length === 2 && completed[0].delivery === "read" &&
          completed[1].text === "Checked reply",
        "Completion adds one reply and marks the existing user turn read without duplicating it",
      );
      const unstored =
        (await q(`select aira_reserve_message($1,$2,null,'text') value`, [
          B,
          crypto.randomUUID(),
        ]))[0].value;
      await q("select aira_save_message_input($1,$2,$3,1)", [
        B,
        unstored.request.id,
        "No storage permission",
      ]);
      assert(
        (await q("select * from messages where user_id=$1", [B])).length === 0,
        "Outgoing persistence still requires storage consent",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name:
    "Native call archives stay separate, owner-bound, durable, revocable and resistant to stale caption overwrites",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: unknown[] = []) =>
      (await db.query<any>(sql, args)).rows;
    try {
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":true}}')`,
        [A],
      );
      const call =
        (await q("select aira_reserve_call($1,'video',2) value", [A]))[0].value;
      assert(
        call.callBinding.length === 64,
        "Each call has a random binding distinct from its public id",
      );
      const id = call.conversation.id;
      const save = async (
        user: string,
        provider: string,
        entries: any[],
        source = "device_captions",
      ) =>
        (await q(
          "select aira_save_call_transcript($1,$2,$3,$4::jsonb,$5,'ready',null) value",
          [user, id, provider, JSON.stringify(entries), source],
        ))[0].value;
      const device = [{
        role: "user",
        text: "Device caption",
        timeInCallSecs: 1,
      }];
      assert(
        !await save(B, "conv_test", device),
        "Another owner cannot write this call",
      );
      assert(
        await save(A, "conv_test", device),
        "Owner can save device captions",
      );
      await fails(() => save(A, "conv_swapped", device), "state_conflict");
      assert(
        (await q("select aira_chat_history($1,null,50) value", [A]))[0].value
          .messages.length === 0,
        "Call captions never appear in main chat",
      );
      const history =
        (await q("select aira_call_history($1,null,$2) value", [A, id]))[0]
          .value;
      assert(
        history.calls[0].entries[0].text === "Device caption" &&
          history.calls[0].source === "device_captions",
        "Separate detail contains labelled captions",
      );
      assert(
        (await q("select aira_call_history($1,null,$2) value", [B, id]))[0]
          .value.calls.length === 0,
        "Other owner cannot read archive",
      );
      assert(
        !JSON.stringify(history).includes(call.callBinding),
        "Private binding never appears in history",
      );
      const canonical = [{
        role: "assistant",
        text: "Canonical reply",
        timeInCallSecs: 2,
      }];
      assert(
        await save(A, "conv_test", canonical, "elevenlabs"),
        "Verified provider data can replace captions",
      );
      await save(A, "conv_test", [...device, ...device]);
      assert(
        (await q(
          "select entries,source from call_transcripts where conversation_id=$1",
          [id],
        ))[0].entries[0].text === "Canonical reply",
        "Late device events cannot overwrite canonical text",
      );
      await q(
        "update conversations set accepted_at=now()-interval '30 days' where id=$1",
        [id],
      );
      await q("select aira_worker_tick()");
      assert(
        (await q("select aira_call_history($1,null,$2) value", [A, id]))[0]
          .value.calls.length === 1,
        "Saved call text survives the normal content-expiry worker",
      );
      await q("select aira_clear_chat_history($1)", [A]);
      assert(
        (await q("select aira_call_history($1,null,$2) value", [A, id]))[0]
          .value.calls.length === 1,
        "Clearing main chat leaves the separate call archive",
      );
      assert(
        !await save(A, "conv_test", device),
        "Privacy-version changes block late writes",
      );
      await db.exec(
        `set role authenticated;select set_config('request.jwt.claim.sub','${A}',false);`,
      );
      await fails(
        () => q("select * from call_transcripts"),
        "permission denied",
      );
      await fails(
        () => q("select aira_call_history($1,null,null)", [B]),
        "permission denied",
      );
      await db.exec("reset role");
      await q(
        `select aira_preferences($1,'{"consents":{"conversation_storage":false}}')`,
        [A],
      );
      assert(
        (await q("select * from call_transcripts")).length === 0,
        "Turning saving off removes the archive",
      );
      assert(
        !await save(A, "conv_test", device),
        "A late caption cannot recreate deleted history",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test({
  name: "Failed text retry reuses one request without a duplicate bubble",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = await database();
    const q = async (sql: string, args: unknown[] = []) =>
      (await db.query<any>(sql, args)).rows;
    try {
      await q("insert into auth.users(id) values($1)", [A]);
      const client = crypto.randomUUID();
      const first =
        (await q("select aira_reserve_message($1,$2,null,'text') value", [
          A,
          client,
        ]))[0].value;
      await q(
        "update message_requests set status='failed',created_at=now()-interval '5 minutes' where id=$1",
        [
          first.request.id,
        ],
      );
      const retry =
        (await q("select aira_reserve_message($1,$2,null,'text') value", [
          A,
          client,
        ]))[0].value;
      assert(
        !retry.duplicate && retry.request.id === first.request.id &&
          retry.request.status === "processing",
        "Retry resumes the same failed logical message",
      );
      assert(
        (await q("select * from message_requests")).length === 1,
        "Retry does not create another request",
      );
      await q("select aira_worker_tick()");
      assert(
        (await q("select status from message_requests where id=$1", [
          first.request.id,
        ]))[0].status === "processing",
        "Old failed messages receive a fresh processing deadline when retried",
      );
    } finally {
      await db.close();
    }
  },
});
