-- Direct owner product decision, 16 October 2026: new accounts start with all
-- app feature toggles enabled. This default does not rewrite an existing user's
-- choices, grant staff roles, verify a caregiver, or schedule a call/medication.
-- Browser microphone/camera permissions still require the browser's permission.
alter table public.profiles alter column consents set default
 '{"conversation_storage":true,"memory":true,"social_reminders":true,"medication_reminders":true,"monitoring":true,"impact":true,"mood_history":true,"face_cues":true,"urgent_sharing":true,"reviewed_sharing":true,"admin_insights":true}'::jsonb;
