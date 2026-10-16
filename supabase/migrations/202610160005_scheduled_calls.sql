-- Explicit daily, foreground-only incoming voice invitations. These are separate
-- from inferred social reminders: the owner's chosen time overrides quiet hours.
-- The schedule persists until deletion; no phone call or background push is sent.
create table public.call_schedules (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null unique references public.profiles(id) on delete cascade,
 local_time time without time zone not null,
 timezone text not null,
 enabled boolean not null default true,
 version integer not null default 1,
 next_due_at timestamptz not null,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table public.scheduled_call_invitations (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 schedule_id uuid not null references public.call_schedules(id) on delete cascade,
 schedule_version integer not null,
 scheduled_for timestamptz not null,
 expires_at timestamptz not null,
 state text not null check(state in ('ringing','accepted','declined','missed','cancelled','started')),
 version integer not null default 1,
 last_request_id uuid,
 conversation_id uuid references public.conversations(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(schedule_id,scheduled_for)
);
create index call_schedule_due on public.call_schedules(next_due_at) where enabled;
create index scheduled_call_owner_state on public.scheduled_call_invitations(user_id,state,expires_at);
alter table public.call_schedules enable row level security;
alter table public.scheduled_call_invitations enable row level security;
revoke all on public.call_schedules,public.scheduled_call_invitations from anon,authenticated;
grant all on public.call_schedules,public.scheduled_call_invitations to service_role;

-- Use civil dates in the selected IANA zone, rather than adding 24 hours in UTC.
-- PostgreSQL resolves a skipped daylight-saving time to the following valid time;
-- a repeated local time still produces only one occurrence on that local date.
create function public.aira_next_daily_call(p_time time,p_timezone text,p_after timestamptz)
returns timestamptz language plpgsql stable set search_path=public,pg_temp as $$
declare local_date date; candidate timestamptz; begin
 if not exists(select 1 from pg_timezone_names where name=p_timezone) then raise exception 'state_conflict'; end if;
 local_date := (p_after at time zone p_timezone)::date;
 candidate := (local_date+p_time) at time zone p_timezone;
 if candidate<=p_after then candidate:=((local_date+1)+p_time) at time zone p_timezone; end if;
 return candidate;
end $$;

create function public.aira_call_schedule_tick(p_user uuid default null) returns integer
language plpgsql security definer set search_path=public,pg_temp as $$
declare owner profiles; schedule call_schedules; created integer:=0; inserted integer; invite_state text; begin
 -- Always lock profile before schedule and invitation, matching save/respond/start.
 for owner in select p.* from profiles p where p.enabled and (p_user is null or p.id=p_user)
 and (exists(select 1 from call_schedules s where s.user_id=p.id and s.enabled and s.next_due_at<=now())
   or exists(select 1 from scheduled_call_invitations i where i.user_id=p.id and i.state in ('ringing','accepted') and i.expires_at<=now()))
 order by p.id limit 100 for update of p skip locked loop
  update scheduled_call_invitations set state='missed',version=version+1
   where user_id=owner.id and state in ('ringing','accepted') and expires_at<=now();
  select * into schedule from call_schedules where user_id=owner.id for update;
  if found and schedule.enabled and schedule.next_due_at<=now() then
   -- A late worker or a busy owner must never receive a surprise catch-up call.
   invite_state:=case when schedule.next_due_at+interval '2 minutes'>now()
    and not exists(select 1 from realtime_sessions r join conversations c on c.id=r.conversation_id
      where r.user_id=owner.id and r.expires_at>now() and r.consent_version=owner.consent_version and c.ended_at is null)
    then 'ringing' else 'missed' end;
   insert into scheduled_call_invitations(user_id,schedule_id,schedule_version,scheduled_for,expires_at,state)
    values(owner.id,schedule.id,schedule.version,schedule.next_due_at,schedule.next_due_at+interval '2 minutes',invite_state)
    on conflict(schedule_id,scheduled_for) do nothing;
   get diagnostics inserted=row_count;
   if invite_state='ringing' then created:=created+inserted; end if;
   update call_schedules set next_due_at=aira_next_daily_call(local_time,timezone,now()),updated_at=now() where id=schedule.id;
  end if;
  delete from scheduled_call_invitations where user_id=owner.id and created_at<now()-interval '7 days'
   and state not in ('ringing','accepted');
 end loop;
 return created;
end $$;

create function public.aira_call_schedule_get(p_user uuid) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare schedule call_schedules; invitation scheduled_call_invitations; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 -- Foreground polling also catches the chosen minute if Cron is temporarily late.
 perform aira_call_schedule_tick(p_user);
 select * into schedule from call_schedules where user_id=p_user;
 select i.* into invitation from scheduled_call_invitations i join call_schedules s on s.id=i.schedule_id
  where i.user_id=p_user and i.state='ringing' and i.expires_at>now() and s.enabled and i.schedule_version=s.version
  order by i.scheduled_for desc limit 1;
 return jsonb_build_object('schedule',case when schedule.id is null then null else jsonb_build_object(
  'id',schedule.id,'localTime',to_char(schedule.local_time,'HH24:MI'),'timeZone',schedule.timezone,
  'enabled',schedule.enabled,'version',schedule.version,'nextCallAt',case when schedule.enabled then schedule.next_due_at else null end) end,
  'incomingCall',case when invitation.id is null then null else jsonb_build_object(
   'id',invitation.id,'scheduleId',invitation.schedule_id,'state',invitation.state,
   'scheduledFor',invitation.scheduled_for,'expiresAt',invitation.expires_at,'version',invitation.version) end,
  'foregroundOnly',true);
end $$;

create function public.aira_call_schedule_save(p_user uuid,p_local_time text,p_timezone text,p_enabled boolean,p_version integer default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare existing call_schedules; next_due timestamptz; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 if p_local_time is null or p_local_time!~'^([01][0-9]|2[0-3]):[0-5][0-9]$' or p_enabled is null then raise exception 'state_conflict'; end if;
 next_due:=aira_next_daily_call(p_local_time::time,p_timezone,now());
 select * into existing from call_schedules where user_id=p_user for update;
 if found then
  if p_version is distinct from existing.version then raise exception 'state_conflict'; end if;
  update call_schedules set local_time=p_local_time::time,timezone=p_timezone,enabled=p_enabled,
   version=version+1,next_due_at=next_due,updated_at=now() where id=existing.id;
  update scheduled_call_invitations set state='cancelled',version=version+1
   where schedule_id=existing.id and state in ('ringing','accepted');
 else
  if p_version is not null then raise exception 'state_conflict'; end if;
  insert into call_schedules(user_id,local_time,timezone,enabled,next_due_at)
   values(p_user,p_local_time::time,p_timezone,p_enabled,next_due);
 end if;
 return aira_call_schedule_get(p_user);
end $$;

create function public.aira_call_schedule_delete(p_user uuid,p_version integer) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare schedule call_schedules; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into schedule from call_schedules where user_id=p_user for update;
 if not found or schedule.version is distinct from p_version then raise exception 'state_conflict'; end if;
 delete from call_schedules where id=schedule.id;
 return jsonb_build_object('schedule',null,'incomingCall',null,'foregroundOnly',true);
end $$;

create function public.aira_scheduled_call_respond(p_user uuid,p_id uuid,p_action text,p_request uuid,p_version integer) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare invitation scheduled_call_invitations; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into invitation from scheduled_call_invitations where id=p_id and user_id=p_user for update;
 if not found then raise exception 'forbidden'; end if;
 if p_action is null or p_action not in ('accept','decline') or p_request is null then raise exception 'state_conflict'; end if;
 if invitation.last_request_id is distinct from p_request then
  if invitation.version is distinct from p_version or invitation.state<>'ringing' or invitation.expires_at<=now()
   or not exists(select 1 from call_schedules s where s.id=invitation.schedule_id and s.enabled and s.version=invitation.schedule_version)
   then raise exception 'state_conflict'; end if;
  update scheduled_call_invitations set state=case when p_action='accept' then 'accepted' else 'declined' end,
   version=version+1,last_request_id=p_request,
   expires_at=case when p_action='accept' then now()+interval '2 minutes' else expires_at end
   where id=invitation.id returning * into invitation;
 elsif (p_action='accept' and invitation.state not in ('accepted','started')) or (p_action='decline' and invitation.state<>'declined') then
  raise exception 'state_conflict';
 end if;
 return jsonb_build_object('invitation',jsonb_build_object('id',invitation.id,'state',invitation.state,'version',invitation.version),
  'startCall',invitation.state='accepted' and invitation.expires_at>now());
end $$;

create function public.aira_reserve_scheduled_call(p_user uuid,p_invitation uuid,p_mode text,p_consent_version integer) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare invitation scheduled_call_invitations; reserved jsonb; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into invitation from scheduled_call_invitations where id=p_invitation and user_id=p_user for update;
 if not found then raise exception 'forbidden'; end if;
 if p_mode is distinct from 'voice' or invitation.state<>'accepted' or invitation.expires_at<=now()
  or not exists(select 1 from call_schedules s where s.id=invitation.schedule_id and s.enabled and s.version=invitation.schedule_version)
  then raise exception 'state_conflict'; end if;
 reserved:=aira_reserve_call(p_user,p_mode,p_consent_version);
 update conversations set initiator='aira' where id=(reserved->'conversation'->>'id')::uuid;
 reserved:=jsonb_set(reserved,'{conversation,initiator}','"aira"'::jsonb);
 update scheduled_call_invitations set state='started',version=version+1,
  conversation_id=(reserved->'conversation'->>'id')::uuid where id=invitation.id;
 return reserved;
end $$;

-- Account deletion currently disables the profile before removing app data.
create function public.aira_remove_disabled_call_schedule() returns trigger
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if not new.enabled then delete from call_schedules where user_id=new.id; end if;
 return new;
end $$;
create trigger aira_disabled_call_schedule after update of enabled on public.profiles
 for each row execute function public.aira_remove_disabled_call_schedule();

alter function public.aira_worker_tick() rename to aira_worker_tick_before_scheduled_calls;
revoke execute on function public.aira_worker_tick_before_scheduled_calls() from public,anon,authenticated,service_role;
create function public.aira_worker_tick() returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare base jsonb; incoming integer; begin
 if not pg_try_advisory_xact_lock(20261014) then return '{"busy":true}'::jsonb; end if;
 base:=aira_worker_tick_before_scheduled_calls();
 incoming:=aira_call_schedule_tick();
 return base||jsonb_build_object('scheduledCalls',incoming);
end $$;

revoke execute on function public.aira_next_daily_call(time,text,timestamptz),public.aira_call_schedule_tick(uuid),
 public.aira_call_schedule_get(uuid),public.aira_call_schedule_save(uuid,text,text,boolean,integer),
 public.aira_call_schedule_delete(uuid,integer),public.aira_scheduled_call_respond(uuid,uuid,text,uuid,integer),
 public.aira_reserve_scheduled_call(uuid,uuid,text,integer),public.aira_remove_disabled_call_schedule(),public.aira_worker_tick()
 from public,anon,authenticated;
grant execute on function public.aira_call_schedule_get(uuid),public.aira_call_schedule_save(uuid,text,text,boolean,integer),
 public.aira_call_schedule_delete(uuid,integer),public.aira_scheduled_call_respond(uuid,uuid,text,uuid,integer),
 public.aira_reserve_scheduled_call(uuid,uuid,text,integer),public.aira_worker_tick() to service_role;
