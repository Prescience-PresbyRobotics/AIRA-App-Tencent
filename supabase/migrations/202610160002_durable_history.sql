-- The user requested WhatsApp-style history on 16 October 2026. Saved chats
-- remain until explicitly deleted or storage is disabled. Other prototype data
-- keeps its existing expiry. Previously deleted/expired content is not restored.
alter table public.messages add column history_order bigint generated always as identity;
alter table public.messages add column context_version integer not null default 0;
create unique index messages_history_order on public.messages(history_order);
create index messages_owner_history on public.messages(user_id,history_order desc);
create index messages_owner_context on public.messages(user_id,conversation_id,context_version,history_order desc);
create index message_requests_owner_created on public.message_requests(user_id,created_at desc);
create index conversations_owner_accepted on public.conversations(user_id,accepted_at desc);

-- Preserve only still-valid transcripts for owners who already opted in.
update public.messages m set expires_at='infinity',context_version=p.consent_version
from public.profiles p,public.conversations c,public.message_requests r
where m.user_id=p.id and p.enabled and (p.consents->>'conversation_storage')::boolean
and c.id=m.conversation_id and r.id=m.request_id
and m.expires_at>now() and c.expires_at>now() and r.expires_at>now();
update public.message_requests r set expires_at='infinity'
where exists(select 1 from public.messages m where m.request_id=r.id and m.expires_at='infinity');
update public.conversations c set expires_at='infinity'
where exists(select 1 from public.messages m where m.conversation_id=c.id and m.expires_at='infinity');

create or replace function public.aira_finish_message(p_user uuid,p_request uuid,p_input text,p_output text,p_consent_version integer) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; r message_requests; begin
 select * into strict p from profiles where id=p_user and enabled for update;
 select * into strict r from message_requests where id=p_request and user_id=p_user and status='processing' for update;
 if p.consent_version <> p_consent_version then update message_requests set status='failed' where id=r.id; return false; end if;
 if (p.consents->>'conversation_storage')::boolean then
  update conversations set expires_at='infinity' where id=r.conversation_id;
  update message_requests set expires_at='infinity' where id=r.id;
  insert into messages(user_id,request_id,conversation_id,role,text,approved,created_at,expires_at,context_version) values
    (p_user,r.id,r.conversation_id,'user',p_input,false,r.created_at,'infinity',p.consent_version),
    (p_user,r.id,r.conversation_id,'assistant',p_output,true,clock_timestamp(),'infinity',p.consent_version);
 end if;
 if (p.consents->>'impact')::boolean then update conversations set completed=true where id=r.conversation_id; end if;
 update message_requests set status='completed' where id=r.id;
 return true;
end $$;

-- The existing preferences RPC removes message text on opt-out. Also bound the
-- remaining request/conversation metadata so opt-out cannot retain it forever.
create function public.aira_history_opt_out() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
 if not coalesce((new.consents->>'conversation_storage')::boolean,false) then
  update conversations set expires_at=least(expires_at,now()+interval '24 hours') where user_id=new.id;
  update message_requests set expires_at=least(expires_at,now()+interval '24 hours') where user_id=new.id;
 end if;
 return new;
end $$;
create trigger aira_history_opt_out after update of consents on public.profiles
for each row execute function public.aira_history_opt_out();
revoke execute on function public.aira_history_opt_out() from public,anon,authenticated;

-- A server-only RPC owns pagination and the consent check in one transaction.
-- The cursor is an exclusive sequence number, so equal timestamps and newly
-- arriving messages cannot skip/duplicate older pages.
create function public.aira_chat_history(p_user uuid,p_before bigint default null,p_limit integer default 50) returns jsonb
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
   'order',m.history_order::text,'contextVersion',m.context_version
  ) row
  from messages m join message_requests r on r.id=m.request_id and r.user_id=p_user
  join conversations c on c.id=m.conversation_id and c.user_id=p_user
  where m.user_id=p_user and m.expires_at>now() and r.expires_at>now() and c.expires_at>now()
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
revoke execute on function public.aira_chat_history(uuid,bigint,integer) from public,anon,authenticated;
grant execute on function public.aira_chat_history(uuid,bigint,integer) to service_role;

create function public.aira_clear_chat_history(p_user uuid) returns integer
language plpgsql security definer set search_path = public, pg_temp as $$
declare v integer; begin
 perform 1 from profiles where id=p_user and enabled for update;
 if not found then raise exception 'forbidden'; end if;
 delete from conversations where user_id=p_user;
 update profiles set consent_version=consent_version+1 where id=p_user returning consent_version into v;
 insert into audit_events(actor_id,subject_id,action) values(p_user,p_user,'chat_history_deleted');
 return v;
end $$;
revoke execute on function public.aira_clear_chat_history(uuid) from public,anon,authenticated;
grant execute on function public.aira_clear_chat_history(uuid) to service_role;

-- Forgetting a memory clears its future model context, not the user's visible
-- chat archive. Every saved turn carries its original privacy version; the API
-- and client omit older versions from model input after this increment.
create or replace function public.aira_memory_edit(p_user uuid,p_id uuid,p_version integer,p_text text) returns integer
language plpgsql security definer set search_path = public,pg_temp as $$
declare v integer; begin
 perform 1 from profiles where id=p_user and enabled and (consents->>'memory')::boolean for update;
 if not found then raise exception 'forbidden'; end if;
 if p_text is null then delete from memories where id=p_id and user_id=p_user;
 else
  update memories set text=p_text,version=version+1 where id=p_id and user_id=p_user and version=p_version and expires_at>now();
  if not found then raise exception 'state_conflict'; end if;
 end if;
 update profiles set consent_version=consent_version+1 where id=p_user returning consent_version into v;
 return v;
end $$;
