#!/usr/bin/env python3
"""Internal, guarded file cleanup for run-lab07.sh cleanup."""
import os
from pathlib import Path
import shutil
import sys

mode, work_arg, backup_arg, sid = sys.argv[1:]
home = Path.home().resolve()
work, backups = Path(work_arg), Path(backup_arg)


def check_path(path):
    if not path.is_absolute() or path == home or home not in path.parents:
        raise SystemExit(f'Refusing cleanup outside a dedicated directory under {home}: {path}')
    for part in (path, *path.parents):
        if part == home:
            break
        if part.is_symlink():
            raise SystemExit(f'Refusing symlink in cleanup path: {part}')
    if path.exists() and (not path.is_dir() or path.stat().st_uid != os.getuid()):
        raise SystemExit(f'Refusing directory not owned by this student: {path}')


for path in (work, backups):
    check_path(path)
# The backup directory has historically had no ownership marker. Restrict its
# cleanup to the reserved course location, never an arbitrary M7_BACKUP_DIR.
if backups != home / 'backups/module07':
    raise SystemExit('Cleanup requires M7_BACKUP_DIR=$HOME/backups/module07; custom backup destinations must be cleaned separately.')
if work == backups or work in backups.parents or backups in work.parents:
    raise SystemExit('Refusing overlapping sandbox and backup directories')
protected = [home / name for name in ('scripts', '.env', '.pgpass', '.pg_service.conf')]
for path in (work, backups):
    if any(path == item or path in item.parents or item in path.parents for item in protected):
        raise SystemExit(f'Refusing cleanup of a protected student path: {path}')
if work.exists():
    marker = work / '.module07'
    if marker.is_symlink() or not marker.is_file() or marker.read_text().strip() != f'{os.getuid()}:{sid}':
        raise SystemExit(f'Refusing sandbox without the matching Module 7 student marker: {work}')

clusters = []
if work.exists():
    recovery = work / 'recovery'
    if recovery.is_symlink():
        raise SystemExit(f'Refusing symlink recovery directory: {recovery}')
    candidates = [work / 'primary']
    if recovery.is_dir():
        candidates.extend(recovery.iterdir())
    for cluster in candidates:
        if cluster.is_symlink():
            raise SystemExit(f'Refusing symlink cluster: {cluster}')
        version = cluster / 'PG_VERSION'
        if version.exists():
            if version.is_symlink() or version.read_text().strip() != '18':
                raise SystemExit(f'Refusing unexpected PostgreSQL cluster: {cluster}')
            clusters.append(cluster)

# Reject unknown PID files before any SQL or server stop is attempted.
known_pids = {cluster / 'postmaster.pid' for cluster in clusters}
for path in (work, backups):
    if path.exists():
        for pid in path.rglob('postmaster.pid'):
            if pid not in known_pids:
                raise SystemExit(f'Refusing cleanup: unexpected postmaster.pid at {pid}')

if mode == 'clusters':
    for cluster in clusters:
        print(cluster)
elif mode == 'validate':
    for path in (work, backups):
        print(f'Module 7 files: {path}' + ('' if path.exists() else ' (already absent)'))
elif mode == 'remove':
    # pg_ctl must have stopped every known cluster before directory removal.
    for cluster in clusters:
        if (cluster / 'postmaster.pid').exists():
            raise SystemExit(f'Refusing deletion while postmaster.pid exists: {cluster}; stop the cluster first')
    # Fail closed for an unexpected running/recovered cluster anywhere in scope.
    for path in (work, backups):
        if path.exists() and next(path.rglob('postmaster.pid'), None) is not None:
            raise SystemExit(f'Refusing deletion: unexpected postmaster.pid under {path}')
    for path in (work, backups):
        if path.exists():
            shutil.rmtree(path)
            print(f'Removed {path}')
else:
    raise SystemExit('Unknown cleanup mode')
