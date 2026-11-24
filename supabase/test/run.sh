#!/usr/bin/env bash
# Teste supabase/schema.sql sur un PostgreSQL local jetable (imitation de Supabase).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -1)"
data="$(mktemp -d)"
chown postgres "$data"
port=54329
as_pg() { su postgres -s /bin/bash -c "$*"; }

as_pg "$bin/initdb -D $data -A trust -U postgres -E UTF8 --locale=C.UTF-8" >/dev/null
as_pg "$bin/pg_ctl -D $data -o '-p $port -k /tmp' -l $data/log -w start" >/dev/null
trap 'as_pg "$bin/pg_ctl -D $data -m fast stop" >/dev/null; rm -rf "$data"' EXIT

psql_() { psql -h /tmp -p $port -U postgres -d postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ -f "$here/emulate_supabase.sql"
psql_ -f "$here/../schema.sql"
psql_ -f "$here/../schema.sql"   # deuxième passage : le script doit pouvoir être relancé
psql_ -f "$here/test_security.sql"
