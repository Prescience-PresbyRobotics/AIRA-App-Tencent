# AIRA-App-Tencent

This checkout belongs only to https://github.com/Prescience-PresbyRobotics/AIRA-App-Tencent. The user confirmed this on 15 October 2026. `aira-mobile-app` is a different project: do not use its repository or cloud resources.

Confirmed cloud targets (15 October 2026): Firebase `aira-app-tencent`, hosted at https://aira-app-tencent.web.app, and Supabase `yzcnccjlwgrkxokgjtkv`. The user requested this separate Firebase project; do not deploy to existing `aira-app-d797a` or `aira-mobile-app-a4150`. The user-confirmed realtime ElevenLabs voice is Jessica (`cgSgspJ2msm6clMCkdW9`); `La9lzDJ3mmfNhhQA06WM` remains the ordinary speech-playback voice. OpenAI `gpt-4.1-mini` writes main text-chat replies through Responses. The user's later 16 October instruction replaces the custom OpenAI live-call bridge: voice/video now use the native ElevenLabs agent with `deepseek-v41-flash`, Scribe Realtime and Jessica/Flash v2. No OpenAI request belongs in the live-call path. Automatic thinking filler is disabled. Keep the provider prompt synchronized with `supabase/functions/_shared/voice_agent.ts`; `aira-voice-setup` is a temporary create/update helper and must be removed from deployment after use.

Read README.md and supabase/README.md for implementation and setup. Stack: Flutter, Supabase Auth/Postgres/Edge Functions, Firebase Hosting, OpenAI Responses API, and ElevenLabs. Repository naming does not require Tencent integrations.

Default display is compact; Larger text retains the original roomy interface. Preserve operating-system text scaling and usable tap targets.

Keep provider and service credentials server-side. Never commit private environment files or print secret values. Public Supabase URL/publishable key are the only client configuration. Preserve owner/role checks, RLS, reviewable feature choices and clearly labelled synthetic preview data. The user's later 16 October decision enables all eleven feature/privacy/care switches by default for new accounts; existing choices remain unchanged. This never grants a staff role, verifies a caregiver, chooses a schedule or bypasses browser permissions. Facial estimates and safety flags are uncertain signals, not clinical findings. The prototype has no external caregiver delivery adapter.

Report verified local checks separately from live cloud/provider verification. Do not represent setup instructions or configured accounts as working integration.

On 16 October 2026 the user required persistent WhatsApp-style conversation history, familiar call screens and richer live mascot actions. Saved signed-in chat/call text stays until deletion or Save conversations is turned off; existing opt-outs remain off. Other prototype data retains its separate expiry. Do not clear chat merely because a call starts/ends. Browser transport tests with generated audio are distinct from physical-microphone/device verification.

Later 16 October requirements: voice/video transcripts belong in Settings → Call history, separate from the main text thread and its model input. Capture device captions with a labelled fallback, verify canonical provider transcripts using the server-issued call binding, and prevent deleted/opted-out archives from being recreated. Calls must not consume text-chat quota or block retry after hangup. Native calls no longer use the text safety-classifier/incident pipeline; do not claim their outputs are pre-screened by it.

Settings → Calls from AIRA supports one owner-selected daily Singapore-time schedule. Keep the app open/visible for Accept/Decline; Aira speaks first on answer. Never claim closed-tab, sleeping-device, push or PSTN ringing. Preserve owner-bound single acceptance, expiry, edit/cancel and no late catch-up calls. New defaults never choose a time automatically.

Caregiver/admin screens are reached from Settings → Care connections or the desktop navigation. Real data still needs verified owner-approved caregiver links or trusted staff assignments. Preview access is not real privilege. Eyebrows are removed from the mascot; retain other animation and reduced-motion behavior.
