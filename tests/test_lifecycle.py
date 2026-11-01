"""v0.3.0 lifecycle: aliases, dry run, Claude Desktop merge, idempotency, uninstall, bootstrapper.

Every test runs in a temporary HOME with fake downloads and a fake `claude`.
The real ~/.claude, ~/.claude.json and Claude Desktop config are never read or written.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import unittest

from test_install import Fixture, REPO

UNINSTALL = REPO / 'scripts/uninstall.sh'
BOOTSTRAP = REPO / 'install.sh'
BOOT_FILES = ('install.sh', 'catalog/apps.json', 'catalog/groups.json', 'scripts/install.sh',
              'scripts/mcp_config.py', 'scripts/uninstall.sh', 'scripts/verify_mcp.py')


def snapshot(root):
    """Every path under root with its type and content hash (symlinks by target)."""
    result = {}
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            p = Path(dirpath) / name
            rel = str(p.relative_to(root))
            if p.is_symlink():
                result[rel] = 'link:' + os.readlink(p)
            elif p.is_dir():
                result[rel] = 'dir'
            else:
                result[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


class LifecycleTests(Fixture):
    def setUp(self):
        super().setUp()
        self.desktop_config = (self.home / 'Library/Application Support/Claude'
                               / 'claude_desktop_config.json')
        self.bin = Path(self.env['CRAFT_BIN_DIR'])
        self.craft_home = Path(self.env['CRAFT_HOME'])
        self.workspace = Path(self.env['CRAFT_WORKSPACE'])

    # --- helpers ---------------------------------------------------------------
    def run_uninstall(self, *args, expected=0, extra=None, stdin=None):
        env = dict(self.env, **(extra or {}))
        r = subprocess.run(['/bin/bash', str(UNINSTALL), *args], env=env, input=stdin,
                           text=True, capture_output=True, timeout=60)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout + r.stderr

    def write_desktop_config(self, doc=None, raw=None):
        self.desktop_config.parent.mkdir(parents=True, exist_ok=True)
        if raw is None:
            raw = json.dumps(doc, indent=4) + '\n'
        self.desktop_config.write_text(raw)
        return raw

    def desktop_doc(self):
        return json.loads(self.desktop_config.read_text())

    def backups(self):
        return sorted(self.desktop_config.parent.glob('claude_desktop_config.json.craft-backup-*'))

    def claude_db(self):
        db = self.root / 'mcp.json'
        return json.loads(db.read_text()) if db.exists() else {}

    def claude_adds(self):
        log = self.root / 'claude.log'
        if not log.exists():
            return []
        return [x for x in map(json.loads, log.read_text().splitlines()) if x[:2] == ['mcp', 'add']]

    def realistic_config(self):
        return {
            'mcpServers': {
                'filesystem': {'command': 'npx', 'args': ['-y', '@modelcontextprotocol/server-filesystem',
                                                          str(self.home / 'Desktop')]},
                'my-notes': {'command': '/usr/local/bin/notes-mcp', 'args': [], 'env': {'NOTES': '1'}},
            },
            'globalShortcut': 'Ctrl+Space',
            'preferences': {'menuBarEnabled': True, 'quickEntryShortcut': 'off'},
        }

    # --- aliases ---------------------------------------------------------------
    def test_alias_groups_select_the_right_apps(self):
        groups = {'aliases': {'adobe': 'creator', 'microsoft': 'office'},
                  'groups': {'creator': {'apps': ['fake1']}, 'office': {'apps': ['fake2']},
                             'all': {'apps': ['fake1', 'fake2']}}}
        (self.catalog / 'groups.json').write_text(json.dumps(groups))
        self.run_install('adobe', '--yes', '--skip-mcp')
        self.assertTrue((self.bin / 'fake1-cli').exists())
        self.assertFalse((self.bin / 'fake2-cli').exists())
        self.run_install('--group', 'microsoft', '--yes', '--skip-mcp')
        self.assertTrue((self.bin / 'fake2-cli').exists())
        self.run_uninstall('microsoft', '--yes')
        self.assertFalse((self.bin / 'fake2-cli').exists())
        self.assertTrue((self.bin / 'fake1-cli').exists())
        self.run_install('--group', 'excel', '--yes', expected=1)

    def test_real_catalog_aliases_in_dry_run(self):
        env = dict(self.env)
        env.pop('CRAFT_CATALOG_DIR')
        expected = {'adobe': ['photocraft', 'vectorcraft', 'filmcraft', 'lightcraft', 'effectcraft', 'soundcraft'],
                    'microsoft': ['pdfcraft', 'wordcraft', 'gridcraft', 'deckcraft', 'designcraft',
                                  'figcraft', 'cadcraft']}
        before = snapshot(self.home)
        for alias, apps in expected.items():
            r = subprocess.run(['/bin/bash', str(REPO / 'scripts/install.sh'), alias, '--dry-run', '--both'],
                               env=env, text=True, capture_output=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            installed = [line.split()[1] for line in r.stdout.splitlines() if line.startswith('== ')
                         and 'craft ' in line]
            self.assertEqual(installed, apps, r.stdout)
            self.assertIn('https://github.com/storytold/', r.stdout)
        self.assertEqual(before, snapshot(self.home))

    # --- dry run ---------------------------------------------------------------
    def test_dry_run_touches_nothing(self):
        raw = self.write_desktop_config(self.realistic_config())
        before = snapshot(self.home)
        out = self.run_install('all', '--dry-run', '--both', '--desktop', '--desktop-dir', str(self.target))
        self.assertEqual(before, snapshot(self.home))
        self.assertFalse(self.target.exists())
        self.assertEqual(self.desktop_config.read_text(), raw)
        for needle in ('DRY RUN', 'would download https://fixture/', str(self.craft_home / 'fake1'),
                       str(self.bin / 'fake1-cli'), 'claude mcp add --scope user fake1',
                       str(self.desktop_config), 'would back up', str(self.target), 'nothing was changed'):
            self.assertIn(needle, out)
        self.assertFalse((self.root / 'downloads').exists())
        self.assertFalse((self.root / 'hdiutil.log').exists())
        self.assertEqual(self.claude_adds(), [])

    def test_uninstall_dry_run_touches_nothing(self):
        self.write_desktop_config(self.realistic_config())
        self.run_install('--yes', '--both')
        before = snapshot(self.home)
        out = self.run_uninstall('--dry-run')
        self.assertIn('would remove', out)
        self.assertEqual(before, snapshot(self.home))

    # --- Claude Desktop config merge ---------------------------------------------
    def test_desktop_merge_keeps_servers_and_unknown_keys_and_backs_up(self):
        original = self.realistic_config()
        raw = self.write_desktop_config(original)
        out = self.run_install('--yes', '--claude-desktop')
        doc = self.desktop_doc()
        for key in ('globalShortcut', 'preferences'):
            self.assertEqual(doc[key], original[key])
        for name, entry in original['mcpServers'].items():
            self.assertEqual(doc['mcpServers'][name], entry)
        self.assertEqual(doc['mcpServers']['fake1']['command'], str(self.bin / 'fake1-cli'))
        self.assertEqual(doc['mcpServers']['fake1']['args'][-1], str(self.workspace))
        [backup] = self.backups()
        self.assertEqual(backup.read_text(), raw)
        self.assertIn('+ fake1', out)
        self.assertIn('Quit Claude Desktop', out)
        self.assertEqual(self.claude_adds(), [])  # --claude-desktop alone leaves Claude Code alone

    def test_desktop_merge_creates_missing_config(self):
        self.run_install('--yes', '--claude-desktop')
        self.assertEqual(set(self.desktop_doc()['mcpServers']), {'fake1', 'fake2'})
        self.assertEqual(self.backups(), [])

    def test_desktop_merge_accepts_empty_file(self):
        self.write_desktop_config(raw='')
        self.run_install('--yes', '--claude-desktop')
        self.assertEqual(set(self.desktop_doc()['mcpServers']), {'fake1', 'fake2'})
        self.assertEqual(len(self.backups()), 1)
        self.run_uninstall('--yes')
        self.assertEqual(self.desktop_config.read_text(), '')

    def test_desktop_merge_leaves_foreign_same_name_entry(self):
        config = self.realistic_config()
        config['mcpServers']['fake1'] = {'command': '/opt/mine/fake1', 'args': ['serve']}
        self.write_desktop_config(config)
        out = self.run_install('--yes', '--claude-desktop')
        self.assertEqual(self.desktop_doc()['mcpServers']['fake1'], config['mcpServers']['fake1'])
        self.assertIn('left alone', out)

    def test_desktop_bad_json_is_refused(self):
        for raw in ('{"mcpServers": {', '[]', '{"mcpServers": []}', '{"a": 1}{"b": 2}'):
            with self.subTest(raw=raw):
                self.write_desktop_config(raw=raw)
                out = self.run_install('--yes', '--claude-desktop', expected=1)
                self.assertIn('Nothing was changed', out)
                self.assertEqual(self.desktop_config.read_text(), raw)
                self.assertEqual(self.backups(), [])

    def test_default_targets_detect_claude_desktop(self):
        out = self.run_install('--yes')
        self.assertIn('Claude Desktop not found', out)
        self.assertFalse(self.desktop_config.exists())
        self.desktop_config.parent.mkdir(parents=True)
        self.run_install('--yes')
        self.assertEqual(set(self.desktop_doc()['mcpServers']), {'fake1', 'fake2'})
        self.assertEqual(len(self.claude_adds()), 2)

    def test_claude_code_foreign_same_name_left_alone(self):
        (self.root / 'mcp.json').write_text(json.dumps({'fake1': ['/opt/other/server', 'run']}))
        out = self.run_install('--yes', '--claude-code')
        self.assertEqual(self.claude_db()['fake1'], ['/opt/other/server', 'run'])
        self.assertIn('left alone', out)
        self.assertEqual(self.claude_db()['fake2'][0], str(self.bin / 'fake2-cli'))

    def test_project_mcp_json_in_current_folder_is_not_mistaken_for_user_scope(self):
        project = self.root / 'some project'
        project.mkdir()
        (project / '.mcp.json').write_text(json.dumps({'mcpServers': {'fake1': {'command': 'x'}}}))
        self.run_install('--yes', '--claude-code', cwd=project)
        self.assertEqual(self.claude_db()['fake1'][0], str(self.bin / 'fake1-cli'))

    def test_workspace_mcp_json_fallback_without_claude_cli(self):
        (self.stub / 'claude').unlink()
        out = self.run_install('--yes', '--claude-code')
        self.assertIn('.mcp.json', out)
        doc = json.loads((self.workspace / '.mcp.json').read_text())
        self.assertEqual(set(doc['mcpServers']), {'fake1', 'fake2'})
        self.run_uninstall('--yes')
        self.assertFalse((self.workspace / '.mcp.json').exists())
        self.assertTrue(self.workspace.is_dir())

    def test_dead_mcp_server_fails_with_exit_2(self):
        out = self.run_install('--yes', '--claude-desktop', expected=2, extra={'MCP_DEAD': '1'})
        self.assertIn('MCP NOT CONNECTED', out)

    # --- idempotency -----------------------------------------------------------
    def test_second_run_changes_nothing(self):
        self.write_desktop_config(self.realistic_config())
        first = self.run_install('--yes', '--both', '--desktop', '--desktop-dir', str(self.target))
        self.assertIn('change(s) made', first)
        before = snapshot(self.root / 'home with spaces')
        adds = len(self.claude_adds())
        second = self.run_install('--yes', '--both', '--desktop', '--desktop-dir', str(self.target))
        self.assertIn('Already installed, nothing changed.', second)
        self.assertEqual(len(self.claude_adds()), adds)
        self.assertEqual(len(self.backups()), 1)
        self.assertEqual(before, snapshot(self.root / 'home with spaces'))
        dry = self.run_install('--dry-run', '--both', '--desktop', '--desktop-dir', str(self.target))
        self.assertIn('Already installed, nothing changed.', dry)

    # --- uninstall -------------------------------------------------------------
    def test_uninstall_removes_only_ours_and_restores_config(self):
        raw = self.write_desktop_config(self.realistic_config())
        (self.root / 'mcp.json').write_text(json.dumps({'someone-else': ['/opt/x', 'y']}))
        self.bin.mkdir(parents=True)
        (self.bin / 'my-tool').write_text('#!/bin/sh\n')
        self.target.mkdir()
        (self.target / 'Mine.app').mkdir()
        self.run_install('--yes', '--both', '--desktop', '--desktop-dir', str(self.target))
        self.assertTrue((self.target / 'Fake One.app').is_dir())
        (self.workspace / 'my-document.docx').write_text('keep me')

        out = self.run_uninstall('--yes')
        self.assertIn('restored byte-for-byte', out)
        self.assertEqual(self.desktop_config.read_text(), raw)
        self.assertEqual(self.claude_db(), {'someone-else': ['/opt/x', 'y']})
        self.assertFalse((self.bin / 'fake1-cli').exists())
        self.assertTrue((self.bin / 'my-tool').exists())
        self.assertFalse((self.target / 'Fake One.app').exists())
        self.assertTrue((self.target / 'Mine.app').is_dir())
        self.assertFalse(self.craft_home.exists())
        self.assertEqual((self.workspace / 'my-document.docx').read_text(), 'keep me')
        self.assertIn('Nothing to do', self.run_uninstall('--yes'))

    def test_uninstall_keeps_later_user_edits(self):
        self.write_desktop_config(self.realistic_config())
        self.run_install('--yes', '--claude-desktop')
        doc = self.desktop_doc()
        doc['mcpServers']['added-later'] = {'command': '/bin/echo', 'args': []}
        doc['mcpServers']['fake2']['args'].append('--edited-by-user')
        self.desktop_config.write_text(json.dumps(doc))
        out = self.run_uninstall('--yes')
        after = self.desktop_doc()['mcpServers']
        self.assertNotIn('fake1', after)
        self.assertIn('added-later', after)
        self.assertIn('--edited-by-user', after['fake2']['args'])
        self.assertIn('left alone', out)
        self.assertEqual(set(self.realistic_config()['mcpServers']) - set(after), set())

    def test_uninstall_keeps_folders_it_did_not_install(self):
        manual = self.craft_home / 'fake2'
        manual.mkdir(parents=True)
        (manual / 'notes.txt').write_text('mine')
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp')
        out = self.run_uninstall('--yes')
        self.assertIn('kept', out)
        self.assertEqual((manual / 'notes.txt').read_text(), 'mine')
        self.assertFalse((self.craft_home / 'fake1').exists())

    def test_uninstall_keeps_claude_code_server_edited_after_install(self):
        self.run_install('--yes', '--claude-code')
        db = self.claude_db()
        db['fake1'] = db['fake1'] + ['--my-flag']
        (self.root / 'mcp.json').write_text(json.dumps(db))
        out = self.run_uninstall('--yes')
        self.assertIn('left alone', out)
        self.assertEqual(set(self.claude_db()), {'fake1'})

    def test_failed_claude_remove_keeps_record_and_fails(self):
        self.run_install('--yes', '--claude-code')
        self.run_uninstall('--yes', expected=1, extra={'CLAUDE_REMOVE_FAIL': '1'})
        self.assertEqual(set(self.claude_db()), {'fake1', 'fake2'})
        self.run_uninstall('--yes')
        self.assertEqual(self.claude_db(), {})

    def test_identical_existing_desktop_entry_is_not_adopted(self):
        self.run_install('--yes', '--skip-mcp')
        entry = {'command': str(self.bin / 'fake1-cli'),
                 'args': ['mcp', '--automation-write-root', str(self.workspace)]}
        self.write_desktop_config({'mcpServers': {'fake1': entry}})
        out = self.run_install('--yes', '--claude-desktop')
        self.assertIn('not added by this installer', out)
        self.run_uninstall('--yes')
        self.assertEqual(self.desktop_doc()['mcpServers'], {'fake1': entry})

    def test_rerun_does_not_overwrite_user_edits_to_our_entry(self):
        self.run_install('--yes', '--claude-desktop')
        doc = self.desktop_doc()
        doc['mcpServers']['fake1']['env'] = {'MY': '1'}
        self.desktop_config.write_text(json.dumps(doc))
        out = self.run_install('--yes', '--claude-desktop', '--workspace', str(self.root / 'other ws'))
        self.assertIn('edited since', out)
        self.assertEqual(self.desktop_doc()['mcpServers']['fake1']['env'], {'MY': '1'})
        self.assertEqual(self.desktop_doc()['mcpServers']['fake2']['args'][-1], str(self.root / 'other ws'))

    def test_uninstall_asks_and_declining_changes_nothing(self):
        self.run_install('--yes', '--skip-mcp')
        before = snapshot(self.root)
        self.run_uninstall(stdin='n\n', expected=1)
        self.run_uninstall(stdin='', expected=1)
        self.assertEqual(before, snapshot(self.root))

    # --- bootstrapper ------------------------------------------------------------
    def make_tarball(self, tamper=None, extra=None):
        path = self.root / 'source.tar.gz'
        with tarfile.open(path, 'w:gz') as tar:
            for rel, data in (extra or {}).items():
                info = tarfile.TarInfo('craft-studio-setup-0.3.0/' + rel)
                info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            for rel in BOOT_FILES:
                data = (REPO / rel).read_bytes()
                if rel == tamper:
                    data += b'\n# tampered\n'
                info = tarfile.TarInfo('craft-studio-setup-0.3.0/' + rel)
                info.size = len(data)
                info.mode = 0o755 if rel.endswith('.sh') else 0o644
                tar.addfile(info, io.BytesIO(data))
        return path

    def run_bootstrap(self, *args, tarball, expected=0, extra=None, stdin=''):
        env = dict(self.env, CRAFT_SETUP_TARBALL=str(tarball), **(extra or {}))
        r = subprocess.run(['/bin/bash', '-s', '--', *args], input=BOOTSTRAP.read_text() if stdin == ''
                           else stdin, env=env, text=True, capture_output=True, timeout=120,
                           start_new_session=True)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout + r.stderr

    def test_bootstrap_pipe_install_and_uninstall(self):
        tarball = self.make_tarball()
        out = self.run_bootstrap('microsoft', '--yes', '--skip-mcp', tarball=tarball)
        self.assertIn('Verified 6 files', out)
        self.assertTrue((self.bin / 'fake1-cli').exists())
        out = self.run_bootstrap('microsoft', '--yes', '--skip-mcp', tarball=tarball)
        self.assertIn('Already installed, nothing changed.', out)
        self.run_bootstrap('uninstall', '--yes', tarball=tarball)
        self.assertFalse((self.bin / 'fake1-cli').exists())

    def test_bootstrap_without_terminal_or_yes_shows_plan_and_refuses(self):
        before = snapshot(self.root / 'home with spaces')
        out = self.run_bootstrap('all', '--skip-mcp', tarball=self.make_tarball(), expected=1)
        self.assertIn('would download', out)
        self.assertIn('Re-run with --yes', out)
        self.assertEqual(before, snapshot(self.root / 'home with spaces'))

    def test_bootstrap_dry_run(self):
        before = snapshot(self.root / 'home with spaces')
        out = self.run_bootstrap('all', '--dry-run', tarball=self.make_tarball())
        self.assertIn('nothing was changed', out)
        self.assertEqual(before, snapshot(self.root / 'home with spaces'))

    def test_bootstrap_rejects_tampered_files(self):
        for rel in ('scripts/install.sh', 'catalog/apps.json', 'scripts/mcp_config.py'):
            with self.subTest(rel=rel):
                out = self.run_bootstrap('all', '--yes', tarball=self.make_tarball(tamper=rel), expected=1)
                self.assertIn('CHECKSUM MISMATCH for ' + rel, out)
                self.assertFalse(self.bin.exists())

    def test_bootstrap_never_runs_unlisted_files(self):
        marker = self.root / 'planted-ran'
        planted = f'open({str(marker)!r}, "w").write("x")\n'.encode()
        tarball = self.make_tarball(extra={'scripts/json.py': planted, 'scripts/argparse.py': planted,
                                           'catalog/json.py': planted})
        self.run_bootstrap('all', '--yes', '--claude-desktop', tarball=tarball)
        self.assertFalse(marker.exists())
        self.assertTrue((self.bin / 'fake1-cli').exists())

    def test_bootstrap_tarball_sha_pin(self):
        tarball = self.make_tarball()
        out = self.run_bootstrap('all', '--dry-run', tarball=tarball, expected=1,
                                 extra={'CRAFT_SETUP_TARBALL_SHA256': '0' * 64})
        self.assertIn('CHECKSUM MISMATCH for the source tarball', out)
        good = hashlib.sha256(tarball.read_bytes()).hexdigest()
        self.run_bootstrap('all', '--dry-run', tarball=tarball, extra={'CRAFT_SETUP_TARBALL_SHA256': good})


class ConfigHelperTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('mcp_config', REPO / 'scripts/mcp_config.py')
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)
        self.tmp = Path(__import__('tempfile').mkdtemp(prefix='craft-helper-'))
        self.addCleanup(__import__('shutil').rmtree, self.tmp)

    def test_atomic_write_refuses_concurrent_change(self):
        target = self.tmp / 'config.json'
        target.write_bytes(b'{"a": 1}')
        with self.assertRaises(self.mod.Raced):
            self.mod.atomic_write(target, b'{}', expect=b'{"a": 0}')
        self.assertEqual(target.read_bytes(), b'{"a": 1}')
        self.assertEqual([p.name for p in self.tmp.iterdir()], ['config.json'])

    def test_backup_is_exclusive_and_private(self):
        target = self.tmp / 'config.json'
        first = self.mod.write_backup(target, b'one')
        second = self.mod.write_backup(target, b'two')
        self.assertNotEqual(first, second)
        self.assertEqual((first.read_bytes(), second.read_bytes()), (b'one', b'two'))
        self.assertEqual(first.stat().st_mode & 0o777, 0o600)

    def test_cc_match(self):
        entry = json.dumps({'command': '/b/x-cli', 'args': ['mcp', '--root', '/w s']})
        good = 'x:\n  Scope: User config\n  Command: /b/x-cli\n  Args: mcp --root /w s\n'
        for text, expected in ((good, 0), (good.replace('User', 'Project'), 1),
                               (good.replace('/w s', '/w s --extra'), 1)):
            with self.subTest(text=text):
                import contextlib
                with contextlib.redirect_stdout(io.StringIO()):
                    sys_stdin = __import__('sys').stdin
                    __import__('sys').stdin = io.StringIO(text)
                    try:
                        self.assertEqual(self.mod.main(['cc-match', '--entry', entry]), expected)
                    finally:
                        __import__('sys').stdin = sys_stdin


class ChecksumTests(unittest.TestCase):
    def test_published_checksums_are_current(self):
        r = subprocess.run(['python3', str(REPO / 'scripts/update_checksums.py'), '--check'],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, 'run scripts/update_checksums.py\n' + r.stdout + r.stderr)

    def test_bootstrap_is_pinned_to_this_release(self):
        plugin = json.loads((REPO / '.claude-plugin/plugin.json').read_text())
        text = BOOTSTRAP.read_text()
        self.assertIn(f'CRAFT_SETUP_REF="v{plugin["version"]}"', text)
        self.assertIn(f'craft-studio-setup/v{plugin["version"]}/install.sh', (REPO / 'README.md').read_text())
        self.assertNotIn('eval ', text)
        self.assertNotIn('sudo ', (REPO / 'scripts/install.sh').read_text())


if __name__ == '__main__':
    unittest.main(verbosity=2)
