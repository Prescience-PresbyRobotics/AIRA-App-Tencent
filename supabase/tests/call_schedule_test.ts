import { PGlite } from "npm:@electric-sql/pglite@0.3.14";
import { ApiError } from "../functions/_shared/domain.ts";
import {
  handleCallSchedule,
  scheduleInput,
} from "../functions/_shared/call_schedule.ts";
import { Database } from "../functions/_shared/runtime.ts";
import { createWorker } from "../functions/aira-worker/index.ts";

const A = "d49f2c15-337f-4133-b9e8-54cf914d6fd3";
const B = "43ee9271-2f32-46a0-844d-f6ae504ed4d5";
const C = "44ee9271-2f32-46a0-844d-f6ae504ed4d5";
const migrations = [
  "202610140001_aira_core.sql",
  "202610160001_realtime_calls.sql",
  "202610160002_durable_history.sql",
  "202610160003_pending_history.sql",
  "202610160004_native_call_archives.sql",
  "202610160005_scheduled_calls.sql",
];
function assert(value: unknown, message = "Assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
function equal(value: unknown, expected: unknown) {
  assert(
    JSON.stringify(value) === JSON.stringify(expected),
    `Unexpected result: ${JSON.stringify(value)}`,
  );
}
async function fails(fn: () => unknown | Promise<unknown>, message: string) {
  try {
    await fn();
  } catch (error) {
    assert(
      String(error).includes(message),
      `Expected ${message}, got ${String(error)}`,
    );
    return;
  }
  throw new Error(`Expected ${message}`);
}

Deno.test("Call scheduling validates wall-clock inputs and owner-binds every RPC", async () => {
  for (const localTime of ["24:00", "9:00", "12:60", "09:00:00", null]) {
    await fails(
      () =>
        scheduleInput({ localTime, timeZone: "Asia/Singapore", enabled: true }),
      "Choose a time",
    );
  }
  for (const timeZone of ["not/a/zone", "", null]) {
    await fails(
      () => scheduleInput({ localTime: "09:00", timeZone, enabled: true }),
      "time zone",
    );
  }
  await fails(
    () =>
      scheduleInput({ localTime: "09:00", timeZone: "UTC", enabled: "true" }),
    "whether scheduled calls",
  );
  await fails(
    () =>
      scheduleInput({
        localTime: "09:00",
        timeZone: "UTC",
        enabled: true,
        expectedVersion: 0,
      }),
    "Refresh",
  );
  equal(
    scheduleInput({
      localTime: "09:05",
      timeZone: "Asia/Singapore",
      enabled: true,
    }).expectedVersion,
    null,
  );
  const calls: { name: string; body: any }[] = [];
  const db = new Database(
    "https://supabase.test",
    "sb_secret_test",
    async (input, init) => {
      calls.push({
        name: new URL(String(input)).pathname.split("/").pop()!,
        body: JSON.parse(String(init?.body)),
      });
      return Response.json({
        schedule: null,
        incomingCall: null,
        foregroundOnly: true,
      });
    },
  );
  const run = (method: string, path: string, body?: any) =>
    handleCallSchedule(
      `/v1${path}`,
      method,
      new Request(`https://api.test/v1${path}`, {
        method,
        ...(body ? { body: JSON.stringify(body) } : {}),
      }),
      { db, user: A },
    );
  await run("GET", "/call-schedule");
  await run("PATCH", "/call-schedule", {
    user: B,
    localTime: "09:05",
    timeZone: "Asia/Singapore",
    enabled: true,
  });
  await run("DELETE", "/call-schedule", { expectedVersion: 3 });
  await run("POST", `/scheduled-calls/${C}/respond`, {
    action: "accept",
    requestId: B,
    expectedVersion: 1,
  });
  equal(calls.map((call) => call.name), [
    "aira_call_schedule_get",
    "aira_call_schedule_save",
    "aira_call_schedule_delete",
    "aira_scheduled_call_respond",
  ]);
  assert(
    calls.every((call) => call.body.p_user === A),
    "A body cannot impersonate a different owner",
  );
  equal(calls[1].body, {
    p_user: A,
    p_local_time: "09:05",
    p_timezone: "Asia/Singapore",
    p_enabled: true,
    p_version: null,
  });
  equal(await run("GET", "/unrelated"), null);
  try {
    await run("POST", `/scheduled-calls/${C}/respond`, {
      action: "answer-without-consent",
      requestId: B,
      expectedVersion: 1,
    });
    throw new Error("Expected rejection");
  } catch (error) {
    assert(error instanceof ApiError && error.status === 400);
  }
  equal(calls.length, 4);
});

Deno.test({
  name:
    "Daily incoming calls are durable, timezone-aware, deduplicated and accepted only once by their owner",
  sanitizeOps: false,
  sanitizeResources: false,
  fn: async () => {
    const db = new PGlite();
    const q = async (sql: string, args: any[] = []) =>
      (await db.query<any>(sql, args)).rows;
    const value = async (sql: string, args: any[] = []) =>
      (await q(sql, args))[0].value;
    try {
      await db.exec(
        "create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create function auth.uid() returns uuid language sql stable as $$select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid$$;grant usage on schema public,auth to authenticated,anon,service_role;",
      );
      for (const name of migrations) {
        const source = await Deno.readTextFile(
          new URL(`../migrations/${name}`, import.meta.url),
        );
        await db.exec(
          source.replace("create extension if not exists pgcrypto;", ""),
        );
      }
      await q("insert into auth.users(id) values($1),($2)", [A, B]);
      equal(
        (await value("select aira_call_schedule_get($1) value", [A])).schedule,
        null,
      );
      let saved = await value(
        "select aira_call_schedule_save($1,'09:30','Asia/Singapore',true,null) value",
        [A],
      );
      equal(saved.schedule.localTime, "09:30");
      equal(saved.schedule.timeZone, "Asia/Singapore");
      equal(saved.foregroundOnly, true);
      assert(Date.parse(saved.schedule.nextCallAt) > Date.now());
      equal(
        (await value("select aira_call_schedule_get($1) value", [B])).schedule,
        null,
      );
      await fails(
        () =>
          q("select aira_call_schedule_save($1,'10:00','UTC',true,null)", [A]),
        "state_conflict",
      );
      await fails(
        () => q("select aira_call_schedule_save($1,'24:00','UTC',true,1)", [A]),
        "state_conflict",
      );
      await fails(
        () =>
          q("select aira_call_schedule_save($1,'10:00','Fake/Zone',true,1)", [
            A,
          ]),
        "state_conflict",
      );
      const next = await value(
        "select aira_next_daily_call('09:30','Asia/Singapore','2026-10-16T02:00:00Z')::text value",
      );
      equal(Date.parse(next), Date.parse("2026-10-17T01:30:00Z"));
      const spring = await value(
        "select aira_next_daily_call('02:30','America/New_York','2026-03-08T06:00:00Z')::text value",
      );
      equal(Date.parse(spring), Date.parse("2026-03-08T07:30:00Z"));
      const fall = await value(
        "select aira_next_daily_call('01:30','America/New_York','2026-11-01T07:00:00Z')::text value",
      );
      equal(Date.parse(fall), Date.parse("2026-11-02T06:30:00Z"));

      // Explicitly chosen calls run even when optional social invitations are off.
      await q(
        "update profiles set social_paused_until=now()+interval '1 day' where id=$1",
        [A],
      );
      await q(
        "update call_schedules set next_due_at=now()-interval '30 seconds' where user_id=$1",
        [A],
      );
      const tick = await value("select aira_worker_tick() value");
      equal(tick.scheduledCalls, 1);
      await q("select aira_worker_tick()");
      saved = await value("select aira_call_schedule_get($1) value", [A]);
      const invitation = saved.incomingCall;
      equal(invitation.state, "ringing");
      equal((await q("select * from scheduled_call_invitations")).length, 1);
      assert(Date.parse(saved.schedule.nextCallAt) > Date.now());
      await fails(
        () =>
          q("select aira_scheduled_call_respond($1,$2,'accept',$3,1)", [
            B,
            invitation.id,
            crypto.randomUUID(),
          ]),
        "forbidden",
      );
      await fails(
        () =>
          q("select aira_reserve_scheduled_call($1,$2,'voice',1)", [
            A,
            invitation.id,
          ]),
        "state_conflict",
      );
      const request = crypto.randomUUID();
      const accepted = await value(
        "select aira_scheduled_call_respond($1,$2,'accept',$3,1) value",
        [A, invitation.id, request],
      );
      equal(accepted.startCall, true);
      equal(
        (await value(
          "select aira_scheduled_call_respond($1,$2,'accept',$3,1) value",
          [A, invitation.id, request],
        )).invitation.version,
        2,
      );
      await fails(
        () =>
          q("select aira_scheduled_call_respond($1,$2,'decline',$3,1)", [
            A,
            invitation.id,
            request,
          ]),
        "state_conflict",
      );
      await fails(
        () =>
          q("select aira_scheduled_call_respond($1,$2,'accept',$3,1)", [
            A,
            invitation.id,
            crypto.randomUUID(),
          ]),
        "state_conflict",
      );
      await fails(
        () =>
          q("select aira_reserve_scheduled_call($1,$2,'video',1)", [
            A,
            invitation.id,
          ]),
        "state_conflict",
      );
      const call = await value(
        "select aira_reserve_scheduled_call($1,$2,'voice',1) value",
        [A, invitation.id],
      );
      equal(call.conversation.initiator, "aira");
      equal(call.session.user_id, A);
      assert(
        call.callBinding.length >= 32,
        "Native agent binding survives scheduled reservation",
      );
      await fails(
        () =>
          q("select aira_reserve_scheduled_call($1,$2,'voice',1)", [
            A,
            invitation.id,
          ]),
        "state_conflict",
      );
      equal(
        (await value(
          "select aira_scheduled_call_respond($1,$2,'accept',$3,1) value",
          [A, invitation.id, request],
        )).startCall,
        false,
      );
      equal(
        (await q("select * from conversations where user_id=$1", [A])).length,
        1,
      );

      // Already on a call, old overdue times and expired rings never ring later.
      await q(
        "update call_schedules set next_due_at=now()-interval '15 seconds' where user_id=$1",
        [A],
      );
      equal(
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall,
        null,
      );
      await q("update conversations set ended_at=now() where id=$1", [
        call.conversation.id,
      ]);
      await q(
        "update call_schedules set next_due_at=now()-interval '1 hour' where user_id=$1",
        [A],
      );
      equal(
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall,
        null,
      );
      equal(
        (await q(
          "select * from scheduled_call_invitations where state='missed'",
        )).length,
        2,
      );
      await q(
        "update call_schedules set next_due_at=now()-interval '10 seconds' where user_id=$1",
        [A],
      );
      const fresh =
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall;
      await q(
        "update scheduled_call_invitations set expires_at=now()-interval '1 second' where id=$1",
        [fresh.id],
      );
      await fails(
        () =>
          q("select aira_scheduled_call_respond($1,$2,'accept',$3,1)", [
            A,
            fresh.id,
            crypto.randomUUID(),
          ]),
        "state_conflict",
      );
      equal(
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall,
        null,
      );

      await q(
        "update call_schedules set next_due_at=now()-interval '8 seconds',created_at=now()-interval '30 days' where user_id=$1",
        [A],
      );
      const declined =
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall;
      const declinedRequest = crypto.randomUUID();
      const declinedResult = await value(
        "select aira_scheduled_call_respond($1,$2,'decline',$3,1) value",
        [A, declined.id, declinedRequest],
      );
      equal(declinedResult.startCall, false);
      equal(declinedResult.invitation.state, "declined");
      equal(
        (await value(
          "select aira_scheduled_call_respond($1,$2,'decline',$3,1) value",
          [A, declined.id, declinedRequest],
        )).invitation.version,
        2,
      );
      await fails(
        () =>
          q("select aira_reserve_scheduled_call($1,$2,'voice',1)", [
            A,
            declined.id,
          ]),
        "state_conflict",
      );
      await q("select aira_worker_tick()");
      assert(
        (await value("select aira_call_schedule_get($1) value", [A])).schedule
          .enabled,
        "Declining one call does not disable the durable daily schedule",
      );

      await q(
        "update call_schedules set next_due_at=now()-interval '5 seconds' where user_id=$1",
        [A],
      );
      const cancelled =
        (await value("select aira_call_schedule_get($1) value", [A]))
          .incomingCall;
      const updated = await value(
        "select aira_call_schedule_save($1,'11:30','UTC',false,1) value",
        [A],
      );
      equal(updated.schedule.enabled, false);
      equal(updated.schedule.nextCallAt, null);
      equal(
        (await q("select state from scheduled_call_invitations where id=$1", [
          cancelled.id,
        ]))[0].state,
        "cancelled",
      );
      await fails(
        () =>
          q("select aira_scheduled_call_respond($1,$2,'accept',$3,1)", [
            A,
            cancelled.id,
            crypto.randomUUID(),
          ]),
        "state_conflict",
      );
      await fails(
        () => q("select aira_call_schedule_delete($1,1)", [A]),
        "state_conflict",
      );
      equal(
        (await value("select aira_call_schedule_delete($1,2) value", [A]))
          .schedule,
        null,
      );
      equal(
        (await q("select * from scheduled_call_invitations where user_id=$1", [
          A,
        ])).length,
        0,
      );

      for (const viewer of [A, B]) {
        await db.exec(
          `set role authenticated;select set_config('request.jwt.claim.sub','${viewer}',false);`,
        );
        await fails(
          () => q("select * from call_schedules"),
          "permission denied",
        );
        await fails(
          () => q("select * from scheduled_call_invitations"),
          "permission denied",
        );
        await fails(
          () => q("select aira_call_schedule_get($1)", [A]),
          "permission denied",
        );
        await fails(
          () =>
            q("select aira_reserve_scheduled_call($1,$2,'voice',1)", [
              A,
              invitation.id,
            ]),
          "permission denied",
        );
        await fails(
          () => q("select aira_worker_tick_before_scheduled_calls()"),
          "permission denied",
        );
        await db.exec("reset role;");
      }

      // New feature defaults do not overwrite existing accounts or grant roles.
      await db.exec(
        await Deno.readTextFile(
          new URL(
            "../migrations/202610160006_feature_defaults.sql",
            import.meta.url,
          ),
        ),
      );
      await q("insert into auth.users(id) values($1)", [C]);
      const oldDefaults =
        (await q("select consents from profiles where id=$1", [A]))[0].consents;
      assert(Object.values(oldDefaults).every((value) => value === false));
      const newDefaults =
        (await q("select consents from profiles where id=$1", [C]))[0].consents;
      assert(
        Object.keys(newDefaults).length === 11 &&
          Object.values(newDefaults).every((value) => value === true),
      );
      equal(
        (await q("select * from role_assignments where user_id=$1", [C]))
          .length,
        0,
      );
      equal(
        (await q(
          "select * from caregiver_links where senior_id=$1 or caregiver_id=$1",
          [C],
        )).length,
        0,
      );
      equal(
        (await value("select aira_call_schedule_get($1) value", [C])).schedule,
        null,
      );
      await q("select aira_call_schedule_save($1,'11:30','UTC',true,null)", [
        A,
      ]);
      await q("select aira_purge($1)", [A]);
      equal(
        (await q("select * from call_schedules where user_id=$1", [A])).length,
        0,
      );
      await fails(
        () => q("select aira_call_schedule_get($1)", [A]),
        "forbidden",
      );
    } finally {
      await db.close();
    }
  },
});

Deno.test("Transcript recovery failure cannot prevent successful scheduled-call worker result", async () => {
  const secret = "synthetic-test-worker-secret-".repeat(2);
  const handler = createWorker(
    (
      key,
    ) => ({
      AIRA_WORKER_SECRET: secret,
      SUPABASE_URL: "https://supabase.test",
      SUPABASE_SECRET_KEY: "sb_secret_synthetic",
    }[key] ?? ""),
    async (input) => {
      if (String(input).includes("/rpc/aira_worker_tick")) {
        return Response.json({
          events: 0,
          scheduledCalls: 1,
          externalDelivery: false,
        });
      }
      throw new Error("Transient transcript service failure");
    },
  );
  const response = await handler(
    new Request("https://api.test/worker", {
      method: "POST",
      headers: { "x-aira-worker-secret": secret },
    }),
  );
  equal(response.status, 200);
  equal(await response.json(), {
    events: 0,
    scheduledCalls: 1,
    externalDelivery: false,
    callTranscriptsSynced: 0,
  });
});
