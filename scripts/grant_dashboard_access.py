#!/usr/bin/env python3
"""Provision explicitly authorized care access for two existing AIRA accounts.

Default mode reads identities and prints the exact plan. --apply atomically grants
operator counts plus reviewer/insights access for one senior and a verified,
test-only caregiver link. It never creates accounts, resets passwords, sends mail,
changes senior preferences, or grants access through user-editable metadata.
Requires an authenticated Supabase CLI linked to this checkout's project.
"""

import argparse
import json
from pathlib import Path
import re
import sys

from configure_worker import Supabase, SetupError, sql_literal

ROOT = Path(__file__).resolve().parents[1]
SCOPES = ("loneliness", "conversations", "mood", "urgent", "reviewed")


def email(value):
    value = value.strip().lower()
    if len(value) > 254 or not re.fullmatch(r"[a-z0-9.!#$%&*+/=?^_`{|}~-]+@[a-z0-9.-]+\.[a-z]{2,}", value):
        raise argparse.ArgumentTypeError("Use the existing account's exact email address.")
    return value


def inspect_sql(admin, senior):
    a, s = sql_literal(admin), sql_literal(senior)
    return f"""
select jsonb_build_object(
  'accounts', coalesce((select jsonb_agg(jsonb_build_object(
    'email',lower(u.email),'emailConfirmed',u.email_confirmed_at is not null,
    'profileExists',p.id is not null,'profileEnabled',coalesce(p.enabled,false),
    'banned',coalesce(u.banned_until>now(),false)))
    from auth.users u left join public.profiles p on p.id=u.id
    where lower(u.email) in ({a},{s})), '[]'::jsonb),
  'roles', coalesce((select jsonb_agg(jsonb_build_object('role',r.role,
    'subject',case when r.subject_id is null then 'global_counts'
      when r.subject_id=(select id from auth.users where lower(email)={s})
      then 'requested_senior' else 'other_senior' end,'enabled',r.enabled))
    from public.role_assignments r join auth.users u on u.id=r.user_id
    where lower(u.email)={a}), '[]'::jsonb),
  'caregiverLinks', coalesce((select jsonb_agg(jsonb_build_object(
    'verified',l.verified,'testOnly',l.test_recipient,
    'revoked',l.revoked_at is not null,'scopes',l.scopes))
    from public.caregiver_links l
    join auth.users a on a.id=l.caregiver_id join auth.users s on s.id=l.senior_id
    where lower(a.email)={a} and lower(s.email)={s}), '[]'::jsonb),
  'seniorChoices', (select jsonb_build_object(
    'adminInsights',p.consents->'admin_insights','impact',p.consents->'impact',
    'moodHistory',p.consents->'mood_history','monitoring',p.consents->'monitoring',
    'urgentSharing',p.consents->'urgent_sharing','reviewedSharing',p.consents->'reviewed_sharing')
    from public.profiles p join auth.users u on u.id=p.id where lower(u.email)={s}),
  'directClientCannotGrantRoles',not has_table_privilege('authenticated','public.role_assignments','INSERT')
    and not has_table_privilege('authenticated','public.role_assignments','UPDATE'),
  'directClientCannotVerifyCaregiver',not has_table_privilege('authenticated','public.caregiver_links','INSERT')
    and not has_table_privilege('authenticated','public.caregiver_links','UPDATE')
) as access;
"""


def grant_sql(admin, senior):
    a, s = sql_literal(admin), sql_literal(senior)
    scopes = "array[" + ",".join(sql_literal(scope) for scope in SCOPES) + "]"
    return f"""begin;
do $aira_access$
declare principal uuid; subject uuid;
begin
  perform pg_advisory_xact_lock(hashtextextended('aira-dashboard:' || {a} || ':' || {s},0));
  if (select count(*) from auth.users where lower(email)={a})<>1
    or (select count(*) from auth.users where lower(email)={s})<>1 then
    raise exception 'Both exact existing account identities are required';
  end if;
  select id into principal from auth.users where lower(email)={a};
  select id into subject from auth.users where lower(email)={s};
  if principal=subject then raise exception 'Use separate staff and senior accounts'; end if;
  if exists(select 1 from auth.users where id in (principal,subject)
    and (email_confirmed_at is null or banned_until>now())) then
    raise exception 'Both accounts must have confirmed emails and be available';
  end if;
  if (select count(*) from public.profiles where id in(principal,subject) and enabled)<>2 then
    raise exception 'Both enabled app profiles must already exist';
  end if;
  insert into public.role_assignments(user_id,role,subject_id,enabled)
    values(principal,'operator',null,true),(principal,'reviewer',subject,true),(principal,'insights',subject,true)
    on conflict(user_id,role,subject_id) do update set enabled=true;
  insert into public.caregiver_links(senior_id,caregiver_id,verified,test_recipient,scopes,revoked_at)
    values(subject,principal,true,true,{scopes},null)
    on conflict(senior_id,caregiver_id) do update set verified=true,test_recipient=true,
      scopes=excluded.scopes,revoked_at=null;
  insert into public.audit_events(actor_id,subject_id,action,detail)
    values(null,subject,'trusted_dashboard_access_granted',jsonb_build_object(
      'principal_id',principal,'source','explicit_project_owner_request',
      'operator_scope','counts_only','reviewer_scope','this_subject',
      'insights_scope','this_subject','caregiver_scopes',{scopes},
      'external_delivery',false,'senior_consents_changed',false));
end $aira_access$;
commit;
"""


