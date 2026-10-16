-- 16 October 2026: live calls use the native ElevenLabs agent. Their transcripts
-- are a separate archive, never text-chat input or text-message quota usage.
create table public.call_transcripts (
 conversation_id uuid primary key references public.conversations(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 consent_version integer not null,
 call_binding text not null,
 provider_id text,
 entries jsonb not null default '[]'::jsonb check(jsonb_typeof(entries)='array'),
 source text not null default 'pending' check(source in ('pending','device_captions','elevenlabs','legacy_bridge')),
 status text not null default 'pending' check(status in ('pending','ready','unavailable')),
 provider_status text,
 sync_attempts integer not null default 0,
 last_sync_at timestamptz,
 archive_order bigint generated always as identity unique,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default 'infinity'
);
alter table public.call_transcripts enable row level security;
revoke all on public.call_transcripts from anon,authenticated;
grant all on public.call_transcripts to service_role;
grant usage,select on sequence public.call_transcripts_archive_order_seq to service_role;
create index call_transcripts_owner_order on public.call_transcripts(user_id,archive_order desc);

-- Preserve earlier saved call text, but move its presentation into Call history.
insert into call_transcripts(conversation_id,user_id,consent_version,call_binding,entries,source,status,created_at)
select c.id,c.user_id,p.consent_version,replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''),
 jsonb_agg(jsonb_build_object('role',m.role,'text',m.text,'timeInCallSecs',greatest(0,extract(epoch from m.created_at-c.accepted_at))::integer) order by m.history_order),
 'legacy_bridge','ready',c.accepted_at
from conversations c join profiles p on p.id=c.user_id
join messages m on m.conversation_id=c.id
where c.mode in ('voice','video') and p.enabled and coalesce((p.consents->>'conversation_storage')::boolean,false)
and m.expires_at>now() and c.expires_at>now() and (m.role='user' or m.approved)
group by c.id,p.consent_version;

create or replace function public.aira_reserve_call(p_user uuid,p_mode text,p_consent_version integer) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; conv conversations; session realtime_sessions; binding text := replace(gen_random_uuid()::text||gen_random_uuid()::text,'-',''); begin
 select * into p from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 if p_mode is null or p_mode not in ('voice','video') then raise exception 'invalid_mode'; end if;
 if p_consent_version is distinct from p.consent_version then raise exception 'state_conflict'; end if;
 if (select count(*) from realtime_sessions s join conversations c on c.id=s.conversation_id
     where s.user_id=p_user and s.expires_at>now() and s.consent_version=p.consent_version
     and c.user_id=p_user and c.ended_at is null and c.expires_at>now()) >= 2
 then raise exception 'rate_limited'; end if;
 insert into conversations(user_id,mode,initiator) values(p_user,p_mode,'senior') returning * into conv;
 insert into realtime_sessions(conversation_id,user_id,consent_version,expires_at)
 values(conv.id,p_user,p.consent_version,now()+interval '15 minutes') returning * into session;
 if coalesce((p.consents->>'conversation_storage')::boolean,false) then
  update conversations set expires_at='infinity' where id=conv.id;
  insert into call_transcripts(conversation_id,user_id,consent_version,call_binding)
  values(conv.id,p_user,p.consent_version,binding);
 end if;
 return jsonb_build_object('conversation',to_jsonb(conv),'session',to_jsonb(session),'callBinding',binding);
end $$;

