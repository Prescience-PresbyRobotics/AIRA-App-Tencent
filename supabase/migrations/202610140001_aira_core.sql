-- AIRA controlled prototype. Apply with `supabase db reset` locally first.
-- Application content expires after 24 hours. No external notification provider exists.
create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '' check (length(display_name) <= 80),
  locale text not null default 'en' check (locale = 'en'),
  timezone text not null default 'Asia/Singapore',
  text_scale numeric not null default 1 check (text_scale between 1 and 2),
  character_id text not null default 'aira',
  reduced_motion boolean not null default false,
  enabled boolean not null default true,
  onboarded boolean not null default false,
  consent_version integer not null default 1,
  consents jsonb not null default '{"conversation_storage":false,"memory":false,"social_reminders":false,"medication_reminders":false,"monitoring":false,"impact":false,"mood_history":false,"face_cues":false,"urgent_sharing":false,"reviewed_sharing":false,"admin_insights":false}',
  social_paused_until timestamptz,
  created_at timestamptz not null default now()
);
create table public.role_assignments (
  user_id uuid references auth.users(id) on delete cascade,
  role text not null check (role in ('operator','reviewer','insights')),
  subject_id uuid references public.profiles(id) on delete cascade,
  enabled boolean not null default true,
  unique nulls not distinct (user_id, role, subject_id)
);
create table public.caregiver_links (
  id uuid primary key default gen_random_uuid(),
  senior_id uuid not null references public.profiles(id) on delete cascade,
  caregiver_id uuid not null references auth.users(id) on delete cascade,
  verified boolean not null default false,
  test_recipient boolean not null default true check (test_recipient),
  scopes text[] not null default '{}',
  revoked_at timestamptz,
  unique (senior_id, caregiver_id)
);
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null default 'text' check (mode in ('text','voice','video')),
  initiator text not null default 'senior' check (initiator in ('senior','aira')),
  completed boolean not null default false,
  accepted_at timestamptz not null default now(),
  ended_at timestamptz,
  expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.message_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  client_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  status text not null default 'processing' check (status in ('processing','completed','failed')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  unique (user_id, client_id)
);
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid not null references public.message_requests(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  role text not null check (role in ('user','assistant')),
  text text not null check (length(text) between 1 and 4000),
  approved boolean not null default false,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  unique(request_id,role)
);
create table public.memories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  text text not null check (length(text) between 1 and 500),
  category text not null default 'preference' check (category in ('preference','relationship','plan','other')),
  confirmed boolean not null default true check (confirmed),
  version integer not null default 1,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('medication','event')),
  label text not null check (length(label) between 1 and 300),
  instructions text not null default '' check (length(instructions) <= 500),
  memory_id uuid references public.memories(id) on delete cascade,
  due_at timestamptz not null,
  timezone text not null,
  confirmed boolean not null default false,
  enabled boolean not null default true,
  version integer not null default 1,
  -- P0 supports explicit one-time occurrences only, not inferred recurrence.
  recurrence text not null default 'once' check (recurrence = 'once'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.foreground_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  schedule_id uuid not null references public.schedules(id) on delete cascade,
  schedule_version integer not null,
  kind text not null check (kind in ('medication','invitation')),
  label text not null,
  state text not null default 'pending' check (state in ('pending','taken','skip','snoozed','accepted','declined','cancelled','expired')),
  action_version integer not null default 1,
  last_request_id uuid,
  conversation_id uuid references public.conversations(id) on delete set null,
  notify_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  unique(schedule_id,schedule_version)
);
create table public.measurement_prompts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  timezone text not null,
  question_version text not null default 'aira-lonely-days-en-v1',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  check (period_end - period_start = 6),
  unique(user_id,question_version,period_start,period_end)
);
create table public.loneliness_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  prompt_id uuid not null unique references public.measurement_prompts(id) on delete cascade,
  lonely_days integer check (lonely_days between 0 and 7),
  skipped boolean not null default false,
  version integer not null default 1,
  last_request_id uuid not null,
  source text not null default 'self_report' check (source = 'self_report'),
  answered_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  check ((skipped and lonely_days is null) or (not skipped and lonely_days is not null))
);
create table public.mood_observations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  label text not null check (label in ('happy','okay','sad','worried','tired')),
  source text not null default 'self_report' check (source = 'self_report'),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours'
);
create table public.incidents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  request_id uuid references public.message_requests(id) on delete cascade,
  source text not null check (source in ('user','assistant','test')),
  reason text not null,
  excerpt text check (length(excerpt) <= 500),
  priority text not null check (priority in ('urgent','review')),
  policy_version text not null default 'prototype-safety-v1',
  state text not null default 'new' check (state in ('new','reviewed','dismissed','followup','closed')),
  version integer not null default 1,
  synthetic boolean not null default false,
  review_reason text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '24 hours',
  unique(request_id,source,policy_version)
);
create table public.test_report_outbox (
  id uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.incidents(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  dispatch_basis text not null check (dispatch_basis in ('urgent_policy','reviewer_approval')),
  consent_version integer not null,
  state text not null default 'queued' check (state in ('queued','test_delivered','acknowledged','cancelled','action_needed','expired')),
  external_delivery boolean not null default false check (not external_delivery),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  acknowledged_at timestamptz,
  expires_at timestamptz not null default now() + interval '24 hours',
  unique(incident_id,recipient_id)
);
create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  subject_id uuid references public.profiles(id) on delete set null,
  action text not null,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days'
);
create index on public.message_requests(user_id,created_at);
create index on public.schedules(due_at) where enabled and confirmed;
create index on public.foreground_events(user_id,notify_at) where state in ('pending','snoozed');

