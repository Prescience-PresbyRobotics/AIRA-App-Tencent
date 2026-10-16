#!/usr/bin/env python3
"""Opt-in live check of cross-channel context and conversational notes/reminders.

Creates one marked synthetic account without sending email. Runs four screened
OpenAI chat turns, verifies automatic memory/plan/medicine writes, edits a manual
medicine reminder beyond 24 hours, inspects a native-call context token (without
starting audio), and verifies forgotten facts do not return. All text, API keys
and tokens stay in memory. Finally deletes the guarded test account and profile.
Provider requests incur normal usage charges. No real users or devices are used.
Without --run, prints a plan without reading credentials or contacting providers.
"""
import argparse
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import re
import secrets
import signal
import sys
import uuid

from configure_worker import Supabase, SetupError, origin
from smoke_live import LiveSmoke, SmokeError, project_keys, require

ROOT = Path(__file__).resolve().parents[1]
SGT = timezone(timedelta(hours=8))


def check_actions(smoke):
    password = secrets.token_urlsafe(32) + 'Aa9!'
    _, created, _, _ = smoke.admin('POST', '', 'Synthetic account creation', {
        'id': smoke.run_id, 'email': smoke.email, 'password': password,
        'email_confirm': True,
        'app_metadata': {'aira_smoke_test': True, 'aira_smoke_run': smoke.run_id},
        'user_metadata': {'display_name': 'Synthetic shared-context test'},
    }, expected=(200, 201))
    require(created.get('id') == smoke.run_id, 'Synthetic account creation identity mismatch.')
    _, session, _, _ = smoke.call('POST', '/auth/v1/token?grant_type=password', 'Synthetic sign-in',
        {'email': smoke.email, 'password': password}, {'apikey': smoke.public_key})
    smoke.token = session.get('access_token')
    require(isinstance(smoke.token, str) and len(smoke.token) > 40, 'Synthetic sign-in returned no token.')
    _, me, _, _ = smoke.app('GET', '/me', 'Synthetic profile')
    profile = me['profile']
    require(me.get('roles') == [] and profile['id'] == smoke.run_id, 'Synthetic account unexpectedly has staff access.')
    require(all(profile['consents'].get(name) is True for name in ('conversation_storage', 'memory', 'social_reminders', 'medication_reminders')), 'Required test feature defaults are not enabled.')
    version = profile['consent_version']
    _, changed, _, _ = smoke.app('PATCH', '/preferences', 'Harmless preference edit', {
        'display_name': 'Casey', 'text_scale': 1.2, 'reduced_motion': True,
    })
    require(changed['profile']['consent_version'] == version, 'Display/profile edit unexpectedly revoked conversation context.')
    print('PASS: synthetic account defaults and display/name changes preserve context.', flush=True)
    conversation = None

    def message(text, stage):
        nonlocal conversation, version
        _, reply, _, elapsed = smoke.app('POST', '/messages', stage, {
            'clientMessageId': str(uuid.uuid4()), 'mode': 'text', 'text': text,
            'conversationId': conversation, 'contextVersion': version,
        })
        require(reply.get('provider') == 'openai' and reply.get('status') == 'approved', stage + ': provider returned fallback/support instead of approved reply.')
        require(isinstance(reply.get('text'), str) and reply['text'].strip(), stage + ': empty reply.')
        conversation, version = reply['conversationId'], reply['privacyVersion']
        print(f'PASS: {stage} ({elapsed}s; text withheld).', flush=True)
        return reply

    future = (datetime.now(SGT) + timedelta(days=3)).replace(hour=15, minute=0, second=0, microsecond=0)
    event_date = future.date().isoformat()
    reply = message(f'My favourite fruit is dragon fruit. I am visiting the Orchid Garden on {event_date} at 3 pm Singapore time. Please remember this and add the visit to my plans.', 'Automatic fact and plan request')
    kinds = {action.get('kind') for action in reply.get('actions', []) if action.get('status') in ('saved', 'updated', 'already_saved')}
    require({'memory', 'event'} <= kinds, 'Fact/plan request did not produce both confirmed automatic actions.')
    _, notes, _, _ = smoke.app('GET', '/memories', 'Automatic memory readback')
    fruit_notes = [item for item in notes.get('memories', []) if 'dragon' in item.get('text', '').lower()]
    require(fruit_notes, 'Automatic personal fact is missing from memory.')
    _, plans, _, _ = smoke.app('GET', '/events/proposals', 'Automatic plan readback')
    visit = next((item for item in plans.get('schedules', []) if 'orchid' in item.get('label', '').lower()), None)
    require(visit and abs(datetime.fromisoformat(visit['due_at']).timestamp() - future.timestamp()) < 60,
        'Automatic plan is missing or has the wrong explicit Singapore date/time.')
    print('PASS: automatic memory and plan persisted with the requested future date.', flush=True)

    med_start = (datetime.now(SGT) + timedelta(days=4)).replace(hour=9, minute=0, second=0, microsecond=0)
    reply = message(f'I already take Vitamin C as part of my existing routine. Please remind me to take my Vitamin C every day at 9 am Singapore time starting {med_start.date().isoformat()}. No dose instructions are needed.', 'Conversational existing-medicine reminder')
    require(any(action.get('kind') == 'medication' and action.get('status') in ('saved', 'updated', 'already_saved') for action in reply.get('actions', [])), 'Conversational request did not save a medicine reminder.')
    _, meds, _, _ = smoke.app('GET', '/medications', 'Automatic medicine readback')
    automatic = next((item for item in meds.get('schedules', []) if 'vitamin' in item.get('label', '').lower()), None)
    require(automatic and automatic.get('recurrence') == 'daily' and abs(datetime.fromisoformat(automatic['due_at']).timestamp() - med_start.timestamp()) < 60,
        'Conversational medicine does not match the requested daily date/time.')
    require(not automatic.get('instructions'), 'Automatic medicine invented instructions that the user did not supply.')
    print('PASS: conversational medicine reminder is daily and contains no invented dosage.', flush=True)

    manual_due = datetime.now(timezone.utc) + timedelta(days=7)
    _, manual, _, _ = smoke.app('POST', '/medications', 'Manual medicine beyond 24 hours', {
        'label': 'Synthetic medicine fixture', 'instructions': 'My existing packet instructions',
        'dueAt': manual_due.isoformat(), 'confirmed': True, 'recurrence': 'once',
    }, expected=(201,))
    item = manual['schedule']
    _, edited, _, _ = smoke.app('PATCH', '/medications/' + item['id'], 'Manual future medicine edit', {
        'expectedVersion': item['version'], 'label': 'Edited synthetic medicine fixture',
        'instructions': 'Use my own existing written instructions',
        'dueAt': (manual_due + timedelta(days=2)).isoformat(), 'recurrence': 'daily',
    })
    require(edited['schedule']['version'] == item['version'] + 1
        and edited['schedule']['recurrence'] == 'daily'
        and edited['schedule']['label'] == 'Edited synthetic medicine fixture'
        and edited['schedule']['expires_at'] == 'infinity', 'Future medicine edit or durable daily retention failed.')
    print('PASS: manual medicine create/edit accepts future dates and daily recurrence.', flush=True)

    call_id = None
    try:
        _, call, _, _ = smoke.app('POST', '/calls/session', 'Native call context preparation', {'mode': 'voice'}, expected=(201,))
        call_id = call['conversationId']
        variables = call.get('dynamicVariables', {})
        context = json.loads(variables.get('aira_context', '{}'))
        serialized = json.dumps(context).lower()
        require('dragon' in serialized and 'orchid' in serialized and 'vitamin' in serialized,
            'Native call context lacks prior text facts, plans or medicine reminder.')
        require('casey' in variables.get('aira_greeting', '').lower()
            and 'what should' not in variables.get('aira_greeting', '').lower(),
            'Returning caller greeting does not use the known name.')
        require('customLlmExtraBody' not in call, 'Native call unexpectedly uses a custom LLM bridge.')
        print('PASS: native ElevenLabs session receives prior text context and known-name greeting; no audio started.', flush=True)
    finally:
        if call_id:
            smoke.app('POST', '/calls/' + call_id + '/end', 'Unused call token cleanup', {})

    recall = message('What is my favourite fruit, and which garden am I going to visit?', 'Saved-context recall')
    require('dragon' in recall['text'].lower() and 'orchid' in recall['text'].lower(), 'Text recall did not use the persisted personal fact and plan.')
    _, notes, _, _ = smoke.app('GET', '/memories', 'Personal fact deletion lookup')
    fruit_notes = [item for item in notes.get('memories', []) if 'dragon' in item.get('text', '').lower()]
    require(fruit_notes, 'Personal fact disappeared before explicit deletion.')
    for memory in fruit_notes:
        _, deletion, _, _ = smoke.app('DELETE', '/memories/' + memory['id'], 'Explicit personal fact deletion')
        version = deletion['privacyVersion']
    forgotten = message('What is my favourite fruit?', 'Forgotten fact exclusion')
    require('dragon' not in forgotten['text'].lower(), 'Forgotten fact was resurrected from old transcript context.')
    _, notes, _, _ = smoke.app('GET', '/memories', 'Forgotten fact remains absent')
    require(not any('dragon' in item.get('text', '').lower() for item in notes.get('memories', [])), 'Forgotten fact was automatically re-saved from the archive.')
    print('PASS: explicit memory deletion excludes old text/call context and does not recreate the fact.', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project-ref', required=True)
    parser.add_argument('--supabase', default='supabase')
    parser.add_argument('--origin', type=origin, default='http://localhost:8080')
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--cleanup-run', type=uuid.UUID)
    args = parser.parse_args()
    require(bool(re.fullmatch(r'[a-z0-9]{20}', args.project_ref)), 'Invalid Supabase project reference.')
    linked = ROOT / 'supabase/.temp/project-ref'
    require(linked.exists() and linked.read_text().strip() == args.project_ref, 'Linked checkout does not match --project-ref.')
    if not args.run and not args.cleanup_run:
        print('Plan only: no credentials, network, accounts or providers accessed.')
        print('With --run: create one marked account, run four screened text turns, verify')
        print('automatic notes/plans/medicine, future medicine editing, native call context,')
        print('forgetting and cleanup. Provider usage charges apply. No audio or emails sent.')
        return
    public_key, server_key = project_keys(Supabase(args.supabase, args.project_ref))
    run_id = str(args.cleanup_run or uuid.uuid4())
    smoke = LiveSmoke(args.project_ref, public_key, server_key, args.origin, run_id)
    journal = ROOT / 'supabase/.temp' / f'live-smoke-{run_id}.json'
    if args.cleanup_run:
        smoke.cleanup()
        journal.unlink(missing_ok=True)
        print('Cleanup verified: marked synthetic account and profile are absent.')
        return
    with open(journal, 'w') as handle:
        os.chmod(journal, 0o600)
        json.dump({'project_ref': args.project_ref, 'run_id': run_id, 'kind': 'shared-actions-smoke',
            'created_at': datetime.now(timezone.utc).isoformat()}, handle)
    print('Synthetic run ID: ' + run_id, flush=True)
    try:
        check_actions(smoke)
    finally:
        try:
            smoke.cleanup()
            journal.unlink(missing_ok=True)
            print('PASS: marked synthetic account and profile removed; cleanup verified.', flush=True)
        except (SmokeError, SetupError):
            print(f'Cleanup requires retry: --project-ref {args.project_ref} --cleanup-run {run_id}', file=sys.stderr)
            raise SmokeError('Could not verify cleanup; non-secret recovery journal preserved.') from None


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, lambda *_args: sys.exit(143))
    try:
        main()
    except (SmokeError, SetupError) as error:
        print('FAILED: ' + str(error), file=sys.stderr)
        sys.exit(1)