-- The old counter included every spoken turn. Count only the matching mode;
-- retries of failed requests may resume the same id instead of staying failed.
create or replace function public.aira_reserve_message(p_user uuid,p_client uuid,p_conversation uuid,p_mode text) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare req message_requests; conv conversations; cap integer; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 if p_mode is null or p_mode not in ('text','voice','video') then raise exception 'invalid_mode'; end if;
 select * into req from message_requests where user_id=p_user and client_id=p_client for update;
 if found then
  if req.status='failed' then
   select * into conv from conversations where id=req.conversation_id and user_id=p_user and mode=p_mode and expires_at>now() and ended_at is null;
   if not found then raise exception 'conversation_not_found'; end if;
   update message_requests set status='processing',created_at=now() where id=req.id returning * into req;
   return jsonb_build_object('duplicate',false,'request',to_jsonb(req));
  end if;
  return jsonb_build_object('duplicate',true,'request',to_jsonb(req));
 end if;
 if p_mode<>'text' and not exists(select 1 from realtime_sessions s join conversations c on c.id=s.conversation_id
  where s.conversation_id=p_conversation and s.user_id=p_user and s.expires_at>now() and c.ended_at is null)
 then raise exception 'conversation_not_found'; end if;
 cap := case when p_mode='text' then 20 else 120 end;
 if (select count(*) from message_requests r join conversations c on c.id=r.conversation_id
     where r.user_id=p_user and c.mode=p_mode and r.created_at>now()-interval '1 minute')>=10
 or (select count(*) from message_requests r join conversations c on c.id=r.conversation_id
     where r.user_id=p_user and c.mode=p_mode and r.created_at>now()-interval '1 hour')>=cap
 then raise exception 'rate_limited'; end if;
 if p_conversation is null then
  insert into conversations(user_id,mode) values(p_user,p_mode) returning * into conv;
 else
  select * into conv from conversations where id=p_conversation and user_id=p_user and mode=p_mode and expires_at>now() and ended_at is null;
  if not found then raise exception 'conversation_not_found'; end if;
 end if;
 insert into message_requests(user_id,client_id,conversation_id) values(p_user,p_client,conv.id) returning * into req;
 return jsonb_build_object('duplicate',false,'request',to_jsonb(req));
end $$;

create function public.aira_save_call_transcript(p_user uuid,p_call uuid,p_provider text,p_entries jsonb,p_source text,p_status text,p_provider_status text default null) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; item call_transcripts; begin
 select * into p from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 select * into item from call_transcripts where conversation_id=p_call and user_id=p_user for update;
 if not found or not coalesce((p.consents->>'conversation_storage')::boolean,false) then return false; end if;
 if item.consent_version<>p.consent_version then return false; end if;
 if item.provider_id is not null and p_provider is distinct from item.provider_id then raise exception 'state_conflict'; end if;
 if p_source not in ('pending','device_captions','elevenlabs') or p_status not in ('pending','ready','unavailable')
 or jsonb_typeof(p_entries)<>'array' or jsonb_array_length(p_entries)>500 or octet_length(p_entries::text)>262144 then raise exception 'state_conflict'; end if;
 update call_transcripts set provider_id=coalesce(provider_id,p_provider),
  entries=case when p_source='elevenlabs' or (source<>'elevenlabs' and jsonb_array_length(p_entries)>=jsonb_array_length(entries)) then p_entries else entries end,
  source=case when p_source='elevenlabs' or (source<>'elevenlabs' and jsonb_array_length(p_entries)>0) then p_source else source end,
  status=case when p_source='elevenlabs' then p_status when source='elevenlabs' then status when jsonb_array_length(p_entries)>0 or jsonb_array_length(entries)>0 then 'ready' else p_status end,
  provider_status=coalesce(p_provider_status,provider_status)
 where conversation_id=p_call;
 if jsonb_array_length(p_entries)>0 and coalesce((p.consents->>'impact')::boolean,false) then
  update conversations set completed=true where id=p_call;
 end if;
 return true;
end $$;
revoke execute on function public.aira_save_call_transcript(uuid,uuid,text,jsonb,text,text,text) from public,anon,authenticated;
grant execute on function public.aira_save_call_transcript(uuid,uuid,text,jsonb,text,text,text) to service_role;

