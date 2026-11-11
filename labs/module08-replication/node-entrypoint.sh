#!/usr/bin/env bash
# Clone an empty standby once; subsequent starts reuse its data.
set -Eeuo pipefail
root=/var/lib/postgresql
[[ ${PGDATA:-} == "$root/18/docker" ]] || { echo 'Unexpected PGDATA.' >&2; exit 1; }
[[ ${M8_NODE:-} =~ ^(primary|replica|replica2|subscriber)$ ]] || exit 1
[[ ${M8_REPLICATION_PASSWORD:-} =~ ^[a-zA-Z0-9_-]{16,}$ ]] || exit 1
exec 9>"$root/.m8-node.lock"
flock -n 9 || { echo 'Node volume is in use.' >&2; exit 1; }
marker=$root/.m8-managed-node
if [[ -f "$marker" ]]; then
  [[ $(cat "$marker") == "$M8_NODE" ]] || { echo 'Volume belongs to another node.' >&2; exit 1; }
elif [[ -f "$PGDATA/PG_VERSION" ]]; then
  echo 'Unmarked existing data; refusing to adopt it.' >&2; exit 1
else
  printf '%s\n' "$M8_NODE" > "$marker"
fi
printf 'primary:5432:*:replicator:%s\n' "$M8_REPLICATION_PASSWORD" > "$root/replication.pgpass"
chmod 600 "$root/replication.pgpass"
chown postgres:postgres "$root/replication.pgpass"
case "$M8_NODE" in
  primary|subscriber)
    [[ ! -f "$PGDATA/standby.signal" ]] || { echo 'Unexpected standby; follow the failover runbook.' >&2; exit 1; }
    if [[ ! -f "$PGDATA/PG_VERSION" && $M8_NODE == primary ]]; then
      mkdir -p /docker-entrypoint-initdb.d
      cp /lab/init/01-replication.sh /docker-entrypoint-initdb.d/01-replication.sh
      chmod 644 /docker-entrypoint-initdb.d/01-replication.sh
    fi
    ;;
  replica|replica2)
    if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
      [[ ! -d "$PGDATA" || -z $(find "$PGDATA" -mindepth 1 -maxdepth 1 -print -quit) ]] || {
        echo 'Standby data is incomplete; inspect this volume before retrying.' >&2; exit 1;
      }
      slot="${M8_NODE}_slot"
      PGPASSWORD="$POSTGRES_PASSWORD" psql -XAt -h primary -U postgres -d claimsure \
        -v ON_ERROR_STOP=1 -c "SELECT pg_create_physical_replication_slot('$slot') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='$slot');"
      mkdir -p "$PGDATA"
      chmod 700 "$PGDATA"
      chown postgres:postgres "$PGDATA"
      gosu postgres pg_basebackup \
        --dbname="host=primary port=5432 user=replicator application_name=$M8_NODE passfile=$root/replication.pgpass connect_timeout=5" \
        --pgdata="$PGDATA" --write-recovery-conf --wal-method=stream \
        --slot="$slot" --checkpoint=fast
    fi
    [[ -f "$PGDATA/standby.signal" ]] || {
      echo 'This node was promoted; do not restart the original topology.' >&2; exit 1;
    }
    ;;
esac
exec /usr/local/bin/docker-entrypoint.sh postgres \
  -c config_file=/lab/config/postgresql.conf -c "cluster_name=m8_$M8_NODE"
