-- Ephemeral live-call context: no image/audio or transcript storage here.
create table public.realtime_sessions (
 conversation_id uuid primary key references public.conversations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 consent_version integer not null,
 context jsonb not null default '{}'::jsonb,
 expires_at timestamptz not null default now()+interval '15 minutes'
);
alter table public.realtime_sessions enable row level security;
revoke all on public.realtime_sessions from anon, authenticated;
grant all on public.realtime_sessions to service_role;
create index realtime_sessions_user_expiry on public.realtime_sessions(user_id,expires_at);

-- The profile lock serializes simultaneous starts and privacy updates for one owner.
-- Only the trusted API may pass p_user; clients cannot execute this RPC directly.
create function public.aira_reserve_call(p_user uuid,p_mode text,p_consent_version integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; conv conversations; session realtime_sessions; begin
 select * into p from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 if p_mode is null or p_mode not in ('voice','video') then raise exception 'invalid_mode'; end if;
 if p_consent_version is distinct from p.consent_version then raise exception 'state_conflict'; end if;
 if (select count(*) from realtime_sessions s join conversations c on c.id=s.conversation_id
     where s.user_id=p_user and s.expires_at>now() and s.consent_version=p.consent_version
     and c.user_id=p_user and c.ended_at is null and c.expires_at>now()) >= 2
 then raise exception 'rate_limited'; end if;
 insert into conversations(user_id,mode,initiator) values(p_user,p_mode,'aira') returning * into conv;
 insert into realtime_sessions(conversation_id,user_id,consent_version,expires_at)
 values(conv.id,p_user,p.consent_version,now()+interval '15 minutes') returning * into session;
 return jsonb_build_object('conversation',to_jsonb(conv),'session',to_jsonb(session));
end $$;
revoke execute on function public.aira_reserve_call(uuid,text,integer) from public,anon,authenticated;
grant execute on function public.aira_reserve_call(uuid,text,integer) to service_role;

-- Keep the established minute worker entry point and result shape. The wrapper
-- removes ephemeral context at its 15-minute deadline, as well as revoked calls.
alter function public.aira_worker_tick() rename to aira_worker_tick_core;
revoke execute on function public.aira_worker_tick_core() from public,anon,authenticated,service_role;
create function public.aira_worker_tick() returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
begin
 if not pg_try_advisory_xact_lock(20261014) then return '{"busy":true}'::jsonb; end if;
 with removed as (
  delete from realtime_sessions s using profiles p,conversations c
  where p.id=s.user_id and c.id=s.conversation_id
  and (s.expires_at<=now() or not p.enabled or s.consent_version<>p.consent_version
       or c.ended_at is not null or c.expires_at<=now())
  returning s.conversation_id
 )
 update conversations c set ended_at=coalesce(c.ended_at,now())
 from removed r where c.id=r.conversation_id;
 return aira_worker_tick_core();
end $$;
revoke execute on function public.aira_worker_tick() from public,anon,authenticated;
grant execute on function public.aira_worker_tick() to service_role;

-- Allow natural turn-taking within bounded live calls. Existing text limit remains 20/hour.
create or replace function public.aira_reserve_message(p_user uuid,p_client uuid,p_conversation uuid,p_mode text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare req message_requests; conv conversations; live_call boolean := false; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into req from message_requests where user_id=p_user and client_id=p_client;
 if found then return jsonb_build_object('duplicate',true,'request',to_jsonb(req)); end if;
 live_call := exists(select 1 from realtime_sessions s join conversations c on c.id=s.conversation_id
  where s.conversation_id=p_conversation and s.user_id=p_user and s.expires_at>now() and c.ended_at is null);
 if (select count(*) from message_requests where user_id=p_user and created_at>now()-interval '1 minute')>=10
 or (select count(*) from message_requests where user_id=p_user and created_at>now()-interval '1 hour') >= (case when live_call then 120 else 20 end)
 then raise exception 'rate_limited'; end if;
 if p_conversation is null then
  insert into conversations(user_id,mode) values(p_user,p_mode) returning * into conv;
 else
  select * into conv from conversations where id=p_conversation and user_id=p_user and expires_at>now() and ended_at is null;
  if not found then raise exception 'conversation_not_found'; end if;
 end if;
 insert into message_requests(user_id,client_id,conversation_id) values(p_user,p_client,conv.id) returning * into req;
 return jsonb_build_object('duplicate',false,'request',to_jsonb(req));
end $$;
