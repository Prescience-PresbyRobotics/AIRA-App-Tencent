import { validateAction } from "../functions/_shared/conversation_actions.ts";
import {
  nativeAgentSettings,
  nativeConversationTool,
} from "../functions/_shared/voice_agent.ts";

function assert(value: unknown, message: string) {
  if (!value) throw new Error(message);
}

Deno.test("Native tool memory categories interoperate with backend action validation", () => {
  const tool = nativeConversationTool("https://project.example/functions/v1/aira-api/");
  const schema = tool.tool_config.api_schema.request_body_schema;
  for (const category of schema.properties.category.enum) {
    const action = validateAction({
      kind: "memory", key: "favorite-plant", category,
      text: "Enjoys growing roses", sourceQuote: "I enjoy growing roses",
    }, "I enjoy growing roses.");
    assert(action.category === category, "Agent category must be accepted by the server");
  }
  assert(schema.required.includes("callId") && schema.required.includes("callBinding"),
    "Every native tool request must carry both bound call identifiers");
  assert(schema.properties.callId.dynamic_variable === "aira_call_id" &&
    schema.properties.callBinding.dynamic_variable === "aira_call_binding",
    "Call authorization is injected from dynamic variables rather than model arguments");
  assert(tool.tool_config.api_schema.url === "https://project.example/functions/v1/aira-api/v1/call-tools",
    "The tool must target the supported bound webhook route");
});

Deno.test("Requested voice setup keeps a private native agent without an OpenAI bridge or filler", () => {
  const settings = nativeAgentSettings("La9lzDJ3mmfNhhQA06WM", ["tool-test-only"]);
  const prompt = settings.conversation_config.agent.prompt;
  assert(settings.conversation_config.tts.voice_id === "La9lzDJ3mmfNhhQA06WM", "Requested kid voice preserved");
  assert(prompt.llm === "deepseek-v41-flash" && prompt.custom_llm === null &&
    prompt.backup_llm_config.preference === "disabled", "No custom or fallback OpenAI live call route");
  assert(settings.platform_settings.auth.enable_auth, "Public unauthenticated agent access remains disabled");
  assert(prompt.tool_ids.includes("tool-test-only"), "The save/search tool must be attached");
  assert(settings.conversation_config.turn.soft_timeout_config.timeout_seconds < 0 &&
    nativeConversationTool("https://project.example").tool_config.pre_tool_speech === "off",
    "Neither turn timeout nor tool execution should introduce thinking filler");
});
