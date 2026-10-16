#!/usr/bin/env python3
"""Opt-in live test of AIRA Auth, screened OpenAI text, ElevenLabs TTS and STT.

Without --run this only validates local configuration and prints the plan. A live
run creates a synthetic, preconfirmed Auth account without sending email,
verifies new-account feature defaults then turns optional consents off before
provider testing, and deletes that account in finally. Provider keys
are never read. Supabase keys, tokens, audio and text stay in process memory.
The ordinary run makes one app message (normally three OpenAI requests), one TTS
request and one STT request, which incur the providers' normal usage charges.
This does not test confirmation emails, Google OAuth, browser audio or accuracy.
"""

import argparse
import base64
import binascii
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import secrets
import signal
import ssl
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import build_opener, HTTPRedirectHandler, HTTPSHandler, Request
import uuid

from configure_worker import Supabase, SetupError, origin


ROOT = Path(__file__).resolve().parents[1]
API_PATH = "/functions/v1/aira-api/v1"


class SmokeError(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        # Never forward credentials to a redirect target.
        return None


def require(condition, message):
    if not condition:
        raise SmokeError(message)


def project_keys(cli):
    try:
        rows = json.loads(cli.run(["projects", "api-keys", "--reveal"], "Project key access"))
        require(isinstance(rows, list), "Unexpected project-key response; values suppressed.")
        selected = []
        for prefix, legacy_name in (("sb_publishable_", "anon"), ("sb_secret_", "service_role")):
            modern = [r for r in rows if isinstance(r, dict)
                      and isinstance(r.get("api_key"), str)
                      and re.fullmatch(re.escape(prefix) + r"[A-Za-z0-9_-]+", r["api_key"])]
            defaults = [r for r in modern if r.get("name") == "default"]
            choices = defaults or modern
            if not choices:
                choices = [r for r in rows if isinstance(r, dict)
                           and r.get("name") == legacy_name
                           and re.fullmatch(r"[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+",
                                            str(r.get("api_key", "")))]
            require(len(choices) == 1, "Cannot select an unambiguous project API key; values suppressed.")
            selected.append(choices[0]["api_key"])
        return selected
    except (ValueError, TypeError, KeyError):
        raise SmokeError("Cannot parse project API keys; values suppressed.") from None


class LiveSmoke:
    def __init__(self, project_ref, public_key, server_key, app_origin, run_id):
        self.base = f"https://{project_ref}.supabase.co"
        self.public_key, self.server_key = public_key, server_key
        self.origin = app_origin
        self.run_id = str(uuid.UUID(run_id))
        self.email = f"aira-smoke-{uuid.UUID(run_id).hex}@example.invalid"
        self.token = None
        self.opener = build_opener(NoRedirect(), HTTPSHandler(context=ssl.create_default_context()))

    def call(self, method, path, stage, body=None, headers=None, expected=(200,), timeout=90):
        require(path.startswith("/") and not path.startswith("//"), "Invalid test path.")
        request = Request(self.base + path, method=method,
                          data=None if body is None else json.dumps(body).encode(),
                          headers={"Content-Type": "application/json", **(headers or {})})
        started = time.monotonic()
        try:
            try:
                response = self.opener.open(request, timeout=timeout)
            except HTTPError as error:
                response = error
            with response:
                status, response_headers = response.status, response.headers
                raw = response.read(10_000_001)
            require(len(raw) <= 10_000_000, f"{stage}: response exceeds the test limit.")
            try:
                data = json.loads(raw) if raw else {}
            except (ValueError, UnicodeDecodeError):
                data = {}
            if status not in expected:
                # Only machine error codes are retained, never provider bodies or text.
                code = data.get("code", data.get("error_code", "")) if isinstance(data, dict) else ""
                safe_code = code if isinstance(code, str) and re.fullmatch(r"[a-z_]{1,60}", code) else "unknown"
                raise SmokeError(f"{stage}: HTTP {status}, code={safe_code}; response body suppressed.")
            return status, data, response_headers, round(time.monotonic() - started, 2)
        except (URLError, TimeoutError, OSError):
            raise SmokeError(f"{stage}: network/connection failure; request details suppressed.") from None

    def admin(self, method, suffix, stage, body=None, expected=(200,)):
        headers = {"apikey": self.server_key}
        if not self.server_key.startswith("sb_secret_"):
            headers["Authorization"] = "Bearer " + self.server_key
        return self.call(method, "/auth/v1/admin/users" + suffix, stage,
                         body, headers, expected, timeout=30)

    def app(self, method, path, stage, body=None, expected=(200,), authenticated=True):
        headers = {"apikey": self.public_key, "Origin": self.origin}
        if authenticated and self.token:
            headers["Authorization"] = "Bearer " + self.token
        return self.call(method, API_PATH + path, stage, body, headers, expected)

    def preflight(self):
        _, _, headers, _ = self.call("OPTIONS", API_PATH + "/me", "CORS preflight", headers={
            "Origin": self.origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization, apikey, content-type",
        }, expected=(204,))
        require(headers.get("Access-Control-Allow-Origin") == self.origin,
                "CORS did not allow the selected app origin.")
        self.app("GET", "/me", "Anonymous access denial", expected=(401,), authenticated=False)
        print("PASS: CORS and anonymous request denial.", flush=True)

    def create_and_test(self):
        password = secrets.token_urlsafe(32) + "Aa9!"
        _, created, _, _ = self.admin("POST", "", "Synthetic account creation", {
            "id": self.run_id, "email": self.email, "password": password,
            "email_confirm": True,
            "app_metadata": {"aira_smoke_test": True, "aira_smoke_run": self.run_id},
            "user_metadata": {"display_name": "Synthetic AIRA smoke test"},
        }, expected=(200, 201))
        require(created.get("id") == self.run_id, "Created test identity does not match its cleanup ID.")
        _, session, _, _ = self.call("POST", "/auth/v1/token?grant_type=password", "Password sign-in",
                                    {"email": self.email, "password": password},
                                    {"apikey": self.public_key})
        self.token = session.get("access_token")
        require(isinstance(self.token, str) and len(self.token) > 40, "Sign-in returned no usable access token.")
        _, me, _, _ = self.app("GET", "/me", "Authenticated profile")
        profile = me.get("profile", {})
        require(profile.get("id") == self.run_id, "Profile does not belong to the synthetic account.")
        consent_names = {
            "conversation_storage", "memory", "social_reminders", "medication_reminders",
            "monitoring", "impact", "mood_history", "face_cues", "urgent_sharing",
            "reviewed_sharing", "admin_insights",
        }
        require(isinstance(profile.get("consents"), dict)
                and set(profile["consents"]) == consent_names
                and all(value is True for value in profile["consents"].values()),
                "Synthetic account does not have the configured new-account defaults.")
        require(me.get("roles") == [], "Synthetic account has unexpected staff assignments.")
        self.app("GET", "/admin/overview", "Staff access denial", expected=(403,))
        print("PASS: password sign-in, account profile, consent defaults and staff access denial.", flush=True)
        _, updated, _, _ = self.app("PATCH", "/preferences", "Disable synthetic account optional features", {
            "consents": {name: False for name in sorted(consent_names)},
        })
        profile = updated.get("profile", {})
        require(profile.get("id") == self.run_id
                and isinstance(profile.get("consents"), dict)
                and set(profile["consents"]) == consent_names
                and all(value is False for value in profile["consents"].values()),
                "Synthetic optional features were not disabled before provider testing.")
        print("PASS: synthetic optional features disabled before provider testing.", flush=True)
        capabilities = me.get("capabilities", {})
        require(capabilities.get("text") is True,
                "Text is not configured: check OPENAI_API_KEY and OPENAI_MODEL in Edge secrets.")
        require(capabilities.get("voice") is True,
                "Voice is not configured: check ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID and signing secret.")
        _, reply, _, elapsed = self.app("POST", "/messages", "Screened OpenAI reply", {
            "clientMessageId": str(uuid.uuid4()), "mode": "text",
            "contextVersion": profile.get("consent_version"),
            "text": "Hello AIRA. I enjoyed a peaceful walk in the garden today. Please give me a brief friendly greeting.",
        })
        require(reply.get("provider") == "openai" and reply.get("status") == "approved"
                and isinstance(reply.get("text"), str) and bool(reply["text"].strip()),
                "OpenAI did not return a screened approved reply; the app returned a fallback or support response.")
        require(isinstance(reply.get("speechToken"), str), "Approved reply has no speech token.")
        print(f"PASS: screened OpenAI reply ({elapsed}s; text withheld).", flush=True)
        _, speech, _, elapsed = self.app("POST", "/speech", "ElevenLabs speech synthesis",
                                       {"speechToken": reply["speechToken"]})
        try:
            audio = base64.b64decode(speech.get("audioBase64", ""), validate=True)
        except (binascii.Error, ValueError, TypeError):
            raise SmokeError("Speech synthesis returned malformed audio.") from None
        require(speech.get("provider") == "elevenlabs" and speech.get("mimeType") == "audio/mpeg"
                and 256 < len(audio) <= 5_000_000,
                "Speech synthesis returned no bounded MP3 audio.")
        require(audio.startswith(b"ID3") or (audio[0] == 0xFF and audio[1] & 0xE0 == 0xE0),
                "Speech synthesis response lacks an MP3 header.")
        print(f"PASS: ElevenLabs speech synthesis ({elapsed}s; {len(audio)} bytes, held in memory).", flush=True)
        _, transcript, _, elapsed = self.app("POST", "/audio/transcriptions", "ElevenLabs transcription", {
            "audioBase64": speech["audioBase64"], "mimeType": "audio/mpeg", "locale": "en",
        })
        require(transcript.get("provider") == "elevenlabs" and transcript.get("editable") is True
                and isinstance(transcript.get("text"), str) and bool(transcript["text"].strip()),
                "Speech transcription returned no editable text.")
        print(f"PASS: ElevenLabs transcription of synthetic speech ({elapsed}s; text withheld).", flush=True)

    def cleanup(self):
        status, user, _, _ = self.admin("GET", "/" + self.run_id, "Cleanup identity check", expected=(200, 404))
        if status == 404:
            return
        metadata = user.get("app_metadata", {})
        require(user.get("id") == self.run_id and user.get("email") == self.email
                and metadata.get("aira_smoke_test") is True
                and metadata.get("aira_smoke_run") == self.run_id,
                "Cleanup identity guard failed; no account was deleted.")
        self.admin("DELETE", "/" + self.run_id, "Synthetic account removal",
                   {"should_soft_delete": False}, expected=(200, 204))
        self.admin("GET", "/" + self.run_id, "Account deletion verification", expected=(404,))
        headers = {"apikey": self.server_key}
        if not self.server_key.startswith("sb_secret_"):
            headers["Authorization"] = "Bearer " + self.server_key
        _, profiles, _, _ = self.call("GET", f"/rest/v1/profiles?id=eq.{self.run_id}&select=id",
                                      "Profile deletion verification", headers=headers, timeout=30)
        require(profiles == [], "Synthetic profile remains after account deletion.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--supabase", default="supabase")
    parser.add_argument("--origin", type=origin, default="http://localhost:8080")
    parser.add_argument("--run", action="store_true", help="Create a temporary test account and use live providers")
    parser.add_argument("--cleanup-run", type=uuid.UUID, help="Remove only the marked account from this earlier run")
    args = parser.parse_args()
    require(bool(re.fullmatch(r"[a-z0-9]{20}", args.project_ref)), "Invalid Supabase project reference.")
    linked = ROOT / "supabase/.temp/project-ref"
    require(linked.exists() and linked.read_text().strip() == args.project_ref,
            "Linked checkout does not match --project-ref.")
    if not args.run and not args.cleanup_run:
        print("Plan only; no network, credentials, accounts or providers accessed.")
        print("Use --run to test CORS, password sign-in, screened text, synthesized speech and transcription.")
        print("One synthetic account is removed in finally; no email, caregiver contact or real-person data is used.")
        return
    cli = Supabase(args.supabase, args.project_ref)
    public_key, server_key = project_keys(cli)
    run_id = str(args.cleanup_run or uuid.uuid4())
    smoke = LiveSmoke(args.project_ref, public_key, server_key, args.origin, run_id)
    journal = ROOT / "supabase/.temp" / f"live-smoke-{run_id}.json"
    if args.cleanup_run:
        smoke.cleanup()
        journal.unlink(missing_ok=True)
        print("Cleanup verified: marked synthetic account and app profile are absent.")
        return
    smoke.preflight()
    # Non-secret journal makes cleanup possible after a machine/process crash.
    with os.fdopen(os.open(journal, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), "w") as stream:
        json.dump({"project_ref": args.project_ref, "run_id": run_id,
                   "started_at": datetime.now(timezone.utc).isoformat()}, stream)
    print(f"Synthetic test run: {run_id}", flush=True)
    failure = None
    try:
        smoke.create_and_test()
    except (SmokeError, KeyboardInterrupt) as error:
        failure = error
    finally:
        try:
            smoke.cleanup()
            journal.unlink(missing_ok=True)
            print("PASS: synthetic Auth account and app profile removed.", flush=True)
        except (SmokeError, OSError):
            print(f"Cleanup requires retry: --project-ref {args.project_ref} --cleanup-run {run_id}", file=sys.stderr)
            raise SmokeError("Could not verify synthetic account cleanup; the non-secret journal was preserved.") from None
    if failure:
        raise failure
    print("Live provider smoke test passed. Browser/device and OAuth/email delivery checks remain separate.")


if __name__ == "__main__":
    # SIGTERM follows the same finally cleanup path as Ctrl-C. SIGKILL/power loss
    # cannot execute Python cleanup; use the printed run ID or ignored journal.
    signal.signal(signal.SIGTERM, lambda _signum, _frame: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        main()
    except (SmokeError, SetupError) as error:
        print(f"Smoke test stopped: {error}", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Smoke test interrupted.", file=sys.stderr)
        sys.exit(130)
    except Exception:
        print("Smoke test stopped: unexpected local error; diagnostic contents suppressed.", file=sys.stderr)
        sys.exit(1)
