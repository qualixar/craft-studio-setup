#!/usr/bin/env python3
"""Safe MCP config edits and installer state for craft-studio-setup.

Subcommands
  servers   print {name: {command, args}} for the selected catalog apps
  merge     add our servers to a JSON config (Claude Desktop or a workspace .mcp.json)
  remove    remove only the servers this installer recorded in a JSON config
  cc-match  does `claude mcp get` output (stdin) show exactly this entry at user scope?
  state     read or change the installer state file (what we installed)

Rules for every config edit:
  * invalid JSON, a non-object top level or a non-object "mcpServers" is refused
    (exit 3) and the file is left untouched;
  * a byte-for-byte backup is created (exclusively, never through a symlink)
    before the first change;
  * only "mcpServers" entries are touched; every other key is preserved;
  * an entry is added only under a free name, and changed or removed only while
    it still equals what this installer recorded writing;
  * the new file is written to a temporary file in the same directory, fsynced
    and renamed over the old one, but only if the file still holds the bytes
    that were read; it is then read back and checked, and the ownership record
    is saved. Any failure after the rename puts the previous bytes back.

Exit codes: 0 nothing changed, 10 changed, 3 refused, 4 failed check, 5 changed underneath us.
"""
import argparse
import datetime as _dt
import json
import os
from pathlib import Path
import sys
import tempfile

CHANGED = 10
REFUSED = 3
CHECK_FAILED = 4
RACE = 5
STATE_VERSION = 1
KINDS = ('configs', 'claude_code', 'desktop_apps', 'clis')


def _fail(code, message):
    print(f'ERROR: {message}', file=sys.stderr)
    raise SystemExit(code)


# --- state -------------------------------------------------------------------

def load_state(path):
    path = Path(path)
    if not path.exists():
        return {'version': STATE_VERSION, **{k: {} for k in KINDS}}
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as error:
        _fail(REFUSED, f'installer state file {path} is unreadable ({error}); '
                       'move it aside and re-run')
    if not isinstance(data, dict):
        _fail(REFUSED, f'installer state file {path} is not a JSON object')
    for key in KINDS:
        if not isinstance(data.get(key), dict):
            data[key] = {}
    data['version'] = STATE_VERSION
    return data


def save_state(path, state):
    path = Path(path)
    if not any(state[k] for k in KINDS):
        if path.exists():
            path.unlink()
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    atomic_write(path, (json.dumps(state, indent=2, sort_keys=True) + '\n').encode(), 0o600)


# --- file helpers --------------------------------------------------------------

_ANY = object()


class Raced(Exception):
    pass


class CheckFailed(Exception):
    pass


def _current_bytes(path):
    try:
        return path.read_bytes()
    except FileNotFoundError:
        return None


def atomic_write(path, data, mode=None, expect=_ANY):
    """Write bytes via a synced temporary file and rename.

    With expect (bytes, or None for "must not exist"), refuse to replace a file
    whose current content differs, so a concurrent edit is never overwritten.
    """
    path = Path(path)
    if mode is None:
        mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    fd, tmp = tempfile.mkstemp(prefix='.' + path.name + '.', suffix='.tmp', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        if expect is not _ANY and _current_bytes(path) != expect:
            raise Raced(f'{path} was changed by another program while this installer was '
                        'editing it. Nothing was written; run the command again.')
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def write_backup(path, raw):
    """Create <config>.craft-backup-<time> exclusively (no symlink following)."""
    stamp = _dt.datetime.now().strftime('%Y%m%d-%H%M%S')
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, 'O_NOFOLLOW', 0)
    for counter in range(1000):
        suffix = f'-{counter}' if counter else ''
        candidate = path.with_name(f'{path.name}.craft-backup-{stamp}{suffix}')
        try:
            fd = os.open(candidate, flags, 0o600)
        except FileExistsError:
            continue
        with os.fdopen(fd, 'wb') as handle:
            handle.write(raw)
            handle.flush()
            os.fsync(handle.fileno())
        return candidate
    _fail(REFUSED, f'could not create a backup next to {path}')


def read_config(path):
    """Return (raw bytes or None, parsed document). Refuse anything unsafe to edit."""
    raw = _current_bytes(path)
    if raw is None:
        return None, {}
    if not raw.strip():
        return raw, {}  # an empty file holds nothing to lose; it is backed up anyway
    try:
        doc = json.loads(raw)
    except ValueError as error:
        _fail(REFUSED, f'{path} is not valid JSON ({error}). Nothing was changed. '
                       'Fix the file (or restore one of its backups) and re-run.')
    if not isinstance(doc, dict):
        _fail(REFUSED, f'{path} must contain a JSON object at the top level. Nothing was changed.')
    if not isinstance(doc.get('mcpServers', {}), dict):
        _fail(REFUSED, f'"mcpServers" in {path} is not a JSON object. Nothing was changed.')
    return raw, doc


