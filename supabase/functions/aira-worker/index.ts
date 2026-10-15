import { sameSecret } from "../_shared/domain.ts";
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
      const result = await new Database(
        get("SUPABASE_URL"),
        supabaseServerKey(get),
        fetcher,
      ).rpc("aira_worker_tick");
      return Response.json(result, {
        headers: { "Cache-Control": "no-store" },
      });
    } catch {
      return Response.json({ code: "worker_failed" }, { status: 503 });
    }
  };
}
if (import.meta.main) Deno.serve(createWorker());
