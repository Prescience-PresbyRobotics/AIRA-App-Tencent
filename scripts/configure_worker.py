#!/usr/bin/env python3
"""Configure AIRA's existing worker without exposing or rotating provider keys.

Requires Supabase CLI 2.120+ and an authenticated, linked checkout. Infrastructure
secrets stay in ignored supabase/.env.infrastructure (0600); CLI output and SQL
errors are deliberately suppressed because they may contain secret values.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[1]
SECRET_NAMES = ("AIRA_WORKER_SECRET", "AIRA_SPEECH_SIGNING_SECRET")
ORIGINS = "AIRA_ALLOWED_ORIGINS"
LOCAL_NAMES = {*SECRET_NAMES, ORIGINS, "AIRA_INFRA_PROJECT_REF"}


class SetupError(Exception):
    pass


def origin(value):
    parsed = urlsplit(value)
    if (parsed.scheme not in ("http", "https") or not parsed.hostname
            or parsed.username or parsed.password or parsed.query or parsed.fragment
            or parsed.path not in ("", "/") or any(c.isspace() for c in value)
            or "," in value):
        raise argparse.ArgumentTypeError("Use an exact http(s) origin without a path.")
    return f"{parsed.scheme}://{parsed.netloc}"


def load_local(path, project_ref):
    values = {}
    if path.is_symlink():
        raise SetupError("Infrastructure secret file must not be a symbolic link.")
    if path.exists():
        for line in path.read_text().splitlines():
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            key, separator, value = line.partition("=")
            if not separator or key not in LOCAL_NAMES or key in values:
                raise SetupError("Infrastructure secret file has an invalid entry; values suppressed.")
            values[key] = value
        if values.get("AIRA_INFRA_PROJECT_REF") != project_ref:
            raise SetupError("Infrastructure secret file belongs to another project.")
    for name in SECRET_NAMES:
        if name in values and not re.fullmatch(r"[A-Za-z0-9_-]{32,}", values[name]):
            raise SetupError(f"{name} must be a high-entropy URL-safe value of at least 32 characters.")
    if ORIGINS in values:
        try:
            values[ORIGINS] = ",".join(origin(v) for v in values[ORIGINS].split(","))
        except (ValueError, argparse.ArgumentTypeError):
            raise SetupError("Infrastructure file contains an invalid allowed origin.") from None
    return values


def save_local(path, values):
    # Atomic replacement keeps a failed run retryable and never creates a world-readable file.
    fd, temporary = tempfile.mkstemp(prefix=".env.infrastructure-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write("# Private AIRA infrastructure only. Never commit or share.\n")
            for name in ("AIRA_INFRA_PROJECT_REF", *SECRET_NAMES, ORIGINS):
                if name in values:
                    stream.write(f"{name}={values[name]}\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class Supabase:
    def __init__(self, binary, project_ref):
        self.binary = binary
        self.project_ref = project_ref

    def run(self, arguments, stage):
        command = [self.binary, *arguments, "--project-ref", self.project_ref,
                   "--workdir", str(ROOT), "--agent", "no",
                   "--output-format", "text", "--output", "json", "--log-level", "error"]
        try:
            result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True,
                                    stdin=subprocess.DEVNULL, timeout=120)
        except (OSError, subprocess.TimeoutExpired):
            raise SetupError(f"{stage} could not complete; command details suppressed.") from None
        if result.returncode:
            raise SetupError(f"{stage} failed; CLI/SQL output suppressed to protect secrets.")
        return result.stdout

    def secret_digests(self):
        try:
            rows = json.loads(self.run(["secrets", "list"], "Secret metadata check"))
            if not isinstance(rows, list):
                raise ValueError()
            result = {}
            for row in rows:
                if row.get("name") in {*SECRET_NAMES, ORIGINS}:
                    digest = row.get("digest", row.get("value", ""))
                    if not isinstance(digest, str) or not re.fullmatch(r"[a-fA-F0-9]{64}", digest):
                        raise ValueError()
                    result[row["name"]] = digest.lower()
            return result
        except (ValueError, TypeError, AttributeError):
            raise SetupError("Cannot verify existing infrastructure secret digests; nothing overwritten.") from None

    def with_file(self, text, suffix, arguments, stage):
        fd, filename = tempfile.mkstemp(prefix="aira-worker-", suffix=suffix)
        try:
            with os.fdopen(fd, "w") as stream:
                os.fchmod(stream.fileno(), 0o600)
                stream.write(text)
            return self.run([*arguments, filename], stage)
        finally:
            os.unlink(filename)


def sha(value):
    return hashlib.sha256(value.encode()).hexdigest()


def sql_literal(value):
    return "'" + value.replace("'", "''") + "'"


def vault_guard(project_url, worker_secret):
    # This block is also run before uploading secrets, so an unrelated existing Vault
    # record cannot cause the script to replace a functioning worker credential.
    return f"""