def verify(path, doc, before_doc, ours):
    try:
        raw = path.read_bytes()
        reread = json.loads(raw) if raw.strip() else {}
    except (OSError, ValueError) as error:
        raise CheckFailed(f'{path} did not parse after writing ({error})') from error
    if reread != doc:
        raise CheckFailed(f'{path} does not match what was written')
    for key, value in before_doc.items():
        if key != 'mcpServers' and reread.get(key) != value:
            raise CheckFailed(f'top-level key {key!r} in {path} changed unexpectedly')
    old = before_doc.get('mcpServers', {})
    new = reread.get('mcpServers', {})
    for name, value in old.items():
        if name not in ours and new.get(name) != value:
            raise CheckFailed(f'server {name!r} in {path} changed unexpectedly')


def commit(path, data, doc, before_doc, ours, raw, state, state_path):
    """Replace path with data (or delete it when data is None), check, then save state.

    raw is what was read (None: the file did not exist). Every failure after the
    replacement restores raw, so the config and the ownership record agree.
    """
    try:
        if data is None:
            if _current_bytes(path) != raw:
                raise Raced(f'{path} was changed by another program; nothing was removed. '
                            'Run the command again.')
            path.unlink()
        else:
            atomic_write(path, data, expect=raw)
    except Raced as error:
        _fail(RACE, str(error))
    try:
        if data is not None:
            verify(path, doc, before_doc, ours)
        save_state(state_path, state)
    except (CheckFailed, OSError, ValueError) as error:
        if raw is None:
            try:
                path.unlink()
            except OSError:
                pass
        else:
            atomic_write(path, raw)
        _fail(CHECK_FAILED, f'{error}; the previous file was put back')


def dumps(doc):
    return (json.dumps(doc, indent=2, ensure_ascii=False) + '\n').encode('utf-8')


# --- subcommands ---------------------------------------------------------------

def cmd_servers(args):
    catalog = {a['name']: a for a in json.loads(Path(args.catalog).read_text())['apps']}
    servers = {}
    for name in [n for n in args.apps.splitlines() if n.strip()]:
        app = catalog[name]
        servers[app['mcp_name']] = {
            'command': str(Path(args.bin_dir) / app['binary']),
            'args': [v.replace('{{WORKSPACE}}', args.workspace) for v in app['mcp_args']],
        }
    print(json.dumps(servers, sort_keys=True))
    return 0


def cmd_merge(args):
    path = Path(os.path.realpath(args.config))
    servers = json.loads(args.servers)
    state = load_state(args.state)
    record = state['configs'].get(str(path), {'created': False, 'backups': [], 'servers': {}})
    raw, doc = read_config(path)
    current = doc.get('mcpServers', {})
    owned = record['servers']
    actions = []
    for name, entry in sorted(servers.items()):
        have = current.get(name)
        if have == entry:
            actions.append(('=', name, 'already set' if name in owned else
                            'already present (not added by this installer, so uninstall keeps it)'))
        elif have is None:
            actions.append(('+', name, 'add'))
        elif name in owned and have == owned[name]:
            actions.append(('~', name, 'update (entry written by this installer)'))
        elif name in owned:
            actions.append(('!', name, 'left alone: edited since this installer wrote it'))
        else:
            actions.append(('!', name, 'left alone: an entry with this name exists and was '
                                       'not written by this installer'))
    to_write = [name for sign, name, _ in actions if sign in '+~']
    label = args.label
    verb = 'would ' if args.dry_run else ''
    print(f'   {label}: {path}')
    if raw is None and to_write:
        print(f'   {verb}create the file (it does not exist yet)')
    for sign, name, note in actions:
        print(f'     {sign} {name}: {verb if sign in "+~" else ""}{note}')
    if not to_write:
        print(f'   {label}: nothing to change')
        return 0
    if args.dry_run:
        if raw is not None:
            print(f'   would back up to {path.name}.craft-backup-<timestamp> first')
        return CHANGED
    new_doc = dict(doc)
    new_doc['mcpServers'] = {**current, **{name: servers[name] for name in to_write}}
    if raw is None:
        path.parent.mkdir(parents=True, exist_ok=True)
        record['created'] = not record['backups']
    else:
        backup = write_backup(path, raw)
        record['backups'].append(str(backup))
        print(f'   backup: {backup}')
    for name in to_write:
        owned[name] = servers[name]
    state['configs'][str(path)] = record
    commit(path, dumps(new_doc), new_doc, doc, set(to_write), raw, state, args.state)
    print(f'   {label}: wrote {len(to_write)} change(s); JSON checked after writing')
    return CHANGED