-- New users are always seniors. User-editable auth metadata never assigns staff roles.
create function public.aira_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
 insert into public.profiles(id) values(new.id) on conflict do nothing;
 return new;
end; $$;
create trigger aira_create_profile after insert on auth.users for each row execute function public.aira_new_user();
insert into public.profiles(id) select id from auth.users on conflict do nothing;

-- Direct clients can read their own nonexpired data only. All writes use checked Edge Functions.
-- No policy authorizes arbitrary client SQL, role changes, caregiver verification, or incident writes.
do $$ declare t text; begin
 foreach t in array array['profiles','role_assignments','caregiver_links','conversations','message_requests','messages','memories','schedules','foreground_events','measurement_prompts','loneliness_responses','mood_observations','incidents','test_report_outbox','audit_events'] loop
   execute format('alter table public.%I enable row level security',t);
   execute format('revoke all on public.%I from anon, authenticated',t);
   execute format('grant select on public.%I to authenticated',t);
 end loop;
 foreach t in array array['conversations','message_requests','messages','memories','schedules','foreground_events','measurement_prompts','loneliness_responses','mood_observations'] loop
   execute format('create policy owner_read on public.%I for select to authenticated using (user_id = auth.uid() and expires_at > now() and exists(select 1 from public.profiles p where p.id = auth.uid() and p.enabled))',t);
 end loop;
end $$;
create policy profile_read on public.profiles for select to authenticated using (id = auth.uid() and enabled);
create policy roles_read on public.role_assignments for select to authenticated using (user_id = auth.uid() and enabled);
-- Scoped staff and caregiver reads deliberately go through the audited Edge Function only.

