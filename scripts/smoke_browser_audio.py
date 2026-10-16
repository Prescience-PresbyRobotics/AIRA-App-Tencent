#!/usr/bin/env python3
"""Opt-in real ElevenLabs WebRTC test with generated speech, never a physical microphone.

Serves a localhost-only test page using the app's unchanged SDK and audio adapter.
Creates a marked synthetic account and a real call, then removes both in finally.
Requires an existing mono 16 kHz, 16-bit PCM WAV and expected transcript words.
Without --run, prints a plan without reading credentials or contacting providers.
"""
import argparse
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import math
import os
from pathlib import Path
import re
import secrets
import signal
import sys
import time
import uuid
import wave

from configure_worker import Supabase, SetupError, origin
from smoke_live import LiveSmoke, SmokeError, project_keys, require

ROOT = Path(__file__).resolve().parents[1]
REASONS = {'audio_recognized_and_answered', 'stopped', 'timeout', 'disconnected',
           'startup_failed', 'rtc_configuration_unsupported', 'audio_failed', 'poll_failed'}


def audio_file(path):
    require(path.is_file() and path.stat().st_size <= 2_000_000,
            'Supply a generated speech WAV smaller than 2 MB.')
    try:
        with wave.open(str(path), 'rb') as audio:
            require((audio.getnchannels(), audio.getsampwidth(), audio.getframerate(), audio.getcomptype())
                    == (1, 2, 16000, 'NONE'), 'WAV must be mono, 16-bit PCM, 16 kHz.')
            require(1 <= audio.getnframes() / 16000 <= 30, 'Use 1–30 seconds of generated speech.')
        return path.read_bytes()
    except (wave.Error, EOFError):
        raise SmokeError('Could not read the synthetic PCM WAV.') from None