def inspect(cli, admin, senior):
    try:
        rows = json.loads(cli.with_file(inspect_sql(admin, senior), ".sql",
            ["db", "query", "--linked", "--file"], "Dashboard identity/access inspection"))
        if not isinstance(rows, list) or len(rows) != 1 or not isinstance(rows[0].get("access"), dict):
            raise ValueError()
        return rows[0]["access"]
    except (ValueError, KeyError, TypeError):
        raise SetupError("Unexpected dashboard-access response; details suppressed.") from None


def validate_identities(state, admin, senior):
    rows = state.get("accounts", [])
    for address in (admin, senior):
        matches = [row for row in rows if row.get("email") == address]
        if len(matches) != 1:
            raise SetupError(f"Existing account not found uniquely: {address}. No account was created.")
        row = matches[0]
        if not row.get("emailConfirmed") or row.get("banned") or not row.get("profileExists") or not row.get("profileEnabled"):
            raise SetupError(f"Account is not confirmed and ready: {address}. No password or profile was changed.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--supabase", default="supabase")
    parser.add_argument("--admin-email", type=email, required=True)
    parser.add_argument("--senior-email", type=email, required=True)
    parser.add_argument("--apply", action="store_true", help="Apply the explicitly authorized roles/link")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9]{20}", args.project_ref):
        raise SetupError("Invalid Supabase project reference.")
    linked = ROOT / "supabase/.temp/project-ref"
    if not linked.exists() or linked.read_text().strip() != args.project_ref:
        raise SetupError("The checkout's linked project differs; nothing changed.")
    if args.admin_email == args.senior_email:
        raise SetupError("Use separate staff and senior accounts.")
    cli = Supabase(args.supabase, args.project_ref)
    before = inspect(cli, args.admin_email, args.senior_email)
    validate_identities(before, args.admin_email, args.senior_email)
    print(json.dumps({"mode": "apply" if args.apply else "plan",
        "staffLogin": args.admin_email, "senior": args.senior_email,
        "grant": ["operator: global counts only", "reviewer: requested senior only", "insights: requested senior only"],
        "verifiedCaregiverScopes": SCOPES, "externalDelivery": False,
        "seniorChoices": before["seniorChoices"],
        "accountOrPasswordChanges": False}, indent=2), flush=True)
    if not args.apply:
        print("Plan only. Add --apply only after the account owner authorizes these exact roles and sharing scopes.")
        return
    cli.with_file(grant_sql(args.admin_email, args.senior_email), ".sql",
        ["db", "query", "--linked", "--file"], "Authorized dashboard access grant")
    after = inspect(cli, args.admin_email, args.senior_email)
    expected = {("operator", "global_counts"), ("reviewer", "requested_senior"), ("insights", "requested_senior")}
    actual = {(row["role"], row["subject"]) for row in after["roles"] if row["enabled"]}
    links = after["caregiverLinks"]
    if not expected.issubset(actual) or len(links) != 1 or not all((
        links[0]["verified"], links[0]["testOnly"], not links[0]["revoked"],
        set(links[0]["scopes"]) == set(SCOPES),
        after["seniorChoices"] == before["seniorChoices"],
        after["directClientCannotGrantRoles"], after["directClientCannotVerifyCaregiver"],
    )):
        raise SetupError("Grant verification needs review; do not assume complete access.")
    print("PASS: exact roles/link read back; senior choices unchanged; direct clients cannot self-grant access.")
    if any(subject == "other_senior" for _, subject in actual):
        print("Existing assignments to other seniors were preserved; this operation did not create them.")
    if not after["seniorChoices"].get("adminInsights"):
        print("Admin insight detail remains blocked until the senior enables Admin insights in Settings → Privacy.")
    print("Sign in with the existing staff email/password. Open Settings → Care connections → Admin dashboard or Caregiver view.")


if __name__ == "__main__":
    try:
        main()
    except SetupError as error:
        print(f"Dashboard access setup stopped: {error}", file=sys.stderr)
        sys.exit(1)
    except Exception:
        print("Dashboard access setup stopped: unexpected error; private details suppressed.", file=sys.stderr)
        sys.exit(1)
