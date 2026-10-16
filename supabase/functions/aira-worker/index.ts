import { sameSecret } from "../_shared/domain.ts";
import { syncPendingCallTranscripts } from "../_shared/native_calls.ts";
import {
  Database,
  type Env,
  env,
  supabaseServerKey,
} from "../_shared/runtime.ts";
export function createWorker(get: Env = env, fetcher: typeof fetch = fetch) {
  return async (req: Request) => {
    const secret = get("AIRA_WORKER_SECRET");
    if (
      req.method !== "POST" || secret.length < 32 ||
      !sameSecret(req.headers.get("x-aira-worker-secret") ?? "", secret)
    ) {
      return new Response('{"code":"unauthorized"}', {
        status: 401,
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": "no-store",
        },
      });
    }
    try {
      const db = new Database(
        get("SUPABASE_URL"),
        supabaseServerKey(get),
        fetcher,
      );
      // The SQL tick atomically creates incoming-call invitations as well as
      // existing reminders. Provider transcript recovery is independently
      // bounded and must never stop a due invitation from being delivered.
      const result = await db.rpc("aira_worker_tick");
      const callTranscriptsSynced = result.busy
        ? 0
        : await syncPendingCallTranscripts(db, get, fetcher, 5).catch(() => 0);
      return Response.json({ ...result, callTranscriptsSynced }, {
        headers: { "Cache-Control": "no-store" },
      });
    } catch {
      return Response.json({ code: "worker_failed" }, { status: 503 });
    }
  };
}
if (import.meta.main) Deno.serve(createWorker());