def validated_result(data):
    require(isinstance(data, dict) and data.get('reason') in REASONS, 'Invalid browser test result.')
    result = {key: data.get(key) is True for key in ('success', 'recognized', 'reply')}
    for key in ('seconds', 'microphoneStreams', 'inputPeak', 'replyOutputPeak', 'audibleReplyPeak'):
        value = data.get(key)
        require(isinstance(value, (int, float)) and not isinstance(value, bool)
                and math.isfinite(value) and 0 <= value <= 1000, 'Invalid browser test measurement.')
        result[key] = value
    result['reason'] = data['reason']
    result['success'] = (result['success'] and result['recognized'] and result['reply']
                         and result['microphoneStreams'] >= 2 and result['inputPeak'] > .01
                         and result['replyOutputPeak'] > .01 and result['audibleReplyPeak'] > .01
                         and result['reason'] == 'audio_recognized_and_answered')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-ref', required=True)
    parser.add_argument('--supabase', default='supabase')
    parser.add_argument('--origin', type=origin, default='http://localhost:8080',
                        help='Already allowed app origin used by server-side test API calls')
    parser.add_argument('--port', type=int, default=8766)
    parser.add_argument('--timeout', type=int, default=240, help='Per-call browser wait, 90–600 seconds')
    parser.add_argument('--calls', type=int, choices=(1, 2), default=2,
                        help='Two same-page calls verify hangup/restart audio (default: 2)')
    parser.add_argument('--audio-file', type=Path)
    parser.add_argument('--expect', nargs='+', help='Words or short phrases that must ALL be recognized')
    parser.add_argument('--shared-context', action='store_true', help='Verify text-to-call context plus native automatic memory and plan tools using the documented fixture.')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--cleanup-run', type=uuid.UUID)
    args = parser.parse_args()
    require(bool(re.fullmatch(r'[a-z0-9]{20}', args.project_ref)), 'Invalid Supabase project reference.')
    require(1024 <= args.port <= 65535 and 90 <= args.timeout <= 600, 'Invalid local port or timeout.')
    linked = ROOT / 'supabase/.temp/project-ref'
    require(linked.exists() and linked.read_text().strip() == args.project_ref,
            'Linked checkout does not match --project-ref.')
    if not args.run and not args.cleanup_run:
        print('Plan only; no credentials, network, accounts or providers accessed.')
        print('With --run: create one marked account and up to two calls on the same browser page,')
        print('stream generated WAV speech through the actual ElevenLabs WebRTC SDK, verify')
        print('expected transcription plus a new non-filler spoken reply, and remove the account.')
        print('Requires --audio-file (mono 16 kHz PCM WAV) and --expect word [word ...].')
        print('Normal ElevenLabs usage plus one OpenAI text-reply verification charges apply. Physical microphone/camera never opens.')
        return
    audio = None
    if not args.cleanup_run:
        require(args.audio_file is not None and bool(args.expect), '--run needs --audio-file and --expect.')
        require(len(args.expect) <= 8 and all(re.fullmatch(r'[A-Za-z0-9 ]{1,60}', word)
                and word.strip() for word in args.expect), 'Use 1–8 short English transcript expectations.')
        audio = audio_file(args.audio_file)
    public_key, server_key = project_keys(Supabase(args.supabase, args.project_ref))
    run_id = str(args.cleanup_run or uuid.uuid4())
    smoke = LiveSmoke(args.project_ref, public_key, server_key, args.origin, run_id)
    journal = ROOT / 'supabase/.temp' / f'live-smoke-{run_id}.json'
    if args.cleanup_run:
        smoke.cleanup()
        journal.unlink(missing_ok=True)
        print('Cleanup verified: marked synthetic account and profile are absent.')
        return
    nonce = secrets.token_urlsafe(32)
    host = f'127.0.0.1:{args.port}'
    local_origin = f'http://{host}'
    call, server, outcome, archive = None, None, None, None
    page = (ROOT / 'scripts/smoke_browser_audio.html').read_text().replace(
        '__AIRA_TEST_CONFIG__', json.dumps({'nonce': nonce, 'expected': args.expect, 'calls': args.calls, 'sharedContext': args.shared_context}))
    assets = {
        '/': (page.encode(), 'text/html; charset=utf-8'),
        '/speech.wav': (audio, 'audio/wav'),
        '/media/realtime_client.js': ((ROOT / 'app/web/media/realtime_client.js').read_bytes(), 'application/javascript'),
        '/media/vendor/elevenlabs-client-1.28.0.js': ((ROOT / 'app/web/media/vendor/elevenlabs-client-1.28.0.js').read_bytes(), 'application/javascript'),
    }

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass  # Never log credentials, headers or browser request paths.

        def setup(self):
            super().setup()
            self.connection.settimeout(3)

        def allowed(self, private=False):
            if (self.headers.get('Host') != host
                    or self.headers.get('Origin', local_origin) != local_origin
                    or self.headers.get('Sec-Fetch-Site', 'same-origin') not in ('same-origin', 'none')):
                self.send_error(403)
                return False
            if private and not secrets.compare_digest(self.headers.get('X-Aira-Smoke', ''), nonce):
                self.send_error(403)
                return False
            return True

        def send(self, status, body=b'', content_type='application/json'):
            self.send_response(status)
            self.send_header('Content-Type', content_type)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'no-store')
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('Permissions-Policy', 'microphone=(), camera=()')
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if not self.allowed(private=self.path == '/config'):
                return
            if self.path == '/config' and call is not None:
                self.send(200, json.dumps(call).encode())
            elif self.path in assets:
                body, kind = assets[self.path]
                self.send(200, body, kind)
            else:
                self.send_error(404)

        def do_POST(self):
            nonlocal outcome, archive
            if self.path not in ('/result', '/checkpoint'):
                self.send_error(404)
                return
            if not self.allowed(private=True):
                return
            try:
                size = int(self.headers.get('Content-Length', 0))
                require(0 < size <= 262144, 'Result body too large.')
                body = json.loads(self.rfile.read(size))
                if self.path == '/checkpoint':
                    smoke.app('POST', '/calls/' + call['conversationId'] + '/transcript', 'Live caption checkpoint', body)
                    self.send(204)
                    return
                outcome = validated_result(body)
                archive = body.get('archive')
            except (ValueError, SmokeError, OSError):
                self.send_error(400)
                return
            self.send(204)
            print(json.dumps(outcome), flush=True)

    # Non-secret recovery journal; no API key, token, transcript or audio is saved.
    with os.fdopen(os.open(journal, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600), 'w') as stream:
        json.dump({'project_ref': args.project_ref, 'run_id': run_id,
                   'started_at': datetime.now(timezone.utc).isoformat()}, stream)
    print(f'Synthetic test run: {run_id}', flush=True)
    try:
        server = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
        server.timeout = 1
        password = secrets.token_urlsafe(32) + 'Aa9!'
        _, created, _, _ = smoke.admin('POST', '', 'Synthetic account creation', {
            'id': run_id, 'email': smoke.email, 'password': password, 'email_confirm': True,
            'app_metadata': {'aira_smoke_test': True, 'aira_smoke_run': run_id},
        }, expected=(200, 201))
        require(created.get('id') == run_id, 'Unexpected synthetic identity.')
        _, login, _, _ = smoke.call('POST', '/auth/v1/token?grant_type=password', 'Synthetic sign-in',
            {'email': smoke.email, 'password': password}, {'apikey': public_key})
        smoke.token = login.get('access_token')
        require(isinstance(smoke.token, str) and len(smoke.token) > 40, 'No synthetic access token.')
        _, me, _, _ = smoke.app('GET', '/me', 'Initialize synthetic profile')
        choices = {key: key == 'conversation_storage' or (args.shared_context and key in ('memory', 'social_reminders', 'medication_reminders')) for key in me['profile']['consents']}
        smoke.app('PATCH', '/preferences', 'Keep only synthetic transcript storage', {'consents': choices})
        if args.shared_context:
            _, me, _, _ = smoke.app('GET', '/me', 'Current privacy version')
            _, reply, _, _ = smoke.app('POST', '/messages', 'Seed text memory', {
                'clientMessageId': str(uuid.uuid4()), 'mode': 'text',
                'contextVersion': me['profile']['consent_version'],
                'text': 'My favorite fruit is mango. Please remember that.',
            })
            require(reply.get('status') == 'approved', 'Text memory seed failed.')
        for call_number in range(1, args.calls + 1):
            outcome, archive = None, None
            _, call, _, _ = smoke.app('POST', '/calls/session', 'WebRTC token mint', {'mode': 'voice'}, expected=(201,))
            if args.shared_context:
                require('mango' in str(call.get('dynamicVariables', {}).get('aira_context', '')).lower(), 'Text context missing from native call.')
            print(f'READY call {call_number}/{args.calls}: open {local_origin}/ and click the Run button. Keep this same page for the next call.', flush=True)
            print('No physical microphone or camera is accessed. Keep this test page visible.', flush=True)
            deadline = time.monotonic() + args.timeout
            while outcome is None and time.monotonic() < deadline:
                server.handle_request()
            require(outcome is not None, 'Browser test deadline expired.')
            require(outcome['success'], 'Browser WebRTC audio test did not pass; see safe measurements above.')
            require(isinstance(archive, dict) and isinstance(archive.get('entries'), list), 'No browser transcript to archive.')
            smoke.app('POST', '/calls/' + call['conversationId'] + '/transcript', 'Archive browser captions', archive)
            smoke.app('POST', '/calls/' + call['conversationId'] + '/end', 'End native call', {})
            _, history, _, _ = smoke.app('GET', '/history', 'Text isolation')
            require(all(item.get('mode') == 'text' for item in history.get('messages', [])), 'Call transcript leaked into main text history.')
            _, detail, _, _ = smoke.app('GET', '/calls/' + call['conversationId'] + '/transcript', 'Read call transcript')
            require(len(detail.get('messages', [])) >= 2, 'Call captions were not saved separately.')
            provider_verified = detail.get('call', {}).get('source') == 'elevenlabs'
            for _ in range(2):
                if provider_verified:
                    break
                time.sleep(11)
                _, detail, _, _ = smoke.app('GET', '/calls/' + call['conversationId'] + '/transcript', 'Canonical transcript recovery')
                provider_verified = detail.get('call', {}).get('source') == 'elevenlabs'
            require(provider_verified, 'Provider transcript ownership/recovery was not verified.')
        if args.shared_context:
            _, notes, _, _ = smoke.app('GET', '/memories', 'Verify native memories')
            print('Native save check: ' + json.dumps({'memory_count': len(notes.get('memories', [])), 'providerConversationId': archive.get('providerConversationId')}), flush=True)
            require('tomato' in json.dumps(notes).lower(), 'Native tool did not save the spoken user fact.')
            _, plans, _, _ = smoke.app('GET', '/events/proposals', 'Verify native plans')
            require('botanical' in json.dumps(plans).lower(), 'Native tool did not save the spoken upcoming plan.')
            require('mango' in ' '.join(item.get('text', '') for item in detail.get('messages', []) if item.get('role') == 'assistant').lower(), 'Native reply did not recall text-chat fruit context.')
            print('PASS: native call recalled text context and saved spoken memory/plan through ElevenLabs tools.', flush=True)
        _, me, _, _ = smoke.app('GET', '/me', 'Current privacy version')
        _, reply, _, _ = smoke.app('POST', '/messages', 'Text immediately after native call', {
            'clientMessageId': str(uuid.uuid4()), 'mode': 'text',
            'contextVersion': me['profile']['consent_version'],
            'text': 'Where am I going tomorrow?' if args.shared_context else 'That was a nice chat about my garden. The tomatoes are growing well.',
        })
        require(reply.get('status') == 'approved' and bool(reply.get('text')), 'Text after call did not return a reply.')
        if args.shared_context:
            require('botanical' in reply.get('text', '').lower(), 'Text chat did not recall native call plan.')
        _, history, _, _ = smoke.app('GET', '/history', 'Read separate text history')
        require(len(history.get('messages', [])) == (4 if args.shared_context else 2) and all(item.get('mode') == 'text' for item in history['messages']), 'Text and call histories are not isolated.')
        print('PASS: separately saved canonical ElevenLabs transcript, verified ownership, isolated main chat and text reply after call.', flush=True)
    finally:
        if server:
            server.server_close()
        if call:
            try:
                smoke.app('POST', '/calls/' + call['conversationId'] + '/end', 'Call cleanup', {})
            except (SmokeError, KeyError):
                pass  # Account deletion also cascades the synthetic call/session.
        try:
            smoke.cleanup()
            journal.unlink(missing_ok=True)
            print('PASS: synthetic account and profile removed.', flush=True)
        except (SmokeError, OSError):
            print(f'Cleanup requires retry: --project-ref {args.project_ref} --cleanup-run {run_id}', file=sys.stderr)
            raise SmokeError('Could not verify cleanup; non-secret recovery journal preserved.') from None
    print(f'PASS: {args.calls} same-page browser WebRTC calls with recognized input and unmuted output playback. Physical devices remain separate.')


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_args: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        main()
    except (SmokeError, SetupError) as error:
        print(f'Browser audio test stopped: {error}', file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print('Browser audio test interrupted.', file=sys.stderr)
        sys.exit(130)
    except Exception:
        print('Browser audio test stopped: unexpected local error; details suppressed.', file=sys.stderr)
        sys.exit(1)
