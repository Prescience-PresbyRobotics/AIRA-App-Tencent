-- Shared owner-scoped conversational context and user-authorized automatic notes/reminders.
alter table public.memories alter column expires_at set default 'infinity';
alter table public.schedules alter column expires_at set default 'infinity';
update public.memories set expires_at='infinity' where expires_at>now();
update public.schedules set expires_at='infinity' where expires_at>now();
alter table public.memories add column auto_key text, add column source_quote text, add column source_conversation uuid references public.conversations(id) on delete set null;
alter table public.schedules add column auto_key text, add column source_quote text, add column source_conversation uuid references public.conversations(id) on delete set null;
create unique index memories_auto_key on public.memories(user_id,auto_key) where auto_key is not null;
create unique index schedules_auto_key on public.schedules(user_id,kind,auto_key) where auto_key is not null;
alter table public.realtime_sessions add column call_binding text;
alter table public.schedules drop constraint schedules_recurrence_check;
alter table public.schedules add constraint schedules_recurrence_check check(recurrence in ('once','daily') and (recurrence='once' or kind='medication'));

-- Every read rechecks the current privacy epoch. Deleting/forgetting cannot feed
-- an older archive back into either model. Saved notes survive unrelated context edits.
create function public.aira_shared_context(p_user uuid,p_version integer,p_query text default null,p_exclude uuid default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare p profiles; notes jsonb; plans jsonb; turns jsonb; search text; terms tsquery; begin
 select * into p from profiles where id=p_user and enabled for share;
 if not found or p.consent_version<>p_version then raise exception 'state_conflict'; end if;
 search:=nullif(trim(left(p_query,100)),'');
 if search is not null then terms:=replace(plainto_tsquery('english',search)::text,' & ',' | ')::tsquery; end if;
 select coalesce(jsonb_agg(to_jsonb(m)),'[]'::jsonb) into notes from (
  select id,text,category,auto_key from memories where user_id=p_user and expires_at>now() and confirmed
   and coalesce((p.consents->>'memory')::boolean,false) and (search is null or to_tsvector('english',text) @@ terms)
  order by created_at desc limit 80
 ) m;
 select coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) into plans from (
  select id,kind,label,instructions,due_at,timezone,recurrence,auto_key from schedules where user_id=p_user and enabled and expires_at>now()
   and ((kind='medication' and coalesce((p.consents->>'medication_reminders')::boolean,false)) or (kind='event' and coalesce((p.consents->>'social_reminders')::boolean,false)))
   and (search is null or to_tsvector('english',label||' '||instructions) @@ terms)
  order by due_at desc limit 50
 ) s;
 if coalesce((p.consents->>'conversation_storage')::boolean,false) then
  select coalesce(jsonb_agg(to_jsonb(t) order by t.at),'[]'::jsonb) into turns from (
   select * from (
    select m.role,left(m.text,2000) text,m.created_at at,'text'::text mode,case when terms is null then 0 else ts_rank(to_tsvector('english',m.text),terms) end relevance from messages m join conversations c on c.id=m.conversation_id
     where m.user_id=p_user and c.user_id=p_user and c.mode='text' and m.context_version=p_version and m.expires_at>now() and c.expires_at>now()
     and (m.role='user' or m.approved) and (p_exclude is null or m.request_id<>p_exclude)
     and (search is null or to_tsvector('english',m.text) @@ terms)
    union all
    select e.value->>'role',left(e.value->>'text',2000),c.accepted_at+make_interval(secs=>(e.value->>'timeInCallSecs')::double precision),c.mode,case when terms is null then 0 else ts_rank(to_tsvector('english',e.value->>'text'),terms) end
     from call_transcripts a join conversations c on c.id=a.conversation_id cross join lateral jsonb_array_elements(a.entries) e(value)
     where a.user_id=p_user and c.user_id=p_user and a.consent_version=p_version and a.expires_at>now() and c.expires_at>now()
     and (search is null or to_tsvector('english',e.value->>'text') @@ terms)
   ) all_turns order by relevance desc,at desc limit 60
  ) t;
 else turns:='[]'::jsonb; end if;
 return jsonb_build_object('memories',notes,'plans',plans,'recentConversation',turns,'privacyVersion',p_version,'bounded',true,'timezone',p.timezone,'now',now());
