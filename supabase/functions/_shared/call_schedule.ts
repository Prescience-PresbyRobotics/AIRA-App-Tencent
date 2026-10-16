import { ApiError, uuid } from "./domain.ts";
import { Database, jsonBody } from "./runtime.ts";

function expectedVersion(value: unknown, optional = false): number | null {
  if (optional && value === undefined) return null;
  if (!Number.isInteger(value) || Number(value) < 1) {
    throw new ApiError(
      400,
      "version_required",
      "Refresh your call schedule and try again.",
    );
  }
  return Number(value);
}

export function scheduleInput(body: Record<string, unknown>) {
  const { localTime, timeZone, enabled } = body;
  if (
    typeof localTime !== "string" ||
    !/^([01]\d|2[0-3]):[0-5]\d$/.test(localTime)
  ) {
    throw new ApiError(400, "invalid_time", "Choose a time for Aira to call.");
  }
  if (typeof timeZone !== "string" || timeZone.length > 100) {
    throw new ApiError(400, "invalid_timezone", "Choose a valid time zone.");
  }
  try {
    new Intl.DateTimeFormat("en", { timeZone }).format(new Date());
  } catch {
    throw new ApiError(400, "invalid_timezone", "Choose a valid time zone.");
  }
  if (typeof enabled !== "boolean") {
    throw new ApiError(
      400,
      "invalid_schedule",
      "Choose whether scheduled calls are on.",
    );
  }
  return {
    localTime,
    timeZone,
    enabled,
    expectedVersion: expectedVersion(body.expectedVersion, true),
  };
}

/** Called only after the API has authenticated an enabled profile. All writes
 * and acceptance races are resolved in owner-bound database transactions. */
export async function handleCallSchedule(
  path: string,
  method: string,
  req: Request,
  context: { db: Database; user: string; profile?: unknown },
): Promise<{ body: unknown; status?: number } | null> {
  const { db, user } = context;
  if (path === "/v1/call-schedule" && method === "GET") {
    return { body: await db.rpc("aira_call_schedule_get", { p_user: user }) };
  }
  if (path === "/v1/call-schedule" && method === "PATCH") {
    const input = scheduleInput(await jsonBody(req, 2048));
    return {
      body: await db.rpc("aira_call_schedule_save", {
        p_user: user,
        p_local_time: input.localTime,
        p_timezone: input.timeZone,
        p_enabled: input.enabled,
        p_version: input.expectedVersion,
      }),
    };
  }
  if (path === "/v1/call-schedule" && method === "DELETE") {
    const body = await jsonBody(req, 1024);
    return {
      body: await db.rpc("aira_call_schedule_delete", {
        p_user: user,
        p_version: expectedVersion(body.expectedVersion),
      }),
    };
  }
  const invitation = path.match(/^\/v1\/scheduled-calls\/([^/]+)\/respond$/);
  if (invitation && method === "POST") {
    const body = await jsonBody(req, 1024);
    if (body.action !== "accept" && body.action !== "decline") {
      throw new ApiError(400, "invalid_action", "Accept or decline this call.");
    }
    return {
      body: await db.rpc("aira_scheduled_call_respond", {
        p_user: user,
        p_id: uuid(invitation[1]),
        p_action: body.action,
        p_request: uuid(body.requestId),
        p_version: expectedVersion(body.expectedVersion),
      }),
    };
  }
  return null;
}