create function public.aira_preferences(p_user uuid, p_patch jsonb) returns public.profiles
language plpgsql security definer set search_path = public, pg_temp as $$
declare old public.profiles; updated public.profiles; begin
 select * into strict old from profiles where id=p_user and enabled for update;
 update profiles set display_name=coalesce(p_patch->>'display_name',display_name),
 timezone=coalesce(p_patch->>'timezone',timezone), text_scale=coalesce((p_patch->>'text_scale')::numeric,text_scale),
 reduced_motion=coalesce((p_patch->>'reduced_motion')::boolean,reduced_motion), onboarded=coalesce((p_patch->>'onboarded')::boolean,onboarded),
 consents=consents || coalesce(p_patch->'consents','{}'::jsonb), consent_version=consent_version+1
 where id=p_user returning * into updated;
 if not (updated.consents->>'conversation_storage')::boolean then delete from messages where user_id=p_user; end if;
 if not (updated.consents->>'memory')::boolean then delete from memories where user_id=p_user; end if;
 if not (updated.consents->>'impact')::boolean then
   delete from measurement_prompts where user_id=p_user; update conversations set completed=false where user_id=p_user;
 end if;
 if not (updated.consents->>'mood_history')::boolean then delete from mood_observations where user_id=p_user; end if;
 if not (updated.consents->>'monitoring')::boolean then delete from incidents where user_id=p_user; end if;
 update foreground_events set state='cancelled' where user_id=p_user and state in ('pending','snoozed') and
  ((kind='invitation' and not (updated.consents->>'social_reminders')::boolean) or (kind='medication' and not (updated.consents->>'medication_reminders')::boolean));
 update test_report_outbox set state='cancelled' where user_id=p_user and state='queued' and
  (not (updated.consents->>'monitoring')::boolean or (dispatch_basis='urgent_policy' and not (updated.consents->>'urgent_sharing')::boolean) or (dispatch_basis='reviewer_approval' and not (updated.consents->>'reviewed_sharing')::boolean));
 insert into audit_events(actor_id,subject_id,action) values(p_user,p_user,'preferences_changed');
 return updated;
end $$;