def cmd_remove(args):
    path = Path(os.path.realpath(args.config))
    state = load_state(args.state)
    record = state['configs'].get(str(path))
    label = args.label
    if not record or not record.get('servers'):
        print(f'   {label}: no entries from this installer recorded for {path}')
        return 0
    names = set(record['servers'])
    if args.names:
        names &= {n for n in args.names.split(',') if n}
    raw, doc = read_config(path)
    if raw is None:
        print(f'   {label}: {path} no longer exists; forgetting its entries')
        if not args.dry_run:
            for name in names:
                record['servers'].pop(name, None)
            _store_record(state, path, record)
            save_state(args.state, state)
        return 0
    current = doc.get('mcpServers', {})
    remove, keep, gone = [], [], []
    for name in sorted(names):
        if name not in current:
            gone.append(name)
        elif current[name] == record['servers'][name]:
            remove.append(name)
        else:
            keep.append(name)
    verb = 'would ' if args.dry_run else ''
    print(f'   {label}: {path}')
    for name in remove:
        print(f'     - {name}: {verb}remove')
    for name in keep:
        print(f'     ! {name}: left alone (edited since this installer wrote it)')
    for name in gone:
        print(f'     = {name}: already absent')
    if args.dry_run:
        return CHANGED if remove else 0
    for name in remove + gone + keep:
        record['servers'].pop(name, None)
    _store_record(state, path, record)
    if not remove:
        save_state(args.state, state)
        return 0
    new_doc = dict(doc)
    new_servers = {k: v for k, v in current.items() if k not in remove}
    original = _original(record)
    if new_servers or (original is not None and 'mcpServers' in original[0]):
        new_doc['mcpServers'] = new_servers
    else:
        new_doc.pop('mcpServers', None)
    backup = write_backup(path, raw)
    print(f'   backup: {backup}')
    if record.get('created') and new_doc == {} and not record['servers']:
        commit(path, None, new_doc, doc, set(remove), raw, state, args.state)
        print(f'   {label}: removed {path} (this installer created it and it is now empty)')
    elif original is not None and new_doc == original[0] and not record['servers']:
        commit(path, original[2], new_doc, doc, set(remove), raw, state, args.state)
        print(f'   {label}: restored byte-for-byte from {original[1]}')
    else:
        commit(path, dumps(new_doc), new_doc, doc, set(remove), raw, state, args.state)
        print(f'   {label}: removed {len(remove)} entr{"y" if len(remove) == 1 else "ies"}; '
              'JSON checked after writing')
    return CHANGED


def _original(record):
    """(parsed, path, bytes) of the first backup taken before this installer's first edit."""
    for backup in record.get('backups', [])[:1]:
        try:
            raw = Path(backup).read_bytes()
            return (json.loads(raw) if raw.strip() else {}), backup, raw
        except (OSError, ValueError):
            return None
    return None


def _store_record(state, path, record):
    if record['servers']:
        state['configs'][str(path)] = record
    else:
        state['configs'].pop(str(path), None)


def cmd_cc_match(args):
    """Exit 0 when `claude mcp get` output on stdin shows this exact user-scope entry."""
    entry = json.loads(args.entry)
    fields = {}
    for line in sys.stdin.read().splitlines():
        key, sep, value = line.strip().partition(':')
        if sep and key in ('Scope', 'Command', 'Args'):
            fields[key] = value.strip()
    return 0 if (fields.get('Scope', '').startswith('User')
                 and fields.get('Command') == entry['command']
                 and fields.get('Args', '') == ' '.join(entry['args'])) else 1


def cmd_state(args):
    state = load_state(args.state)
    kind = args.kind
    if args.action == 'get':
        value = state[kind].get(args.key) if args.key else state[kind]
        if value is not None:
            print(json.dumps(value, sort_keys=True))
        return 0
    if args.action == 'keys':
        for key in sorted(state[kind]):
            print(key)
        return 0
    if args.action == 'set':
        new = json.loads(args.value)
        if state[kind].get(args.key) == new:
            return 0
        state[kind][args.key] = new
    elif args.action == 'delete':
        if args.key not in state[kind]:
            return 0
        del state[kind][args.key]
    save_state(args.state, state)
    return CHANGED


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest='command', required=True)

    p = sub.add_parser('servers')
    p.add_argument('--catalog', required=True)
    p.add_argument('--bin-dir', required=True)
    p.add_argument('--workspace', required=True)
    p.add_argument('--apps', required=True)
    p.set_defaults(func=cmd_servers)

    for name, func in (('merge', cmd_merge), ('remove', cmd_remove)):
        p = sub.add_parser(name)
        p.add_argument('--config', required=True)
        p.add_argument('--state', required=True)
        p.add_argument('--label', default='config')
        p.add_argument('--dry-run', action='store_true')
        if name == 'merge':
            p.add_argument('--servers', required=True, help='JSON object {name: entry}')
        else:
            p.add_argument('--names', default='', help='comma-separated subset to remove')
        p.set_defaults(func=func)

    p = sub.add_parser('cc-match')
    p.add_argument('--entry', required=True)
    p.set_defaults(func=cmd_cc_match)

    p = sub.add_parser('state')
    p.add_argument('action', choices=('get', 'keys', 'set', 'delete'))
    p.add_argument('--state', required=True)
    p.add_argument('--kind', required=True, choices=KINDS)
    p.add_argument('--key', default='')
    p.add_argument('--value', default='null')
    p.set_defaults(func=cmd_state)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == '__main__':
    raise SystemExit(main())