do $aira_check$
declare secret_count integer; matches boolean;
begin
  if to_regprocedure('public.aira_worker_tick()') is null then
    raise exception 'Apply the AIRA database migration first';
  end if;
  if to_regclass('vault.decrypted_secrets') is not null then
    select count(*), bool_and(decrypted_secret = {sql_literal(project_url)})
      into secret_count, matches from vault.decrypted_secrets where name='aira_project_url';
    if secret_count > 1 or (secret_count=1 and matches is not true) then
      raise exception 'Existing AIRA Vault URL differs';
    end if;
    select count(*), bool_and(decrypted_secret = {sql_literal(worker_secret)})
      into secret_count, matches from vault.decrypted_secrets where name='aira_worker_secret';
    if secret_count > 1 or (secret_count=1 and matches is not true) then
      raise exception 'Existing AIRA Vault worker secret differs';
    end if;
  end if;
end $aira_check$;
"""


def worker_sql(project_url, worker_secret):
    return f"""begin;
create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;
create extension if not exists supabase_vault with schema vault;
{vault_guard(project_url, worker_secret)}
do $aira_vault$
begin
  if (select count(*) from cron.job where jobname='aira-worker-every-minute') > 1
    or exists(select 1 from cron.job where jobname='aira-worker-every-minute' and username<>current_user) then
    raise exception 'Existing AIRA worker job ownership differs';
  end if;
  if not exists(select 1 from vault.secrets where name='aira_project_url') then
    perform vault.create_secret({sql_literal(project_url)}, 'aira_project_url', 'AIRA worker project URL');
  end if;
  if not exists(select 1 from vault.secrets where name='aira_worker_secret') then
    perform vault.create_secret({sql_literal(worker_secret)}, 'aira_worker_secret', 'AIRA worker authentication');
  end if;
end $aira_vault$;
select cron.schedule('aira-worker-every-minute', '* * * * *', $aira_job$
  select net.http_post(
    url := (select decrypted_secret from vault.decrypted_secrets where name='aira_project_url')
      || '/functions/v1/aira-worker',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-aira-worker-secret', (select decrypted_secret from vault.decrypted_secrets where name='aira_worker_secret')),
    body := '{{}}'::jsonb,
    timeout_milliseconds := 10000
  );
$aira_job$);
commit;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project-ref", required=True)
    parser.add_argument("--supabase", default="supabase", help="Supabase CLI executable")
    parser.add_argument("--origin", action="append", type=origin, default=[],
                        help="Allowed browser origin to append (repeatable)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Validate local inputs and print the plan; no network or file changes")
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9]{20}", args.project_ref):
        raise SetupError("Use the 20-character Supabase project reference.")
    linked = ROOT / "supabase/.temp/project-ref"
    if not linked.exists() or linked.read_text().strip() != args.project_ref:
        raise SetupError("Linked project does not match --project-ref; link this checkout first.")
    path = ROOT / "supabase/.env.infrastructure"
    local = load_local(path, args.project_ref)
    if args.dry_run:
        print("Local project identity is valid. No files or cloud settings changed.")
        print("Plan: preserve existing infrastructure secrets, append requested origins, "
              "configure Vault and one named minute-based worker job. Provider keys are untouched.")
        return
    cli = Supabase(args.supabase, args.project_ref)
    remote = cli.secret_digests()
    values = {**local, "AIRA_INFRA_PROJECT_REF": args.project_ref}
    for name in SECRET_NAMES:
        if name in remote and (name not in local or remote[name] != sha(local[name])):
            raise SetupError(f"Existing {name} cannot be matched to the local copy; refusing to rotate it.")
        values.setdefault(name, secrets.token_urlsafe(48))
    previous_origins = local.get(ORIGINS, "")
    allowed = list(dict.fromkeys([*filter(None, previous_origins.split(",")), *args.origin]))
    if not allowed:
        allowed = ["http://localhost:8080"]
    values[ORIGINS] = ",".join(allowed)
    if ORIGINS in remote and remote[ORIGINS] not in {sha(previous_origins), sha(values[ORIGINS])}:
        raise SetupError("Existing allowed origins do not match the local configuration; refusing to replace them.")
    project_url = f"https://{args.project_ref}.supabase.co"
    cli.with_file(vault_guard(project_url, values[SECRET_NAMES[0]]), ".sql",
                  ["db", "query", "--linked", "--file"], "Existing Vault configuration check")
    # Preserve generated credentials before any upload, even if the following call fails.
    saved = {**values}
    if previous_origins:
        saved[ORIGINS] = previous_origins
    save_local(path, saved)
    pending = {name: values[name] for name in (*SECRET_NAMES, ORIGINS)
               if remote.get(name) != sha(values[name])}
    if pending:
        cli.with_file("".join(f"{name}={value}\n" for name, value in pending.items()),
                      ".env", ["secrets", "set", "--env-file"], "Infrastructure secret upload")
    save_local(path, values)
    cli.with_file(worker_sql(project_url, values[SECRET_NAMES[0]]), ".sql",
                  ["db", "query", "--linked", "--file"], "Worker schedule configuration")
    print("AIRA infrastructure secrets and the minute-based worker schedule are configured.")
    print("Provider keys were untouched. Private local credentials: supabase/.env.infrastructure")


if __name__ == "__main__":
    try:
        main()
    except (SetupError, OSError) as error:
        # Raw OS errors may include filenames; never print unexpected exception contents.
        print(f"Setup stopped: {error}" if isinstance(error, SetupError)
              else "Setup stopped: local file access failed; details suppressed.", file=sys.stderr)
        sys.exit(1)
    except KeyboardInterrupt:
        print("Setup interrupted; any saved infrastructure credentials were preserved.", file=sys.stderr)
        sys.exit(130)
