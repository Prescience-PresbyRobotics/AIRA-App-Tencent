-- Preserve a delivered, opted-in user message before model processing. This is
-- separate from reply approval: no unchecked assistant content is ever stored.
create function public.aira_save_message_input(p_user uuid,p_request uuid,p_input text,p_consent_version integer) returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare p profiles; r message_requests; begin
 select * into strict p from profiles where id=p_user and enabled for update;
 select * into strict r from message_requests where id=p_request and user_id=p_user and status='processing' for update;
 if p.consent_version <> p_consent_version then update message_requests set status='failed' where id=r.id; return false; end if;
 if coalesce((p.consents->>'conversation_storage')::boolean,false) then
  update conversations set expires_at='infinity' where id=r.conversation_id;
  update message_requests set expires_at='infinity' where id=r.id;
  insert into messages(user_id,request_id,conversation_id,role,text,approved,created_at,expires_at,context_version)
  values(p_user,r.id,r.conversation_id,'user',p_input,false,r.created_at,'infinity',p.consent_version)
  on conflict(request_id,role) do nothing;
 end if;
 return true;
end $$;
revoke execute on function public.aira_save_message_input(uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.aira_save_message_input(uuid,uuid,text,integer) to service_role;

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
    (p_user,r.id,r.conversation_id,'assistant',p_output,true,clock_timestamp(),'infinity',p.consent_version)
  on conflict(request_id,role) do nothing;
 end if;
 if (p.consents->>'impact')::boolean then update conversations set completed=true where id=r.conversation_id; end if;
 update message_requests set status='completed' where id=r.id;
 return true;
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
