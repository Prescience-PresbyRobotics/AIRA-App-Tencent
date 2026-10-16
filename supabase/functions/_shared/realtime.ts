import { ApiError, sameSecret, uuid } from "./domain.ts";
import { type Env, requireEnv } from "./runtime.ts";
export type CallClaims = {
  user: string;
  conversation: string;
  version: number;
  expires: number;
};
const encoder = new TextEncoder();
const encode = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_")
    .replace(/=+$/, "");
const decode = (s: string) =>
  Uint8Array.from(
    atob(s.replaceAll("-", "+").replaceAll("_", "/")),
    (c) => c.charCodeAt(0),
  );
async function key(secret: string) {
  if (secret.length < 32) {
    throw new ApiError(
      503,
      "not_configured",
      "Live calls are not configured yet.",
    );
  }
  return await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}
export async function signCall(claims: CallClaims, secret: string) {
  const payload = encode(encoder.encode(JSON.stringify(claims)));
  const sig = await crypto.subtle.sign(
    "HMAC",
    await key(secret),
    encoder.encode(payload),
  );
  return `${payload}.${encode(new Uint8Array(sig))}`;
}
export async function verifyCall(
  token: unknown,
  secret: string,
  now = Date.now(),
): Promise<CallClaims> {
  try {
    if (typeof token !== "string" || token.length > 2048) throw Error();
    const [payload, signature, extra] = token.split(".");
    if (
      extra || !signature ||
      !await crypto.subtle.verify(
        "HMAC",
        await key(secret),
        decode(signature),
        encoder.encode(payload),
      )
    ) throw Error();
    const c = JSON.parse(new TextDecoder().decode(decode(payload)));
    uuid(c.user);
    uuid(c.conversation);
    if (
      !Number.isInteger(c.version) || !Number.isFinite(c.expires) ||
      c.expires <= now || c.expires > now + 31 * 60000
    ) throw Error();
    return c;
  } catch {
    throw new ApiError(401, "call_expired", "Please start a new call.");
  }
}
export function bridgeAuthorized(header: string | null, get: Env) {
  const secret = get("AIRA_REALTIME_BRIDGE_SECRET");
  return secret.length >= 32 && sameSecret(header ?? "", `Bearer ${secret}`);
}
export function realtimeConfigured(get: Env) {
  return !!get("ELEVENLABS_AGENT_ID") && !!get("ELEVENLABS_API_KEY");
}
export async function conversationToken(get: Env, fetcher = fetch) {
  const r = await fetcher(
    `https://api.elevenlabs.io/v1/convai/conversation/token?agent_id=${
      encodeURIComponent(requireEnv(get, "ELEVENLABS_AGENT_ID"))
    }`,
    {
      headers: { "xi-api-key": requireEnv(get, "ELEVENLABS_API_KEY") },
      signal: AbortSignal.timeout(15000),
    },
  );
  const b = await r.json().catch(() => ({}));
  if (!r.ok || typeof b.token !== "string") {
    throw new ApiError(
      503,
      "call_unavailable",
      "Aira couldn't connect the call. Please try again.",
    );
  }
  return b.token as string;
}
export function callContext(body: any, faceAllowed: boolean) {
  let cueSummary = null;
  if (
    faceAllowed && body.cueSummary &&
    [
      "neutral",
      "happy",
      "sad",
      "angry",
      "fearful",
      "disgusted",
      "surprised",
      "unknown",
    ].includes(body.cueSummary.label) &&
    Math.abs(Date.now() - Date.parse(body.cueSummary.observedAt)) < 15000
  ) {
    cueSummary = {
      label: body.cueSummary.label,
      observedAt: body.cueSummary.observedAt,
    };
  }
  const selfReportedFeeling =
    ["happy", "sad", "worried", "calm", "mixed", "okay", "tired"].includes(
        body.selfReportedFeeling,
      )
      ? body.selfReportedFeeling
      : null;
  return { cueSummary, selfReportedFeeling };
}
