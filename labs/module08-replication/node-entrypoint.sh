#!/usr/bin/env bash
# Infrastructure only: start a node, or seed a stopped node with pg_basebackup.
# Credentials go in a 0600 passfile; never into primary_conninfo or log output.
set -Eeuo pipefail
root=/var/lib/postgresql
expected_pgdata=$root/18/docker
[[ ${PGDATA:-} == "$expected_pgdata" ]] || { echo 'Unexpected PGDATA; refusing operation.' >&2; exit 1; }
[[ ${M8_NODE:-} =~ ^pg[123]$ ]] || { echo 'M8_NODE must be pg1, pg2 or pg3.' >&2; exit 1; }
[[ ${M8_REPLICATION_PASSWORD:-} =~ ^[a-zA-Z0-9_-]{16,}$ ]] || {
  echo 'Use a replication secret of at least 16 letters/digits/underscores/hyphens (random hex recommended).' >&2; exit 1;
}

# The lock covers the running server too: a second container cannot rebuild its volume.
# Alpine ships BusyBox flock, which has no --no-fork option. Hold the lock on
# an inherited descriptor so postgres remains PID 1 and receives stop signals.
exec 9>"$root/.m8-node.lock"
flock -n 9 || { echo 'Node volume is in use; stop the node before cloning/rebuilding.' >&2; exit 1; }
marker=$root/.m8-managed-node
if [[ -f "$marker" ]]; then
  [[ $(cat "$marker") == "$M8_NODE" ]] || { echo 'Volume belongs to another node.' >&2; exit 1; }
elif [[ -e "$PGDATA/PG_VERSION" ]]; then
  echo 'Unmarked PostgreSQL data; refusing to adopt this volume.' >&2; exit 1
else
  printf '%s\n' "$M8_NODE" > "$marker"
fi
printf '*:5432:replication:replicator:%s\n*:5432:claimsure_m8:replicator:%s\n' \
  "$M8_REPLICATION_PASSWORD" "$M8_REPLICATION_PASSWORD" > "$root/replication.pgpass"
chmod 600 "$root/replication.pgpass"
chown postgres:postgres "$root/replication.pgpass"

case ${1:-postgres} in
  postgres)
    if [[ ! -f "$PGDATA/PG_VERSION" && ${M8_BOOTSTRAP:-false} != true ]]; then
      echo "Seed $M8_NODE first: docker compose run --rm --no-deps $M8_NODE clone <primary-node>" >&2
      exit 1
    fi
    if [[ ! -f "$PGDATA/PG_VERSION" ]]; then
      # Copy off the host bind mount: Docker Desktop FUSE can report a .sh
      # executable to postgres even when its host mode is 0644, then deny exec.
      mkdir -p /docker-entrypoint-initdb.d
      cp /lab/init/*.sh /docker-entrypoint-initdb.d/
      chmod 644 /docker-entrypoint-initdb.d/*.sh
    fi
    # Existing data decides its role. In particular, restarting promoted pg2 keeps it primary.
    exec /usr/local/bin/docker-entrypoint.sh postgres \
      -c config_file=/lab/config/postgresql.conf -c "cluster_name=m8_$M8_NODE"
    ;;
  clone|rebuild)
    mode=$1
    upstream=${2:-}
    [[ $upstream =~ ^pg[123]$ && $upstream != "$M8_NODE" ]] || {
      echo 'Specify another node in this private Compose network.' >&2; exit 1;
    }
    conn="host=$upstream port=5432 user=replicator application_name=$M8_NODE passfile=$root/replication.pgpass connect_timeout=5"
    is_standby=$(gosu postgres psql "$conn dbname=claimsure_m8" -XAtv ON_ERROR_STOP=1 -c 'SELECT pg_is_in_recovery()')
    [[ $is_standby == f ]] || { echo 'Source is not a writable primary.' >&2; exit 1; }
    slot="m8_$M8_NODE"
    slot_ready=$(gosu postgres psql "$conn dbname=claimsure_m8" -XAtv ON_ERROR_STOP=1 \
      -c "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$slot' AND slot_type='physical' AND NOT active")
    [[ $slot_ready == 1 ]] || { echo "Create the inactive physical slot $slot on $upstream first." >&2; exit 1; }
    if [[ $mode == rebuild ]]; then
      [[ ${M8_REBUILD_CONFIRM:-} == "$M8_NODE" && -f "$PGDATA/PG_VERSION" ]] || {
        echo "Rebuild needs existing lab data and M8_REBUILD_CONFIRM=$M8_NODE." >&2; exit 1;
      }
      previous="$PGDATA.before-rebuild.$(date -u +%Y%m%dT%H%M%S).$$"
      mv "$PGDATA" "$previous"
      echo "Preserved old data inside this node volume: $previous"
    elif [[ -d "$PGDATA" && -n $(find "$PGDATA" -mindepth 1 -maxdepth 1 -print -quit) ]]; then
      echo 'Clone target is not empty. Use the documented stopped-node rebuild procedure.' >&2; exit 1
    fi
    mkdir -p "$PGDATA"
    chmod 700 "$PGDATA"
    chown postgres:postgres "$PGDATA"
    # -R writes standby.signal + primary_conninfo/primary_slot_name.
    # -X stream includes backup WAL; -S uses the slot explicitly created by the learner.
    gosu postgres pg_basebackup --dbname="$conn" --pgdata="$PGDATA" \
      --write-recovery-conf --wal-method=stream --slot="$slot" --checkpoint=fast --progress
    echo "Seeded $M8_NODE from $upstream. Start it explicitly with docker compose up -d $M8_NODE."
    ;;
  *) echo 'Use postgres, clone <primary-node>, or rebuild <primary-node>.' >&2; exit 1 ;;
esac
