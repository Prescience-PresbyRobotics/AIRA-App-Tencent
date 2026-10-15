import { ApiError } from "../functions/_shared/domain.ts";
import { type Env, supabaseServerKey } from "../functions/_shared/runtime.ts";
import { createHandler } from "../functions/aira-api/index.ts";
import { createWorker } from "../functions/aira-worker/index.ts";

const modern = "sb_secret_test_only_default";
const named = "sb_secret_test_only_named";
const legacy = "legacy.test.jwt";
const user = "d49f2c15-337f-4133-b9e8-54cf914d6fd3";
const getEnv = (values: Record<string, string | undefined>): Env => (name) =>
  values[name] ?? "";
function equal(actual: unknown, expected: unknown) {
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("Unexpected result");
  }
}

Deno.test("Server key selection prefers the configured modern key and supports legacy runtimes", () => {
  const common = {
    SUPABASE_SECRET_KEYS: JSON.stringify({ default: modern, worker: named }),
    SUPABASE_SECRET_KEY: "sb_secret_test_only_single",
    SUPABASE_SERVICE_ROLE_KEY: legacy,
  };
  equal(supabaseServerKey(getEnv(common)), modern);
  equal(
    supabaseServerKey(getEnv({
      ...common,
      AIRA_SUPABASE_SECRET_KEY_NAME: "worker",
    })),
    named,
  );
  equal(
    supabaseServerKey(getEnv({
      SUPABASE_SECRET_KEY: modern,
      SUPABASE_SERVICE_ROLE_KEY: legacy,
    })),
    modern,
  );
  equal(
    supabaseServerKey(getEnv({ SUPABASE_SERVICE_ROLE_KEY: legacy })),
    legacy,
  );
});

Deno.test("Invalid or missing selected modern keys fail closed without leaking configuration", () => {
  for (
    const values of [
      { SUPABASE_SECRET_KEYS: "malformed-private-value" },
      { SUPABASE_SECRET_KEYS: "[]" },
      { SUPABASE_SECRET_KEYS: "null" },
      { SUPABASE_SECRET_KEYS: JSON.stringify({ worker: named }) },
      { SUPABASE_SECRET_KEYS: JSON.stringify({ default: 123 }) },
      {
        SUPABASE_SECRET_KEYS: JSON.stringify({
          default: "sb_publishable_test",
        }),
      },
      { SUPABASE_SECRET_KEYS: JSON.stringify({ default: "" }) },
      { SUPABASE_SECRET_KEY: "sb_publishable_test" },
      { AIRA_SUPABASE_SECRET_KEY_NAME: "missing" },
      {
        SUPABASE_SECRET_KEYS: JSON.stringify({ default: modern }),
        AIRA_SUPABASE_SECRET_KEY_NAME: "missing",
      },
    ]
  ) {
    let rejected = false;
    try {
      supabaseServerKey(
        getEnv({ SUPABASE_SERVICE_ROLE_KEY: legacy, ...values }),
      );
    } catch (error) {
      rejected = error instanceof ApiError && error.status === 503 &&
        error.code === "not_configured" &&
        error.message === "This service is not configured yet.";
    }
    equal(rejected, true);
  }
  let missingRejected = false;
  try {
    supabaseServerKey(getEnv({}));
  } catch (error) {
    missingRejected = error instanceof ApiError &&
      error.code === "not_configured";
  }
  equal(missingRejected, true);
});

Deno.test("API keeps user authentication separate from modern and legacy database credentials", async () => {
  for (const key of [modern, legacy]) {
    const calls: string[] = [];
    const get = getEnv({
      SUPABASE_URL: "https://supabase.test",
      ...(key === modern
        ? { SUPABASE_SECRET_KEYS: JSON.stringify({ default: key }) }
        : { SUPABASE_SERVICE_ROLE_KEY: key }),
    });
    const handler = createHandler(get, async (input, init) => {
      const url = String(input);
      const headers = new Headers(init?.headers);
      equal(headers.get("apikey"), key);
      calls.push(url);
      if (url.endsWith("/auth/v1/user")) {
        equal(headers.get("Authorization"), "Bearer current.user.token");
        return Response.json({ id: user });
      }
      equal(
        headers.get("Authorization"),
        key === modern ? null : `Bearer ${key}`,
      );
      if (url.includes("/profiles?")) {
        return Response.json([{ id: user, consents: {}, text_scale: 1 }]);
      }
      if (url.includes("/role_assignments?")) return Response.json([]);
      throw new Error("Unexpected request");
    });
    const response = await handler(
      new Request("https://api.test/aira-api/v1/me", {
        headers: { Authorization: "Bearer current.user.token" },
      }),
    );
    equal(response.status, 200);
    equal((await response.json()).profile.id, user);
    equal(calls.length, 3);
    equal(calls[0], "https://supabase.test/auth/v1/user");
  }
});

Deno.test("Rejected Auth tokens cannot reach the database with a modern server key", async () => {
  let calls = 0;
  const handler = createHandler(
    getEnv({
      SUPABASE_URL: "https://supabase.test",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: modern }),
    }),
    async (input) => {
      equal(String(input), "https://supabase.test/auth/v1/user");
      calls++;
      return Response.json({ error: "invalid token" }, { status: 401 });
    },
  );
  const response = await handler(
    new Request("https://api.test/aira-api/v1/me", {
      headers: { Authorization: "Bearer invalid.user.token" },
    }),
  );
  equal(response.status, 401);
  equal(calls, 1);
});

Deno.test("Authorized worker uses the modern server key only in the apikey header", async () => {
  const workerSecret = "test-worker-secret-".repeat(3);
  let calls = 0;
  const worker = createWorker(
    getEnv({
      SUPABASE_URL: "https://supabase.test",
      SUPABASE_SECRET_KEYS: JSON.stringify({ default: modern }),
      AIRA_WORKER_SECRET: workerSecret,
    }),
    async (input, init) => {
      equal(
        String(input),
        "https://supabase.test/rest/v1/rpc/aira_worker_tick",
      );
      const headers = new Headers(init?.headers);
      equal(headers.get("apikey"), modern);
      equal(headers.get("Authorization"), null);
      equal(headers.get("x-aira-worker-secret"), null);
      calls++;
      return Response.json({
        events: 0,
        testReports: 0,
        externalDelivery: false,
      });
    },
  );
  const response = await worker(
    new Request("https://api.test/aira-worker", {
      method: "POST",
      headers: { "x-aira-worker-secret": workerSecret },
    }),
  );
  equal(response.status, 200);
  equal(calls, 1);
});
