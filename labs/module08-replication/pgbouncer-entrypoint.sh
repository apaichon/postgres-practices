#!/bin/sh
set -eu
umask 077
mkdir -p /tmp/m8-pgbouncer
printf '"postgres" "%s"\n"claim_app" "%s"\n' \
  "$M8_ADMIN_PASSWORD" "$M8_APP_PASSWORD" > /tmp/m8-pgbouncer/users.txt
exec /usr/bin/pgbouncer /lab/config/pgbouncer.ini
