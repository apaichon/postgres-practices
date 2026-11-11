#!/usr/bin/env bash
set -Eeuo pipefail
# This runs only for the first initialization of pg1.
psql -X -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=repl_password="$M8_REPLICATION_PASSWORD" <<'SQL'
CREATE ROLE replicator WITH LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE
  PASSWORD :'repl_password';
CREATE SCHEMA claimsure;
CREATE SCHEMA lab_m8;
CREATE TABLE lab_m8.environment (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  purpose text NOT NULL CHECK (purpose = 'isolated-module08-docker')
);
INSERT INTO lab_m8.environment VALUES (true, 'isolated-module08-docker');
SQL
