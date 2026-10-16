import { createHandler } from "../aira-api/index.ts";
import { ApiError, boundedText } from "../_shared/domain.ts";
import { bridgeAuthorized, verifyCall } from "../_shared/realtime.ts";
import {
  Database,
  type Env,
  env,
  jsonBody,
  supabaseServerKey,
} from "../_shared/runtime.ts";
async function turnId(conversation: string, messages: unknown) {
  const hash = new Uint8Array(
    await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(JSON.stringify([conversation, messages])),
    ),
  );
  hash[6] = (hash[6] & 15) | 80;
  hash[8] = (hash[8] & 63) | 128;
  const hex = Array.from(
    hash.slice(0, 16),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${
    hex.slice(16, 20)
  }-${hex.slice(20)}`;
}
export function realtimeHandler(get: Env = env, fetcher: typeof fetch = fetch) {
  return async (req: Request): Promise<Response> => {
    const headers = {
      "Cache-Control": "no-store",
      "Content-Type": "application/json",
    };
    try {
      if (
        req.method !== "POST" ||
        !bridgeAuthorized(req.headers.get("authorization"), get)
      ) throw new ApiError(401, "unauthorized", "Call authorization required.");
      const b = await jsonBody(req, 262144);
      const claims = await verifyCall(
        b.elevenlabs_extra_body?.aira_session_token,
        get("AIRA_CALL_SIGNING_SECRET"),
      );
      const db = new Database(
        get("SUPABASE_URL"),
        supabaseServerKey(get),
        fetcher,
      );
      async function valid() {
        const [p, s, c] = await Promise.all([
          db.one("profiles", `id=eq.${claims.user}&enabled=eq.true`),
          db.one(
            "realtime_sessions",
            `conversation_id=eq.${claims.conversation}&user_id=eq.${claims.user}&expires_at=gt.${
              encodeURIComponent(new Date().toISOString())
            }`,
          ),
          db.one(
            "conversations",
            `id=eq.${claims.conversation}&user_id=eq.${claims.user}&ended_at=is.null`,
          ),
        ]);
        if (
          !p || !s || !c || p.consent_version !== claims.version ||
          s.consent_version !== claims.version || claims.expires <= Date.now()
        ) throw new ApiError(409, "call_expired", "Please start a new call.");
        return { p, s, c };
      }
      const { s, c } = await valid();
      if (!Array.isArray(b.messages) || b.messages.length > 400) {
        throw new ApiError(400, "invalid_messages", "Invalid call turn.");
      }
      // Discard provider system prompts/tools; only our own trusted prompt can direct Aira.
      const messages = b.messages.filter((m: any) =>
        ["user", "assistant"].includes(m?.role) && typeof m.content === "string"
      );
      const last = messages.at(-1);
      if (!last || last.role !== "user") {
        throw new ApiError(400, "invalid_messages", "A user turn is required.");
      }
      const internal = new Request(
        `${get("SUPABASE_URL")}/functions/v1/aira-api/v1/messages`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            clientMessageId: await turnId(claims.conversation, messages),
            conversationId: claims.conversation,
            text: boundedText(last.content),
            mode: c.mode,
            contextVersion: claims.version,
            context: messages.slice(0, -1).slice(-10).map((m: any) => ({
              role: m.role,
              text: m.content,
            })),
            ...s.context,
          }),
        },
      );
      // Identity comes only from the verified provider secret and signed live session above.
      const result = await createHandler(get, fetcher, async () => claims.user)(
        internal,
      );
      const output = await result.json();
      if (!result.ok || typeof output.text !== "string") {
        throw new ApiError(503, "reply_unavailable", "Please try again.");
      }
      await valid(); // End, revocation or deletion during generation must not release the answer.
      const id = `chatcmpl-${output.messageId}`;
      const base = {
        id,
        object: "chat.completion.chunk",
        created: Math.floor(Date.now() / 1000),
        model: "aira-screened-openai",
      };
      if (b.stream === true) {
        // Buffer until screening finishes: unchecked model tokens are never spoken.
        const chunks = [
          {
            ...base,
            choices: [{
              index: 0,
              delta: { role: "assistant", content: output.text },
              finish_reason: null,
            }],
          },
          {
            ...base,
            choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
          },
        ];
        return new Response(
          chunks.map((x) => `data: ${JSON.stringify(x)}\n\n`).join("") +
            "data: [DONE]\n\n",
          { headers: { ...headers, "Content-Type": "text/event-stream" } },
        );
      }
      return new Response(
        JSON.stringify({
          ...base,
          object: "chat.completion",
          choices: [{
            index: 0,
            message: { role: "assistant", content: output.text },
            finish_reason: "stop",
          }],
        }),
        { headers },
      );
    } catch (e) {
      const error = e instanceof ApiError ? e : new ApiError(
        503,
        "call_unavailable",
        "Call temporarily unavailable.",
      );
      return new Response(
        JSON.stringify({ error: { message: error.message, code: error.code } }),
        { status: error.status, headers },
      );
    }
  };
}
if (import.meta.main) Deno.serve(realtimeHandler());
