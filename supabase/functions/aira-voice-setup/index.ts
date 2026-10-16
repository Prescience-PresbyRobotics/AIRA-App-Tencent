// One-time infrastructure setup. Deploy explicitly, invoke with worker secret, then delete.
import { sameSecret } from "../_shared/domain.ts";
import { FIRST_GREETING, FRIEND_PROMPT } from "../_shared/providers.ts";
import { env } from "../_shared/runtime.ts";
Deno.serve(async (req) => {
  const secret = env("AIRA_WORKER_SECRET");
  const reply = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), {
      status,
      headers: {
        "Content-Type": "application/json",
        "Cache-Control": "no-store",
      },
    });
  if (
    req.method !== "POST" || secret.length < 32 ||
    !sameSecret(req.headers.get("x-aira-worker-secret") ?? "", secret)
  ) return reply({ error: "unauthorized" }, 401);
  const key = env("ELEVENLABS_API_KEY"),
    bridge = env("AIRA_REALTIME_BRIDGE_SECRET");
  if (!key || bridge.length < 32) {
    return reply({ error: "missing_configuration" }, 503);
  }
  async function api(path: string, method: string, body: unknown) {
    const r = await fetch(`https://api.elevenlabs.io/v1/convai/${path}`, {
      method,
      headers: { "xi-api-key": key, "Content-Type": "application/json" },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(30000),
    });
    const b = await r.json().catch(() => ({}));
    if (!r.ok) {
      throw {
        status: r.status,
        fields: Array.isArray(b.detail)
          ? b.detail.map((d: any) => ({
            path: d.loc,
            message: String(d.msg ?? "").replaceAll(key, "[redacted]")
              .replaceAll(bridge, "[redacted]"),
          }))
          : [],
        message: String(b.detail?.message ?? "").replaceAll(key, "[redacted]")
          .replaceAll(bridge, "[redacted]").slice(0, 800),
        code: typeof b.detail?.status === "string"
          ? b.detail.status
          : "provider_error",
      };
    }
    return b;
  }
  try {
    const operation = await req.json().catch(() => ({}));
    if (env("ELEVENLABS_AGENT_ID") && operation.action !== "voices") {
      const agentId = encodeURIComponent(env("ELEVENLABS_AGENT_ID"));
      const path = operation.action === "connection-test"
        ? `conversation/get-signed-url?agent_id=${agentId}`
        : `agents/${agentId}`;
      const r = await fetch(`https://api.elevenlabs.io/v1/convai/${path}`, {
        headers: { "xi-api-key": key },
      });
      const b = await r.json();
      if (!r.ok) {
        return reply({ error: "agent_read_failed", status: r.status }, 502);
      }
      if (operation.action === "connection-test") {
        return reply({ signedUrl: b.signed_url });
      }
      return reply({
        agentId: b.agent_id,
        voiceId: b.conversation_config?.tts?.voice_id,
        auth: b.platform_settings?.auth,
        privacy: b.platform_settings?.privacy,
        model: b.conversation_config?.agent?.prompt?.llm,
        customLlmUrl: b.conversation_config?.agent?.prompt?.custom_llm?.url,
        backup: b.conversation_config?.agent?.prompt?.backup_llm_config,
        overrides: b.platform_settings?.overrides,
        configured: true,
      });
    }
    if (operation.action === "voices") {
      const r = await fetch("https://api.elevenlabs.io/v1/voices", {
        headers: { "xi-api-key": key },
      });
      const b = await r.json();
      return reply({
        voices: (b.voices ?? []).filter((v: any) => v.category !== "cloned")
          .map((v: any) => ({
            id: v.voice_id,
            name: v.name,
            category: v.category,
            labels: v.labels,
          })).slice(0, 40),
      });
    }
    const stored = await api("secrets", "POST", {
      type: "new",
      name: "AIRA screened OpenAI bridge",
      value: bridge,
    });
    const settings = {
      name: "AIRA App — screened OpenAI live companion",
      conversation_config: {
        agent: {
          language: "en",
          first_message: FIRST_GREETING,
          disable_first_message_interruptions: false,
          dynamic_variables: {
            dynamic_variable_placeholders: { aira_name: "friend" },
          },
          prompt: {
            prompt: FRIEND_PROMPT,
            llm: "custom-llm",
            ignore_default_personality: true,
            max_tokens: 250,
            custom_llm: {
              url: `${
                env("SUPABASE_URL")
              }/functions/v1/aira-realtime/chat/completions`,
              model_id: "aira-screened-openai",
              api_type: "chat_completions",
              api_key: { secret_id: stored.secret_id },
            },
            backup_llm_config: { preference: "disabled" },
            cascade_timeout_seconds: 10,
          },
        },
        tts: {
          voice_id: env("ELEVENLABS_REALTIME_VOICE_ID") ||
            env("ELEVENLABS_VOICE_ID"),
          model_id: "eleven_flash_v2",
        },
        turn: {
          turn_timeout: 15,
          silence_end_call_timeout: 120,
          turn_eagerness: "patient",
        },
        conversation: {
          max_duration_seconds: 900,
          client_events: [
            "audio",
            "interruption",
            "user_transcript",
            "agent_response",
            "agent_response_correction",
          ],
          file_input: { enabled: false },
        },
      },
      platform_settings: {
        auth: { enable_auth: true },
        overrides: { custom_llm_extra_body: true },
        privacy: {
          record_voice: false,
          retention_days: 0, // Scheduled deletion; not the provider's separate Zero Retention Mode.
          delete_transcript_and_pii: true,
          delete_audio: true,
          zero_retention_mode: false,
        },
        call_limits: {
          agent_concurrency_limit: 3,
          daily_limit: 50,
          bursting_enabled: false,
        },
        data_collection: {},
        evaluation: { criteria: [] },
      },
    };
    const result = await api("agents/create", "POST", settings);
    return reply({
      agentId: result.agent_id,
      secretId: stored.secret_id,
      configured: true,
    });
  } catch (e) {
    // Only provider status and field paths are safe to expose; never echo request bodies/secrets.
    const x = e as any;
    return reply({
      error: "setup_failed",
      providerStatus: x.status ?? null,
      message: x.message ?? "",
      fields: x.fields ?? [],
      code: x.code ?? "unknown",
    }, 502);
  }
});
