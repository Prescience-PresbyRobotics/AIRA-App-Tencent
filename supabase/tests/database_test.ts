// Runs real PostgreSQL semantics in WASM. Auth schema is a minimal test stand-in;
// hosted Supabase Auth, Edge gateway and real RLS JWT behavior still need staging proof.
import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
const A = "d49f2c15-337f-4133-b9e8-54cf914d6fd3",
  B = "43ee9271-2f32-46a0-844d-f6ae504ed4d5",
  C = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
function assert(v: unknown, msg = "Assertion failed") {
  if (!v) throw new Error(msg);
}
Deno.test({
  name:
    "Database ownership, privacy, deduplication, reminders and consent-gated test reports",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = new PGlite();
    try {
      await db.exec(
        `create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon,service_role;`,
      );
      const migration = await Deno.readTextFile(
        new URL("../migrations/202610140001_aira_core.sql", import.meta.url),
      );
      await db.exec(
        migration.replace(
          "create extension if not exists pgcrypto;",
          "-- pgcrypto not required by the tested functions; gen_random_uuid is PostgreSQL built-in.",
        ),
      );
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
        (await q("select * from messages")).length === 0,
        "Forgetting removes stale context",
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