end $$;
revoke execute on function public.aira_shared_context(uuid,integer,text,uuid) from public,anon,authenticated;
grant execute on function public.aira_shared_context(uuid,integer,text,uuid) to service_role;

create function public.aira_conversation_action(p_user uuid,p_version integer,p_conversation uuid,p_action jsonb,p_binding text default null) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare p profiles; m memories; s schedules; action_kind text:=p_action->>'kind'; key text:=p_action->>'key'; label text; due timestamptz; action_state text:='saved'; begin
 select * into p from profiles where id=p_user and enabled for update;
 if not found or p.consent_version<>p_version then raise exception 'state_conflict'; end if;
 if not exists(select 1 from conversations where id=p_conversation and user_id=p_user and expires_at>now()) then raise exception 'forbidden'; end if;
 if p_binding is not null and not exists(select 1 from conversations where id=p_conversation and user_id=p_user and ended_at is null) then raise exception 'forbidden'; end if;
 if p_binding is not null and not exists(select 1 from realtime_sessions where conversation_id=p_conversation and user_id=p_user and call_binding=p_binding and consent_version=p_version and expires_at>now()) then raise exception 'forbidden'; end if;
 if action_kind not in ('memory','event','medication') or key is null or length(key) not between 1 and 100 or coalesce(length(p_action->>'sourceQuote'),0) not between 1 and 1000 then raise exception 'state_conflict'; end if;
 if action_kind='memory' then
  if not coalesce((p.consents->>'memory')::boolean,false) then return jsonb_build_object('kind',action_kind,'status','disabled'); end if;
  label:=p_action->>'text';
  if coalesce(length(label),0) not between 1 and 500 or p_action->>'category' not in ('preference','relationship','plan','other') then raise exception 'state_conflict'; end if;
  select * into m from memories where user_id=p_user and auto_key=key for update;
  if found then
   action_state:=case when m.text=label then 'already_saved' else 'updated' end;
   update memories set text=label,category=p_action->>'category',source_quote=p_action->>'sourceQuote',source_conversation=p_conversation,version=version+case when m.text=label then 0 else 1 end,expires_at='infinity' where id=m.id returning * into m;
  else
   insert into memories(user_id,text,category,auto_key,source_quote,source_conversation) values(p_user,label,p_action->>'category',key,p_action->>'sourceQuote',p_conversation) returning * into m;
  end if;
  return jsonb_build_object('kind',action_kind,'id',m.id,'label',m.text,'status',action_state);
 end if;
 if not coalesce((p.consents->>case when action_kind='medication' then 'medication_reminders' else 'social_reminders' end)::boolean,false) then return jsonb_build_object('kind',action_kind,'status','disabled'); end if;
 label:=p_action->>'label'; due:=(p_action->>'dueAt')::timestamptz;
 if coalesce(length(label),0) not between 1 and 300 or due is null or due<=now() or due>now()+interval '366 days' or coalesce(p_action->>'recurrence','once') not in ('once','daily') or (action_kind='event' and coalesce(p_action->>'recurrence','once')<>'once') then raise exception 'state_conflict'; end if;
 select * into s from schedules where user_id=p_user and schedules.kind=action_kind and auto_key=key for update;
 if found then
  if s.label=label and s.due_at=due and s.instructions=coalesce(p_action->>'instructions','') and s.recurrence=coalesce(p_action->>'recurrence','once') then action_state:='already_saved';
  else
   action_state:='updated';
   update schedules set label=p_action->>'label',due_at=due,instructions=coalesce(p_action->>'instructions',''),recurrence=coalesce(p_action->>'recurrence','once'),source_quote=p_action->>'sourceQuote',source_conversation=p_conversation,version=version+1,enabled=true,expires_at='infinity' where id=s.id returning * into s;
   update foreground_events set state='cancelled' where schedule_id=s.id and state in ('pending','snoozed');
  end if;
 else
  insert into schedules(user_id,kind,label,instructions,due_at,timezone,confirmed,recurrence,auto_key,source_quote,source_conversation)
   values(p_user,action_kind,label,coalesce(p_action->>'instructions',''),due,p.timezone,true,coalesce(p_action->>'recurrence','once'),key,p_action->>'sourceQuote',p_conversation) returning * into s;
 end if;
 return jsonb_build_object('kind',action_kind,'id',s.id,'label',s.label,'dueAt',s.due_at,'status',action_state);
