-- Display, profile-name and timezone edits do not revoke saved conversational context.
-- Effective privacy-consent changes and explicit memory/history deletion still do.
create or replace function public.aira_preferences(p_user uuid, p_patch jsonb) returns public.profiles
language plpgsql security definer set search_path = public, pg_temp as $$
declare old public.profiles; updated public.profiles; begin
 select * into strict old from profiles where id=p_user and enabled for update;
 update profiles set display_name=coalesce(p_patch->>'display_name',display_name),
 timezone=coalesce(p_patch->>'timezone',timezone), text_scale=coalesce((p_patch->>'text_scale')::numeric,text_scale),
 reduced_motion=coalesce((p_patch->>'reduced_motion')::boolean,reduced_motion), onboarded=coalesce((p_patch->>'onboarded')::boolean,onboarded),
 consents=consents || coalesce(p_patch->'consents','{}'::jsonb), consent_version=consent_version+case when (consents || coalesce(p_patch->'consents','{}'::jsonb)) is distinct from consents then 1 else 0 end
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
