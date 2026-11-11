#!/usr/bin/env python3
"""Run the source Module 5 SQL sections in a dedicated architecture_m5 database."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

LAB = Path(__file__).resolve().parent
SOURCE = LAB / '05-architecture.sql'


def sections():
    text = SOURCE.read_text()
    marks = list(re.finditer(r"^\\echo '\\n-- Lab (5[A-G](?:\.[1-5])?): (.+)$", text, re.M))
    if len(marks) != 12:
        raise RuntimeError('Expected all 12 source lab sections.')
    preflight = text[:marks[0].start()]
    blocks = {match[1]: text[match.start():marks[i + 1].start() if i + 1 < len(marks) else len(text)]
              for i, match in enumerate(marks)}
    return preflight, blocks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('lab', nargs='?', default='list')
    args = parser.parse_args()
    preflight, blocks = sections()
    if args.lab == 'list':
        print('Lab 5: ' + ', '.join(blocks) + ', 5E-A, 5E-B, setup, all')
        print('make lab5 LAB_NO=5C     Run one complete source section')
        print('make lab5 LAB_NO=5E-A   Terminal A: wait for B at the prompt')
        print('make lab5 LAB_NO=5E-B   Terminal B: commit, then return to A')
        print('all runs the source file; run 5E-A/B separately for the two-session exercise.')
        return
    if args.lab not in (*blocks, 'setup', 'all', '5E-A', '5E-B'):
        parser.error('Unknown lab; run make lab5 LAB_NO=list')
    if not re.fullmatch(r'architecture_m5_(0[1-9]|1[0-9]|20)', os.environ.get('PGDATABASE', '')):
        raise RuntimeError('Set PGDATABASE=architecture_m5_xx with your assigned number 01–20.')
    if not os.environ.get('PGHOST') or not os.environ.get('PGPORT'):
        raise RuntimeError('Set PGHOST and PGPORT to the instructor-provided direct PostgreSQL endpoint.')
    command = ['psql', '-X', '-v', 'ON_ERROR_STOP=1']
    if args.lab in ('setup', 'all', '5E-A', '5E-B'):
        name = {'setup': '00-setup.sql', 'all': SOURCE.name,
                '5E-A': '05-mvcc-session-a.sql', '5E-B': '05-mvcc-session-b.sql'}[args.lab]
        subprocess.run([*command, '-f', str(LAB / name)], check=True)
    else:
        # A file supports both psql meta-commands and SQL while keeping stdin
        # connected to the terminal for the password prompt.
        with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', encoding='utf-8') as script:
            script.write(preflight + blocks[args.lab])
            script.flush()
            subprocess.run([*command, '-f', script.name], check=True)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        print('ERROR: ' + str(error), file=sys.stderr)
        sys.exit(1)