create function public.aira_reserve_message(p_user uuid,p_client uuid,p_conversation uuid,p_mode text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare req message_requests; conv conversations; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into req from message_requests where user_id=p_user and client_id=p_client;
 if found then return jsonb_build_object('duplicate',true,'request',to_jsonb(req)); end if;
 if (select count(*) from message_requests where user_id=p_user and created_at>now()-interval '1 minute')>=10
 or (select count(*) from message_requests where user_id=p_user and created_at>now()-interval '1 hour')>=20 then raise exception 'rate_limited'; end if;
 if p_conversation is null then
  insert into conversations(user_id,mode) values(p_user,p_mode) returning * into conv;
 else
  select * into conv from conversations where id=p_conversation and user_id=p_user and expires_at>now() and ended_at is null;
  if not found then raise exception 'conversation_not_found'; end if;
 end if;
 insert into message_requests(user_id,client_id,conversation_id) values(p_user,p_client,conv.id) returning * into req;
 return jsonb_build_object('duplicate',false,'request',to_jsonb(req));
end $$;

create function public.aira_finish_message(p_user uuid,p_request uuid,p_input text,p_output text,p_consent_version integer) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; r message_requests; begin
 select * into strict p from profiles where id=p_user and enabled for update;
 select * into strict r from message_requests where id=p_request and user_id=p_user and status='processing' for update;
 if p.consent_version <> p_consent_version then update message_requests set status='failed' where id=r.id; return false; end if;
 if (p.consents->>'conversation_storage')::boolean then
  insert into messages(user_id,request_id,conversation_id,role,text,approved) values
    (p_user,r.id,r.conversation_id,'user',p_input,false),(p_user,r.id,r.conversation_id,'assistant',p_output,true);
 end if;
 if (p.consents->>'impact')::boolean then update conversations set completed=true where id=r.conversation_id; end if;
 update message_requests set status='completed' where id=r.id;
 return true;
end $$;

create function public.aira_incident(p_user uuid,p_request uuid,p_source text,p_reason text,p_excerpt text,p_priority text,p_synthetic boolean default false) returns uuid
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; incident_id uuid; begin
 select * into strict p from profiles where id=p_user and enabled for update;
 if not (p.consents->>'monitoring')::boolean then return null; end if;
 insert into incidents(user_id,request_id,source,reason,excerpt,priority,synthetic)
 values(p_user,p_request,p_source,p_reason,left(p_excerpt,500),p_priority,p_synthetic)
 on conflict(request_id,source,policy_version) do update set reason=excluded.reason returning id into incident_id;
 if p_priority='urgent' and (p.consents->>'urgent_sharing')::boolean then
   insert into test_report_outbox(incident_id,user_id,recipient_id,dispatch_basis,consent_version)
   select incident_id,p_user,l.caregiver_id,'urgent_policy',p.consent_version from caregiver_links l
   where l.senior_id=p_user and l.verified and l.test_recipient and l.revoked_at is null and 'urgent'=any(l.scopes)
   on conflict do nothing;
 end if;
 return incident_id;
end $$;

create function public.aira_worker_tick() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare job record; event_count integer:=0; report_count integer:=0; begin
 -- Serialize short ticks: occurrence uniqueness remains a second deduplication boundary.
 if not pg_try_advisory_xact_lock(20261014) then return '{"busy":true}'::jsonb; end if;
 update foreground_events set state='expired' where expires_at<=now() and state in ('pending','snoozed');
 for job in select s.*,p.consents,p.social_paused_until from schedules s join profiles p on p.id=s.user_id
 where s.enabled and s.confirmed and s.due_at<=now() and s.expires_at>now() and p.enabled
 and not exists(select 1 from foreground_events e where e.schedule_id=s.id and e.schedule_version=s.version)
 order by s.due_at limit 100 for update of s skip locked loop
   if job.kind='medication' and (job.consents->>'medication_reminders')::boolean then
     insert into foreground_events(user_id,schedule_id,schedule_version,kind,label,expires_at)
     values(job.user_id,job.id,job.version,'medication',job.label,job.expires_at) on conflict do nothing;
     event_count:=event_count+1;
   elsif job.kind='event' and (job.consents->>'social_reminders')::boolean and (job.social_paused_until is null or job.social_paused_until<=now())
   and extract(hour from now() at time zone job.timezone)>=9 and extract(hour from now() at time zone job.timezone)<21
   and not exists(select 1 from foreground_events e where e.user_id=job.user_id and e.kind='invitation' and (e.created_at at time zone job.timezone)::date=(now() at time zone job.timezone)::date)
   and not exists(select 1 from conversations c where c.user_id=job.user_id and c.ended_at is null and c.accepted_at>now()-interval '30 minutes') then
     insert into foreground_events(user_id,schedule_id,schedule_version,kind,label,expires_at)
     values(job.user_id,job.id,job.version,'invitation',job.label,least(job.expires_at,now()+interval '30 seconds')) on conflict do nothing;
     event_count:=event_count+1;
   end if;
 end loop;
 -- This update writes only to an internal test inbox. There is no external-send branch.
 update test_report_outbox r set state='test_delivered',delivered_at=now()
 from profiles p,caregiver_links l,incidents i
 where r.state='queued' and r.user_id=p.id and l.senior_id=p.id and l.caregiver_id=r.recipient_id
 and i.id=r.incident_id and i.state not in ('dismissed','closed') and i.expires_at>now() and r.expires_at>now()
 and p.enabled and (p.consents->>'monitoring')::boolean and l.verified and l.test_recipient and l.revoked_at is null
 and ((r.dispatch_basis='urgent_policy' and i.priority='urgent' and (p.consents->>'urgent_sharing')::boolean and 'urgent'=any(l.scopes))
 or (r.dispatch_basis='reviewer_approval' and i.state in ('reviewed','followup') and (p.consents->>'reviewed_sharing')::boolean and 'reviewed'=any(l.scopes)));
 get diagnostics report_count=row_count;
 update test_report_outbox set state='action_needed' where state='queued';
 -- Access filters hide expired rows even if Cron is late; this removes their contents.
 delete from messages where expires_at<=now(); delete from memories where expires_at<=now();
 delete from schedules where expires_at<=now(); delete from measurement_prompts where expires_at<=now();
 delete from mood_observations where expires_at<=now(); delete from incidents where expires_at<=now();
 delete from conversations where expires_at<=now(); delete from audit_events where expires_at<=now();
 update message_requests set status='failed' where status='processing' and created_at<now()-interval '2 minutes';
 return jsonb_build_object('events',event_count,'testReports',report_count,'externalDelivery',false);
end $$;

create function public.aira_event_action(p_user uuid,p_id uuid,p_action text,p_request uuid,p_version integer,p_snooze timestamptz default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare e foreground_events; p profiles; c uuid; begin
 select * into strict p from profiles where id=p_user and enabled for update;
 select * into strict e from foreground_events where id=p_id and user_id=p_user for update;
 if e.last_request_id=p_request then return to_jsonb(e); end if;
 if e.action_version<>p_version or e.expires_at<=now() or e.state in ('cancelled','expired') then raise exception 'state_conflict'; end if;
 if e.kind='medication' then
  if not (p.consents->>'medication_reminders')::boolean or p_action not in ('taken','skip','snooze') then raise exception 'forbidden'; end if;
  if p_action='snooze' and (p_snooze is null or p_snooze<=now() or p_snooze>=e.expires_at) then raise exception 'invalid_snooze'; end if;
  update foreground_events set state=case when p_action='snooze' then 'snoozed' else p_action end,
   notify_at=case when p_action='snooze' then p_snooze else notify_at end,action_version=action_version+1,last_request_id=p_request where id=e.id returning * into e;
 else
  if not (p.consents->>'social_reminders')::boolean or p_action not in ('accept','decline') or e.state<>'pending' then raise exception 'forbidden'; end if;
  if p_action='accept' then insert into conversations(user_id,initiator) values(p_user,'aira') returning id into c;
  else update profiles set social_paused_until=now()+interval '24 hours' where id=p_user; end if;
  update foreground_events set state=case when p_action='accept' then 'accepted' else 'declined' end,
   conversation_id=c,action_version=action_version+1,last_request_id=p_request where id=e.id returning * into e;
 end if;
 return to_jsonb(e);
end $$;

create function public.aira_loneliness(p_user uuid,p_prompt uuid,p_days integer,p_skip boolean,p_request uuid,p_version integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare r loneliness_responses; begin
 perform 1 from profiles where id=p_user and enabled and (consents->>'impact')::boolean for update;
 if not found then raise exception 'forbidden'; end if;
 perform 1 from measurement_prompts where id=p_prompt and user_id=p_user and expires_at>now();
 if not found then raise exception 'prompt_expired'; end if;
 select * into r from loneliness_responses where prompt_id=p_prompt;
 if found then
  if r.last_request_id=p_request then return to_jsonb(r); end if;
  if r.version<>p_version then raise exception 'state_conflict'; end if;
  update loneliness_responses set lonely_days=p_days,skipped=p_skip,version=version+1,last_request_id=p_request,answered_at=now() where id=r.id returning * into r;
 else
  if p_version<>0 then raise exception 'state_conflict'; end if;
  insert into loneliness_responses(user_id,prompt_id,lonely_days,skipped,last_request_id) values(p_user,p_prompt,p_days,p_skip,p_request) returning * into r;
 end if;
 insert into audit_events(actor_id,subject_id,action) values(p_user,p_user,'loneliness_response_saved');
 return to_jsonb(r);
end $$;

create function public.aira_purge(p_user uuid) returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
 update profiles set enabled=false,display_name='',timezone='Asia/Singapore',text_scale=1,onboarded=false,consents='{}'::jsonb,consent_version=consent_version+1 where id=p_user;
 delete from caregiver_links where senior_id=p_user; delete from incidents where user_id=p_user;
 delete from memories where user_id=p_user; delete from schedules where user_id=p_user;
 delete from measurement_prompts where user_id=p_user; delete from mood_observations where user_id=p_user;
 delete from conversations where user_id=p_user;
 insert into audit_events(actor_id,subject_id,action) values(p_user,p_user,'app_data_deleted');
end $$;

-- SECURITY DEFINER entry points must never be callable by an untrusted client.
revoke execute on function public.aira_new_user() from public,anon,authenticated;
revoke execute on function public.aira_preferences(uuid,jsonb) from public,anon,authenticated;
revoke execute on function public.aira_reserve_message(uuid,uuid,uuid,text) from public,anon,authenticated;
revoke execute on function public.aira_finish_message(uuid,uuid,text,text,integer) from public,anon,authenticated;
revoke execute on function public.aira_incident(uuid,uuid,text,text,text,text,boolean) from public,anon,authenticated;
revoke execute on function public.aira_worker_tick() from public,anon,authenticated;
revoke execute on function public.aira_event_action(uuid,uuid,text,uuid,integer,timestamptz) from public,anon,authenticated;
revoke execute on function public.aira_loneliness(uuid,uuid,integer,boolean,uuid,integer) from public,anon,authenticated;
revoke execute on function public.aira_purge(uuid) from public,anon,authenticated;
grant execute on all functions in schema public to service_role;
grant all on all tables in schema public to service_role;
grant usage,select on all sequences in schema public to service_role;

-- Atomic edits prevent a worker from dispatching a superseded occurrence.
create function public.aira_schedule_edit(p_user uuid,p_id uuid,p_kind text,p_version integer,p_patch jsonb) returns jsonb
language plpgsql security definer set search_path = public,pg_temp as $$
declare s schedules; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into strict s from schedules where id=p_id and user_id=p_user and kind=p_kind and expires_at>now() for update;
 if s.version<>p_version then raise exception 'state_conflict'; end if;
 if p_patch ? 'due_at' and (p_patch->>'due_at')::timestamptz>=s.expires_at then raise exception 'state_conflict'; end if;
 update schedules set label=coalesce(p_patch->>'label',label),due_at=coalesce((p_patch->>'due_at')::timestamptz,due_at),
 enabled=coalesce((p_patch->>'enabled')::boolean,enabled),version=version+1 where id=p_id returning * into s;
 update foreground_events set state='cancelled' where schedule_id=p_id and state in ('pending','snoozed');
 return to_jsonb(s);
end $$;
create function public.aira_memory_edit(p_user uuid,p_id uuid,p_version integer,p_text text) returns integer
language plpgsql security definer set search_path = public,pg_temp as $$
declare v integer; begin
 perform 1 from profiles where id=p_user and enabled and (consents->>'memory')::boolean for update;
 if not found then raise exception 'forbidden'; end if;
 if p_text is null then delete from memories where id=p_id and user_id=p_user;
 else
  update memories set text=p_text,version=version+1 where id=p_id and user_id=p_user and version=p_version and expires_at>now();
  if not found then raise exception 'state_conflict'; end if;
 end if;
 delete from messages where user_id=p_user;
 update profiles set consent_version=consent_version+1 where id=p_user returning consent_version into v;
 return v;
end $$;
alter table public.profiles add column last_prompt_date date;
create function public.aira_prompt(p_user uuid) returns jsonb
language plpgsql security definer set search_path = public,pg_temp as $$
declare p profiles; prompt measurement_prompts; today date; begin
 select * into strict p from profiles where id=p_user and enabled and (consents->>'impact')::boolean for update;
 select * into prompt from measurement_prompts where user_id=p_user and expires_at>now() order by created_at desc limit 1;
 if found then return to_jsonb(prompt); end if;
 today:=(now() at time zone p.timezone)::date;
 if p.last_prompt_date is not null and today<p.last_prompt_date+7 then return null; end if;
 insert into measurement_prompts(user_id,period_start,period_end,timezone) values(p_user,today-7,today-1,p.timezone) returning * into prompt;
 update profiles set last_prompt_date=today where id=p_user;
 return to_jsonb(prompt);
end $$;
create table public.provider_usage (
 user_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check(kind in ('speech','transcription')),
 created_at timestamptz not null default now()
);
alter table public.provider_usage enable row level security;
revoke all on public.provider_usage from public,anon,authenticated;
grant all on public.provider_usage to service_role;
create function public.aira_media_limit(p_user uuid,p_kind text) returns void
language plpgsql security definer set search_path = public,pg_temp as $$
begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 if (select count(*) from provider_usage where user_id=p_user and created_at>now()-interval '1 hour')>=40 then raise exception 'rate_limited'; end if;
 delete from provider_usage where created_at<now()-interval '24 hours';
 insert into provider_usage(user_id,kind) values(p_user,p_kind);
end $$;
revoke execute on function public.aira_schedule_edit(uuid,uuid,text,integer,jsonb) from public,anon,authenticated;
revoke execute on function public.aira_memory_edit(uuid,uuid,integer,text) from public,anon,authenticated;
revoke execute on function public.aira_prompt(uuid) from public,anon,authenticated;
revoke execute on function public.aira_media_limit(uuid,text) from public,anon,authenticated;
grant execute on function public.aira_schedule_edit(uuid,uuid,text,integer,jsonb),public.aira_memory_edit(uuid,uuid,integer,text),public.aira_prompt(uuid),public.aira_media_limit(uuid,text) to service_role;
