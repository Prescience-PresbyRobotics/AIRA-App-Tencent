export class ApiError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string, message: string) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
export const SAFETY_VERSION = "prototype-safety-v1";
export const SAFE_FALLBACK =
  "I'm having trouble checking my reply. Please try again in a moment. If you need support now, contact someone you trust. I have not contacted anyone for you.";
export const SUPPORT_REPLY =
  "I'm sorry things feel difficult right now. Are you safe at the moment? If you might act on thoughts of harming yourself, contact local emergency services or a person you trust who can stay with you. This prototype cannot send help or contact anyone outside its test inbox.";
export const CONSENTS = [
  "conversation_storage",
  "memory",
  "social_reminders",
  "medication_reminders",
  "monitoring",
  "impact",
  "mood_history",
  "face_cues",
  "urgent_sharing",
  "reviewed_sharing",
  "admin_insights",
];
export function uuid(value: unknown, label = "id"): string {
  if (
    typeof value !== "string" ||
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(value)
  ) throw new ApiError(400, "invalid_input", `A valid ${label} is required.`);
  return value;
}
export function boundedText(
  value: unknown,
  max = 2000,
  label = "text",
): string {
  if (typeof value !== "string" || !value.trim() || value.length > max) {
    throw new ApiError(
      400,
      "invalid_input",
      `${label} must contain 1–${max} characters.`,
    );
  }
  return value.trim();
}
export function preferences(
  value: Record<string, unknown>,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const key of Object.keys(value)) {
    if (
      ![
        "display_name",
        "timezone",
        "text_scale",
        "reduced_motion",
        "consents",
        "onboarded",
      ].includes(key)
    ) {
      throw new ApiError(
        400,
        "invalid_preference",
        `Unsupported preference: ${key}`,
      );
    }
  }
  if (value.display_name !== undefined) {
    if (
      typeof value.display_name !== "string" || value.display_name.length > 80
    ) throw new ApiError(400, "invalid_input", "Name is too long.");
    out.display_name = value.display_name;
  }
  if (value.timezone !== undefined) {
    try {
      new Intl.DateTimeFormat("en", { timeZone: String(value.timezone) });
    } catch {
      throw new ApiError(400, "invalid_timezone", "Choose a valid timezone.");
    }
    out.timezone = value.timezone;
  }
  if (value.text_scale !== undefined) {
    if (
      typeof value.text_scale !== "number" || value.text_scale < 1 ||
      value.text_scale > 2
    ) {
      throw new ApiError(
        400,
        "invalid_input",
        "Text scale must be between 1 and 2.",
      );
    }
    out.text_scale = value.text_scale;
  }
  if (value.reduced_motion !== undefined) {
    if (typeof value.reduced_motion !== "boolean") {
      throw new ApiError(
        400,
        "invalid_input",
        "Reduced motion must be true or false.",
      );
    }
    out.reduced_motion = value.reduced_motion;
  }
  if (value.onboarded !== undefined) {
    if (typeof value.onboarded !== "boolean") {
      throw new ApiError(
        400,
        "invalid_input",
        "Onboarding must be true or false.",
      );
    }
    out.onboarded = value.onboarded;
  }
  if (value.consents !== undefined) {
    if (
      !value.consents || typeof value.consents !== "object" ||
      Array.isArray(value.consents)
    ) {
      throw new ApiError(
        400,
        "invalid_input",
        "Consent choices must be an object.",
      );
    }
    for (const [key, v] of Object.entries(value.consents)) {
      if (!CONSENTS.includes(key) || typeof v !== "boolean") {
        throw new ApiError(
          400,
          "invalid_consent",
          "Consent must use supported true/false choices.",
        );
      }
    }
    out.consents = value.consents;
  }
  return out;
}
export type SafetyResult = {
  safe: boolean;
  concern:
    | "none"
    | "self_harm"
    | "harmful_advice"
    | "belief_reinforcement"
    | "dependency"
    | "uncertain";
  immediate: boolean;
  selfDirected: boolean;
  current: boolean;
  quotedOrHistorical: boolean;
  evidence: string;
  reason: string;
};
export function parseSafety(raw: string): SafetyResult {
  let obj: SafetyResult;
  try {
    obj = JSON.parse(raw);
  } catch {
    throw new ApiError(
      503,
      "screening_unavailable",
      "Reply screening is unavailable.",
    );
  }
  if (
    !obj || typeof obj.safe !== "boolean" ||
    ![
      "none",
      "self_harm",
      "harmful_advice",
      "belief_reinforcement",
      "dependency",
      "uncertain",
    ].includes(obj.concern) ||
    ["immediate", "selfDirected", "current", "quotedOrHistorical"].some((k) =>
      typeof obj[k as keyof SafetyResult] !== "boolean"
    ) || typeof obj.evidence !== "string" || typeof obj.reason !== "string"
  ) {
    throw new ApiError(
      503,
      "screening_unavailable",
      "Reply screening is unavailable.",
    );
  }
  return obj;
}
// Conservative prototype qualification; unvalidated and never a medical assessment.
// A model opinion alone cannot qualify an urgent route: attributable current text must match.
export function qualifiesUrgent(result: SafetyResult, text: string): boolean {
  if (
    result.concern !== "self_harm" || !result.immediate ||
    !result.selfDirected || !result.current || result.quotedOrHistorical ||
    !result.evidence || !text.includes(result.evidence)
  ) return false;
  if (
    /\b(not|never|used to|yesterday|years? ago|story|quote|said|my friend|my mother|my father)\b/i
      .test(text)
  ) return false;
  return /\b(i am|i'm|i will|i intend to|i want to)\b[\s\S]{0,80}\b(kill myself|end my life|hurt myself)\b[\s\S]{0,50}\b(now|tonight|today)\b/i
    .test(text);
}
export function outputAllowed(result: SafetyResult): boolean {
  return result.safe && result.concern === "none";
}
export function outputText(value: unknown): string {
  const v = value as {
    status?: string;
    output?: { type: string; content?: { type: string; text?: string }[] }[];
  };
  if (v?.status && v.status !== "completed") {
    throw new ApiError(
      503,
      "provider_incomplete",
      "The response was incomplete.",
    );
  }
  const text = (v?.output ?? []).filter((x) => x.type === "message").flatMap(
    (x) => x.content ?? [],
  ).filter((x) => x.type === "output_text").map((x) => x.text ?? "").join("");
  if (!text.trim()) {
    throw new ApiError(
      503,
      "provider_empty",
      "AIRA could not prepare a reply.",
    );
  }
  return text;
}
export function localDate(now: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(now);
  const p = (type: string) => parts.find((x) => x.type === type)?.value;
  return `${p("year")}-${p("month")}-${p("day")}`;
}
export function shiftDate(day: string, delta: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + delta);
  return d.toISOString().slice(0, 10);
}
export function weeklyPeriod(now: Date, timeZone: string) {
  const today = localDate(now, timeZone);
  return {
    period_start: shiftDate(today, -7),
    period_end: shiftDate(today, -1),
    timezone: timeZone,
    question_version: "aira-lonely-days-en-v1",
  };
}
export function safeContext(
  value: unknown,
): { role: string; content: string }[] {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.length > 10) {
    throw new ApiError(
      400,
      "invalid_context",
      "At most ten recent turns are allowed.",
    );
  }
  return value.map((x) => {
    if (!x || !["user", "assistant"].includes(x.role)) {
      throw new ApiError(400, "invalid_context", "Invalid context role.");
    }
    return { role: x.role, content: boundedText(x.text, 2000) };
  });
}
export function exactOrigin(origin: string | null, allowed: string[]): boolean {
  return origin === null || allowed.includes(origin);
}
export function sameSecret(a: string, b: string): boolean {
  if (!a || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
const encode = (v: Uint8Array) =>
  btoa(String.fromCharCode(...v)).replaceAll("+", "-").replaceAll("/", "_")
    .replaceAll("=", "");
const decode = (v: string) =>
  Uint8Array.from(
    atob(v.replaceAll("-", "+").replaceAll("_", "/")),
    (x) => x.charCodeAt(0),
  );
async function signingKey(secret: string) {
  if (secret.length < 32) {
    throw new ApiError(
      503,
      "voice_unavailable",
      "Voice signing is not configured.",
    );
  }
  return crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}
export async function signSpeech(
  payload: Record<string, unknown>,
  secret: string,
): Promise<string> {
  const body = encode(new TextEncoder().encode(JSON.stringify(payload)));
  return `${body}.${
    encode(
      new Uint8Array(
        await crypto.subtle.sign(
          "HMAC",
          await signingKey(secret),
          new TextEncoder().encode(body),
        ),
      ),
    )
  }`;
}
export async function verifySpeech(
  token: string,
  secret: string,
  user: string,
  version: number,
  now = Date.now(),
): Promise<{ text: string; requestId: string }> {
  try {
    const [body, sig, ...extra] = token.split(".");
    if (extra.length || !body || !sig) throw new Error();
    if (
      !await crypto.subtle.verify(
        "HMAC",
        await signingKey(secret),
        decode(sig),
        new TextEncoder().encode(body),
      )
    ) throw new Error();
    const payload = JSON.parse(new TextDecoder().decode(decode(body)));
    if (
      payload.user !== user || payload.version !== version ||
      typeof payload.exp !== "number" || payload.exp < now ||
      payload.exp > now + 310000
    ) throw new Error();
    return {
      text: boundedText(payload.text, 4000),
      requestId: uuid(payload.requestId),
    };
  } catch {
    throw new ApiError(
      403,
      "invalid_speech_token",
      "This approved reply has expired. Send another message to continue.",
    );
  }
}
