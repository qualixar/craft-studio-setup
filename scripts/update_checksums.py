#!/usr/bin/env python3
"""Regenerate every checksum this repository publishes. Run before tagging.

1. Embed the SHA-256 of each file the bootstrapper runs into install.sh.
2. Write the SHA-256 of the resulting install.sh into README.md and the
   current release notes (between the INSTALL-SH-SHA256 markers).
3. Write SHA256SUMS for every tracked file (except SHA256SUMS itself).

`--check` changes nothing and exits 1 if any of the three is stale.
"""
import argparse
import hashlib
from pathlib import Path
import re
import subprocess
import sys

REPO = Path(__file__).resolve().parents[1]
BOOTSTRAP_FILES = (
    'catalog/apps.json',
    'catalog/groups.json',
    'scripts/install.sh',
    'scripts/mcp_config.py',
    'scripts/uninstall.sh',
    'scripts/verify_mcp.py',
)
SUMS_BLOCK = re.compile(r"(CRAFT_SETUP_SUMS=')\n.*?\n(')", re.S)
MARKER = re.compile(r'(<!-- INSTALL-SH-SHA256 -->)`?[0-9a-f]*`?(<!-- /INSTALL-SH-SHA256 -->)')
DOCS = ('README.md', 'RELEASE-NOTES-v0.3.0.md')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tracked_files():
    out = subprocess.run(['git', 'ls-files', '-z'], cwd=REPO, check=True,
                         capture_output=True).stdout.decode()
    return sorted(p for p in out.split('\0') if p and p != 'SHA256SUMS' and (REPO / p).is_file())


def build():
    """Return {relative path: new text} for every file whose content should change."""
    updates = {}
    boot = (REPO / 'install.sh').read_text()
    lines = '\n'.join(f'{sha256(REPO / p)}  {p}' for p in BOOTSTRAP_FILES)
    new_boot, count = SUMS_BLOCK.subn(lambda m: f'{m.group(1)}\n{lines}\n{m.group(2)}', boot)
    if count != 1:
        sys.exit('install.sh: checksum block not found')
    if new_boot != boot:
        updates['install.sh'] = new_boot
    boot_sha = hashlib.sha256(new_boot.encode()).hexdigest()
    for doc in DOCS:
        path = REPO / doc
        if not path.exists():
            continue
        text = path.read_text()
        new = MARKER.sub(lambda m: f'{m.group(1)}`{boot_sha}`{m.group(2)}', text)
        if new != text:
            updates[doc] = new
    contents = {p: (updates[p].encode() if p in updates else (REPO / p).read_bytes())
                for p in tracked_files()}
    sums = ''.join(f'{hashlib.sha256(data).hexdigest()}  {p}\n' for p, data in contents.items())
    old_sums = (REPO / 'SHA256SUMS').read_text() if (REPO / 'SHA256SUMS').exists() else ''
    if sums != old_sums:
        updates['SHA256SUMS'] = sums
    return updates


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('--check', action='store_true', help='report stale checksums; change nothing')
    args = parser.parse_args()
    updates = build()
    if args.check:
        for path in updates:
            print(f'stale: {path}')
        return 1 if updates else 0
    for path, text in updates.items():
        (REPO / path).write_text(text)
        print(f'updated {path}')
    if not updates:
        print('all checksums current')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
