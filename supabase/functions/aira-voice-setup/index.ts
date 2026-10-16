// Temporary infrastructure helper. Deploy explicitly, invoke with worker secret, then delete.
import { sameSecret } from "../_shared/domain.ts";
import { env } from "../_shared/runtime.ts";
import { nativeAgentSettings, nativeConversationTool } from "../_shared/voice_agent.ts";
Deno.serve(async (req) => {
  const secret = env("AIRA_WORKER_SECRET");
  const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
    status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
  if (req.method !== "POST" || secret.length < 32 || !sameSecret(req.headers.get("x-aira-worker-secret") ?? "", secret)) {
    return reply({ error: "unauthorized" }, 401);
  }
  const key = env("ELEVENLABS_API_KEY");
  if (!key) return reply({ error: "missing_configuration" }, 503);
  async function api(path: string, method = "GET", body?: unknown) {
    const r = await fetch(`https://api.elevenlabs.io/v1/convai/${path}`, {
      method, headers: { "xi-api-key": key, "Content-Type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    const b = await r.json().catch(() => ({}));
    if (!r.ok) throw {
      status: r.status,
      fields: Array.isArray(b.detail) ? b.detail.map((d: any) => ({path: d.loc, message: String(d.msg ?? "").replaceAll(key, "[redacted]")})) : [],
      message: String(b.detail?.message ?? "").replaceAll(key, "[redacted]").slice(0, 500),
    };
    return b;
  }
  try {
    const operation = await req.json().catch(() => ({}));
    let agentId = env("ELEVENLABS_AGENT_ID");
    if (operation.action === "configure-native") {
      const voiceId = env("ELEVENLABS_REALTIME_VOICE_ID");
      if (!voiceId) return reply({error: "missing_voice"}, 503);
      const apiBase = `${env("SUPABASE_URL")}/functions/v1/aira-api`;
      const tool = nativeConversationTool(apiBase);
      const listed = await api("tools");
      const existing = (listed.tools ?? []).find((t: any) =>
        t.tool_config?.name === tool.tool_config.name && t.tool_config?.api_schema?.url === tool.tool_config.api_schema.url);
      const saved = existing
        ? await api(`tools/${encodeURIComponent(existing.id ?? existing.tool_id)}`, "PATCH", tool)
        : await api("tools", "POST", tool);
      const toolId = saved.id ?? saved.tool_id ?? existing?.id ?? existing?.tool_id;
      if (!toolId) throw {message: "Provider did not return the conversation tool identifier."};
      const settings = nativeAgentSettings(voiceId, [toolId]);
      if (agentId) await api(`agents/${encodeURIComponent(agentId)}`, "PATCH", settings);
      else agentId = (await api("agents/create", "POST", settings)).agent_id;
    } else if (operation.action === "set-requested-voice") {
      if (!agentId) return reply({error: "missing_agent"}, 503);
      await api(`agents/${encodeURIComponent(agentId)}`, "PATCH", {
        conversation_config: {tts: {voice_id: "La9lzDJ3mmfNhhQA06WM", model_id: "eleven_flash_v2"}},
      });
    } else if (operation.action !== "inspect") return reply({error: "unsupported_action"}, 400);
    if (!agentId) return reply({error: "missing_agent"}, 503);
    const b = await api(`agents/${encodeURIComponent(agentId)}`);
    return reply({
      agentId: b.agent_id, name: b.name,
      voiceId: b.conversation_config?.tts?.voice_id,
      authEnabled: b.platform_settings?.auth?.enable_auth,
      privacy: b.platform_settings?.privacy,
      model: b.conversation_config?.agent?.prompt?.llm,
      hasCustomLlm: !!b.conversation_config?.agent?.prompt?.custom_llm?.url,
      backup: b.conversation_config?.agent?.prompt?.backup_llm_config,
      firstMessage: b.conversation_config?.agent?.first_message,
      dynamicVariableNames: Object.keys(b.conversation_config?.agent?.dynamic_variables?.dynamic_variable_placeholders ?? {}),
      asr: b.conversation_config?.asr?.provider,
      softTimeoutSeconds: b.conversation_config?.turn?.soft_timeout_config?.timeout_seconds,
      ttsModel: b.conversation_config?.tts?.model_id,
      toolIds: b.conversation_config?.agent?.prompt?.tool_ids ?? [],
      configured: true,
    });
  } catch (error) {
    const e = error as any;
    return reply({error: "setup_failed", providerStatus: e.status ?? null, fields: e.fields ?? [], message: e.message ?? ""}, 502);
  }
});
