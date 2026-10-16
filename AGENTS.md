# AIRA-App-Tencent

This checkout belongs only to https://github.com/Prescience-PresbyRobotics/AIRA-App-Tencent. The user confirmed this on 15 October 2026. `aira-mobile-app` is a different project: do not use its repository or cloud resources.

Confirmed cloud targets (15 October 2026): Firebase `aira-app-tencent`, hosted at https://aira-app-tencent.web.app, and Supabase `yzcnccjlwgrkxokgjtkv`. The user requested this separate Firebase project; do not deploy to existing `aira-app-d797a` or `aira-mobile-app-a4150`. The user-confirmed realtime ElevenLabs voice is Jessica (`cgSgspJ2msm6clMCkdW9`); `La9lzDJ3mmfNhhQA06WM` remains the ordinary speech-playback voice. OpenAI `gpt-4.1-mini` writes replies through Responses; ElevenLabs Scribe Realtime handles live transcription and Flash v2 handles live speech. This is not an OpenAI Realtime/audio-model integration.

Read README.md and supabase/README.md for implementation and setup. Stack: Flutter, Supabase Auth/Postgres/Edge Functions, Firebase Hosting, OpenAI Responses API, and ElevenLabs. Repository naming does not require Tencent integrations.

Default display is compact; Larger text retains the original roomy interface. Preserve operating-system text scaling and usable tap targets.

Keep provider and service credentials server-side. Never commit private environment files or print secret values. Public Supabase URL/publishable key are the only client configuration. Preserve explicit consent, owner/role checks, RLS and clearly labelled synthetic preview data. Facial estimates and safety flags are uncertain signals, not clinical findings. The prototype has no external caregiver delivery adapter.

Report verified local checks separately from live cloud/provider verification. Do not represent setup instructions or configured accounts as working integration.

On 16 October 2026 the user required persistent WhatsApp-style conversation history, familiar call screens and richer live mascot actions. Saved signed-in chat/call text stays until deletion or Save conversations is turned off; existing opt-outs remain off. Other prototype data retains its separate expiry. Do not clear chat merely because a call starts/ends. Browser transport tests with generated audio are distinct from physical-microphone/device verification.