create function public.aira_call_history(p_user uuid,p_before bigint default null,p_call uuid default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; rows jsonb; cursor text; total integer; begin
 select * into p from profiles where id=p_user and enabled for share;
 if not found then raise exception 'forbidden'; end if;
 if not coalesce((p.consents->>'conversation_storage')::boolean,false) then
  return jsonb_build_object('calls','[]'::jsonb,'nextCursor',null,'privacyVersion',p.consent_version);
 end if;
 select jsonb_agg(row order by ordering desc),count(*) into rows,total from (
  select a.archive_order ordering,jsonb_build_object('id',c.id,'mode',c.mode,'startedAt',c.accepted_at,'endedAt',c.ended_at,
   'initiator',c.initiator,'turnCount',jsonb_array_length(a.entries),'status',a.status,'source',a.source,
   'order',a.archive_order::text,'entries',case when p_call is not null then a.entries else null end) row
  from call_transcripts a join conversations c on c.id=a.conversation_id
  where a.user_id=p_user and c.user_id=p_user and a.expires_at>now() and c.expires_at>now()
  and (p_call is null or a.conversation_id=p_call) and (p_before is null or a.archive_order<p_before)
  order by a.archive_order desc limit 21
 ) page;
 if total>20 then rows=rows-20; cursor=rows->19->>'order'; end if;
 return jsonb_build_object('calls',coalesce(rows,'[]'::jsonb),'nextCursor',cursor,'privacyVersion',p.consent_version);
end $$;
revoke execute on function public.aira_call_history(uuid,bigint,uuid) from public,anon,authenticated;
grant execute on function public.aira_call_history(uuid,bigint,uuid) to service_role;

create function public.aira_delete_call_transcript(p_user uuid,p_call uuid) returns boolean
language plpgsql security definer set search_path = public,pg_temp as $$
begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 delete from call_transcripts where conversation_id=p_call and user_id=p_user;
 delete from messages where conversation_id=p_call and user_id=p_user;
 update conversations set expires_at=least(expires_at,now()+interval '24 hours') where id=p_call and user_id=p_user;
 return true;
end $$;
revoke execute on function public.aira_delete_call_transcript(uuid,uuid) from public,anon,authenticated;
grant execute on function public.aira_delete_call_transcript(uuid,uuid) to service_role;

create or replace function public.aira_history_opt_out() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
 if not coalesce((new.consents->>'conversation_storage')::boolean,false) then
  delete from call_transcripts where user_id=new.id;
  update conversations set expires_at=least(expires_at,now()+interval '24 hours') where user_id=new.id;
  update message_requests set expires_at=least(expires_at,now()+interval '24 hours') where user_id=new.id;
 end if;
 return new;
end $$;

create or replace function public.aira_clear_chat_history(p_user uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare v integer; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 delete from conversations where user_id=p_user and mode='text';
 update profiles set consent_version=consent_version+1 where id=p_user returning consent_version into v;
 insert into audit_events(actor_id,subject_id,action) values(p_user,p_user,'chat_history_deleted');
 return v;
end $$;

create or replace function public.aira_chat_history(p_user uuid,p_before bigint default null,p_limit integer default 50) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; rows jsonb; cursor text; latest text; total integer; begin
 select * into p from profiles where id=p_user and enabled for share;
 if not found then raise exception 'forbidden'; end if;
 if p_limit not between 1 and 100 or (p_before is not null and p_before<1) then raise exception 'state_conflict'; end if;
 if not coalesce((p.consents->>'conversation_storage')::boolean,false) then
  return jsonb_build_object('messages','[]'::jsonb,'nextCursor',null,'conversationId',null,'privacyVersion',p.consent_version);
 end if;
 select jsonb_agg(row order by ordering),count(*) into rows,total from (
  select m.history_order ordering,jsonb_build_object(
   'id',case when m.role='user' then r.client_id else r.id end,
   'text',m.text,'role',m.role,'createdAt',m.created_at,'mode',c.mode,
   'order',m.history_order::text,'contextVersion',m.context_version,
   'requestStatus',r.status,'delivery',case when r.status='completed' then 'read' else 'delivered' end
  ) row
  from messages m join message_requests r on r.id=m.request_id and r.user_id=p_user
  join conversations c on c.id=m.conversation_id and c.user_id=p_user
  where m.user_id=p_user and c.mode='text' and m.expires_at>now() and r.expires_at>now() and c.expires_at>now()
  and (m.role='user' or m.approved) and (p_before is null or m.history_order<p_before)
  order by m.history_order desc limit p_limit+1
 ) page;
 if total>p_limit then
  rows=rows-0;
  cursor=rows->0->>'order';
 end if;
 select id::text into latest from conversations c
 where c.user_id=p_user and c.mode='text' and c.ended_at is null and c.expires_at>now()
 and exists(select 1 from messages m where m.conversation_id=c.id and m.user_id=p_user and m.expires_at>now())
 order by c.accepted_at desc limit 1;
 return jsonb_build_object('messages',coalesce(rows,'[]'::jsonb),'nextCursor',cursor,'conversationId',latest,'privacyVersion',p.consent_version);
end $$;