end $$;
revoke execute on function public.aira_conversation_action(uuid,integer,uuid,jsonb,text) from public,anon,authenticated;
grant execute on function public.aira_conversation_action(uuid,integer,uuid,jsonb,text) to service_role;

create or replace function public.aira_schedule_edit(p_user uuid,p_id uuid,p_kind text,p_version integer,p_patch jsonb) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare s schedules; begin
 perform 1 from profiles where id=p_user and enabled and coalesce((consents->>case when p_kind='medication' then 'medication_reminders' else 'social_reminders' end)::boolean,false) for update;
 if not found then raise exception 'forbidden'; end if;
 select * into s from schedules where id=p_id and user_id=p_user and kind=p_kind and expires_at>now() for update;
 if not found or s.version<>p_version then raise exception 'state_conflict'; end if;
 if p_patch ? 'due_at' and ((p_patch->>'due_at')::timestamptz<=now() or (p_patch->>'due_at')::timestamptz>now()+interval '366 days') then raise exception 'state_conflict'; end if;
 update schedules set label=coalesce(p_patch->>'label',s.label),instructions=coalesce(p_patch->>'instructions',s.instructions),due_at=coalesce((p_patch->>'due_at')::timestamptz,s.due_at),
 recurrence=coalesce(p_patch->>'recurrence',s.recurrence),enabled=coalesce((p_patch->>'enabled')::boolean,s.enabled),version=s.version+1,expires_at='infinity' where id=p_id returning * into s;
 update foreground_events set state='cancelled' where schedule_id=p_id and state in ('pending','snoozed');
 return to_jsonb(s);
end $$;

create or replace function public.aira_worker_tick_core() returns jsonb
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
     values(job.user_id,job.id,job.version,'medication',job.label,least(job.expires_at,now()+interval '24 hours')) on conflict do nothing;
     if job.recurrence='daily' then
      update schedules set due_at=aira_next_daily_call((job.due_at at time zone job.timezone)::time,job.timezone,now()),version=version+1 where id=job.id;
     end if;
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


-- Deleting a transcript also revokes any already-loaded model context. The
-- archive is never re-created by a late provider sync or a stale native tool.
create or replace function public.aira_delete_call_transcript(p_user uuid,p_call uuid) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 delete from call_transcripts where conversation_id=p_call and user_id=p_user;
 if found then
  delete from messages where conversation_id=p_call and user_id=p_user;
  update conversations set expires_at=least(expires_at,now()+interval '24 hours') where id=p_call and user_id=p_user;
  update profiles set consent_version=consent_version+1 where id=p_user;
 end if;
 return true;
end $$;

-- Atomic merge prevents facial-context updates and caption checkpoints from
-- overwriting one another. The authenticated API supplies the allowlisted data.
create function public.aira_update_call_context(p_user uuid,p_call uuid,p_version integer,p_context jsonb) returns boolean
language plpgsql security definer set search_path=public,pg_temp as $$
begin
 perform 1 from profiles where id=p_user and enabled and consent_version=p_version for share;
 if not found or jsonb_typeof(p_context)<>'object' or octet_length(p_context::text)>60000 or exists(select 1 from jsonb_object_keys(p_context) k where k not in ('cueSummary','selfReportedFeeling','recentUserCaptions')) then return false; end if;
 update realtime_sessions s set context=s.context||p_context
 where s.conversation_id=p_call and s.user_id=p_user and s.consent_version=p_version and s.expires_at>now()
 and exists(select 1 from conversations c where c.id=p_call and c.user_id=p_user and c.ended_at is null and c.expires_at>now());
 return found;
end $$;
revoke execute on function public.aira_update_call_context(uuid,uuid,integer,jsonb) from public,anon,authenticated;
grant execute on function public.aira_update_call_context(uuid,uuid,integer,jsonb) to service_role;
