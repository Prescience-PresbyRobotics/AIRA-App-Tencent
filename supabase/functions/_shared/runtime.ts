import { ApiError } from "./domain.ts";
export type Env = (name: string) => string;
export const env: Env = (name) => Deno.env.get(name) ?? "";
export function requireEnv(get: Env, name: string) {
  const value = get(name);
  if (!value) {
    throw new ApiError(
      503,
      "not_configured",
      "This service is not configured yet.",
    );
  }
  return value;
}
export function supabaseServerKey(get: Env): string {
  const dictionary = get("SUPABASE_SECRET_KEYS");
  const selectedName = get("AIRA_SUPABASE_SECRET_KEY_NAME") || "default";
  let key: unknown;
  if (dictionary) {
    try {
      const keys = JSON.parse(dictionary);
      if (keys && typeof keys === "object" && !Array.isArray(keys)) {
        key = keys[selectedName];
      }
    } catch {
      // Do not fall back to a different privilege source when configuration is invalid.
    }
  } else if (!get("AIRA_SUPABASE_SECRET_KEY_NAME")) {
    // The single-key form supports local runtimes; older projects inject the legacy key.
    key = get("SUPABASE_SECRET_KEY");
    if (!key) return requireEnv(get, "SUPABASE_SERVICE_ROLE_KEY");
  }
  if (
    typeof key !== "string" || !/^sb_secret_[A-Za-z0-9_-]+$/.test(key)
  ) {
    throw new ApiError(
      503,
      "not_configured",
      "This service is not configured yet.",
    );
  }
  return key;
}
export class Database {
  url: string;
  key: string;
  fetcher: typeof fetch;
  constructor(url: string, key: string, fetcher = fetch) {
    this.url = url;
    this.key = key;
    this.fetcher = fetcher;
  }
  async request(path: string, method = "GET", body?: unknown): Promise<any> {
    const res = await this.fetcher(`${this.url}/rest/v1/${path}`, {
      method,
      headers: {
        apikey: this.key,
        // Modern API keys are opaque strings, not JWTs. Legacy service-role JWTs
        // retain their Authorization header for older/local Supabase gateways.
        ...(this.key.startsWith("sb_secret_")
          ? {}
          : { Authorization: `Bearer ${this.key}` }),
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    });
    if (!res.ok) {
      const e = await res.json().catch(() => ({}));
      const detail = String(e.message ?? "");
      if (detail.includes("rate_limited")) {
        throw new ApiError(
          429,
          "rate_limited",
          "Please wait before sending another message.",
        );
      }
      if (/state_conflict|duplicate key/.test(detail)) {
        throw new ApiError(
          409,
          "state_conflict",
          "This item changed. Refresh and try again.",
        );
      }
      if (/forbidden|conversation_not_found|prompt_expired/.test(detail)) {
        throw new ApiError(403, "access_denied", "This item is unavailable.");
      }
      throw new ApiError(
        503,
        "database_unavailable",
        "AIRA could not save this change. Please retry.",
      );
    }
    return res.status === 204 ? null : await res.json();
  }
  async rpc(name: string, args: Record<string, unknown> = {}) {
    return await this.request(`rpc/${name}`, "POST", args);
  }
  async one(table: string, query: string) {
    const rows = await this.request(`${table}?${query}&limit=1`);
    return rows[0] ?? null;
  }
  async insert(table: string, row: Record<string, unknown>) {
    return (await this.request(table, "POST", row))[0];
  }
  async patch(table: string, query: string, row: Record<string, unknown>) {
    return await this.request(`${table}?${query}`, "PATCH", row);
  }
  async remove(table: string, query: string) {
    return await this.request(`${table}?${query}`, "DELETE");
  }
}
export async function authenticate(
  req: Request,
  get: Env,
  fetcher = fetch,
): Promise<string> {
  const auth = req.headers.get("Authorization") ?? "";
  if (!/^Bearer [A-Za-z0-9._-]+$/.test(auth)) {
    throw new ApiError(401, "unauthorized", "Please sign in.");
  }
  const res = await fetcher(`${requireEnv(get, "SUPABASE_URL")}/auth/v1/user`, {
    headers: {
      Authorization: auth,
      apikey: supabaseServerKey(get),
    },
    signal: AbortSignal.timeout(10000),
  });
  if (!res.ok) throw new ApiError(401, "unauthorized", "Please sign in again.");
  const user = await res.json();
  if (!user.id || user.is_anonymous) {
    throw new ApiError(
      403,
      "account_required",
      "Create an email or Google account to continue.",
    );
  }
  return user.id;
}
export async function jsonBody(
  req: Request,
  limit = 32768,
): Promise<Record<string, any>> {
  const declared = Number(req.headers.get("content-length") ?? 0);
  if (declared > limit) {
    throw new ApiError(413, "too_large", "This request is too large.");
  }
  const reader = req.body?.getReader();
  const chunks: Uint8Array[] = [];
  let count = 0;
  if (reader) {
    while (true) {
      const result = await reader.read();
      if (result.done) break;
      count += result.value.byteLength;
      if (count > limit) {
        await reader.cancel();
        throw new ApiError(413, "too_large", "This request is too large.");
      }
      chunks.push(result.value);
    }
  }
  const bytes = new Uint8Array(count);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  const raw = new TextDecoder().decode(bytes);
  try {
    const v = JSON.parse(raw);
    if (!v || typeof v !== "object" || Array.isArray(v)) throw new Error();
    return v;
  } catch {
    throw new ApiError(400, "invalid_json", "The request could not be read.");
  }
}
