// Retired on 16 October 2026. Calls now run entirely in ElevenLabs Agents.
// Keep a non-forwarding response for old browser builds during rollout.
export function realtimeHandler(..._unused: unknown[]) {
  return (_req: Request): Promise<Response> =>
    Promise.resolve(Response.json({
      code: "call_upgrade_required",
      message: "Please refresh AIRA to start a live ElevenLabs call.",
    }, { status: 410, headers: { "Cache-Control": "no-store" } }));
}
if (import.meta.main) Deno.serve(realtimeHandler());
