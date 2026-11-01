"""Installer contract tests: temp HOME, fake downloads/DMGs, no network."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

REPO = Path(__file__).resolve().parents[1]
INSTALL = REPO / 'scripts/install.sh'


MCP_SERVER = r'''
import json, sys
for line in sys.stdin:
    m = json.loads(line)
    if m.get('method') == 'initialize':
        r = {'protocolVersion': '2024-11-05', 'capabilities': {}, 'serverInfo': {'name': 'fixture', 'version': '1'}}
    elif m.get('method') == 'tools/list':
        r = {'tools': [{'name': 'fixture'}]}
    else:
        continue
    print(json.dumps({'jsonrpc': '2.0', 'id': m['id'], 'result': r}), flush=True)
'''


class Fixture(unittest.TestCase):
    """Temp HOME, fake downloads, fake DMGs and a fake `claude`. No network."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='craft-fixture-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / 'home with spaces'
        self.home.mkdir()
        self.stub = self.root / 'stub'
        self.stub.mkdir()
        self.catalog = self.root / 'catalog'
        self.catalog.mkdir()
        self.target = self.root / 'Applications with spaces'
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=str(self.stub) + ':/usr/bin:/bin:/usr/sbin:/sbin',
                        CRAFT_HOME=str(self.home / 'tools/craft'),
                        CRAFT_BIN_DIR=str(self.home / '.local/bin'),
                        CRAFT_WORKSPACE=str(self.home / 'workspace'),
                        CRAFT_CATALOG_DIR=str(self.catalog), FIXTURE=str(self.root),
                        TMPDIR=str(self.root),
                        CRAFT_CLAUDE_DESKTOP_APPS=str(self.root / 'no-claude-desktop.app'))
        for key in ('CRAFT_YES', 'CRAFT_SKIP_MCP', 'CRAFT_GROUP', 'CRAFT_CURL_PROTO',
                    'CLAUDE_CONFIG_DIR'):
            self.env.pop(key, None)
        self.write_stub('curl', '''
import os, pathlib, shutil, sys
args=sys.argv[1:]; dest=pathlib.Path(args[args.index('-o')+1]); url=args[-1]
with open(os.environ['FIXTURE']+'/downloads','a') as f: f.write(url+'\\n')
shutil.copyfile(url.removeprefix('https://fixture/'), dest)
''')
        self.write_stub('claude', '''
import json, os, pathlib, sys
r=pathlib.Path(os.environ['FIXTURE']); args=sys.argv[1:]
with (r/'claude.log').open('a') as f: f.write(json.dumps(args)+'\\n')
db=r/'mcp.json'; servers=json.loads(db.read_text()) if db.exists() else {}
if args[:2]==['mcp','add']:
    name=args[4]; servers[name]=args[args.index('--')+1:]; db.write_text(json.dumps(servers))
elif args[:2]==['mcp','get']:
    if os.environ.get('CLAUDE_GET_FAIL'): print('Error: could not read config'); sys.exit(1)
    project=pathlib.Path.cwd()/'.mcp.json'  # like claude: project servers from the current folder
    if project.exists() and args[2] in json.loads(project.read_text()).get('mcpServers', {}):
        print(args[2]+':'); print('  Scope: Project config'); sys.exit(0)
    if args[2] not in servers: print('No MCP server named "'+args[2]+'".'); sys.exit(1)
    print(args[2]+':'); print('  Scope: User config (available in all your projects)')
    print('  Command: '+servers[args[2]][0]); print('  Args: '+' '.join(servers[args[2]][1:]))
elif args[:2]==['mcp','remove']:
    if os.environ.get('CLAUDE_REMOVE_FAIL'): sys.exit(1)
    name=args[-1]
    if name not in servers: sys.exit(1)
    del servers[name]; db.write_text(json.dumps(servers))
elif args[:2]==['mcp','list']:
    for n in servers:
        if os.environ.get('MCP_MISSING')==n: continue
        print(n+(': cmd - Failed to connect' if os.environ.get('MCP_FAIL')==n else ': cmd - Connected'))
    if os.environ.get('MCP_LIST_FAIL'): sys.exit(1)
''')
        self.write_stub('hdiutil', '''
import os, pathlib, plistlib, sys
r=pathlib.Path(os.environ['FIXTURE']); args=sys.argv[1:]
with (r/'hdiutil.log').open('a') as f: f.write(' '.join(args)+'\\n')
if args[0]=='attach':
    if os.environ.get('ATTACH_FAIL'): sys.exit(1)
    mount=pathlib.Path(args[args.index('-mountpoint')+1])
    if not os.environ.get('MISSING_APP'):
        bundle=mount/'Fake One.app'/'Contents'; bundle.mkdir(parents=True)
        (bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'9.9.9'}))
        (bundle/'payload').write_text('desktop fixture')
elif args[0]=='detach':
    if os.environ.get('DETACH_FAIL'): sys.exit(1)
    import shutil
    for p in pathlib.Path(args[1]).iterdir():
        if p.is_dir(): shutil.rmtree(p)
        else: p.unlink()
''')
        (self.root/'mcp_server.py').write_text(MCP_SERVER)
        self.apps = []
        for n in ('fake1', 'fake2'):
            archive = self.root / (n + '.zip')
            binary = ('#!/bin/bash\nif [ "${1:-}" = --version ]; then echo "' + n + '-cli 9.9.9"; exit 0; fi\n'
                      'if [ "${1:-}" = mcp ] && [ -z "${MCP_DEAD:-}" ]; then exec ' + sys.executable
                      + ' -c "$(cat "$FIXTURE/mcp_server.py")"; fi\nexit 0\n')
            with zipfile.ZipFile(archive, 'w') as z:
                z.writestr(n + '-payload/' + n + '-cli', binary)
            dmg = self.root / (n + '.dmg')
            dmg.write_bytes(b'fake dmg data')
            self.apps.append(dict(name=n, version='9.9.9', binary=n+'-cli',
                                  asset=n+'.zip', asset_url='https://fixture/'+str(archive),
                                  sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                                  mcp_name=n, mcp_args=['mcp', '--automation-write-root', '{{WORKSPACE}}'],
                                  group='creator', desktop=dict(asset=n+'.dmg',
                                  asset_url='https://fixture/'+str(dmg),
                                  sha256=hashlib.sha256(dmg.read_bytes()).hexdigest())))
        self.save_catalog()
        groups = {n: {'apps': ['fake1', 'fake2']} for n in ('creator', 'office', 'all')}
        aliases = {'adobe': 'creator', 'microsoft': 'office'}
        (self.catalog/'groups.json').write_text(json.dumps({'aliases': aliases, 'groups': groups}))

    def write_stub(self, name, source):
        p = self.stub / name
        p.write_text('#!' + sys.executable + '\n' + source)
        p.chmod(0o755)

    def save_catalog(self):
        (self.catalog/'apps.json').write_text(json.dumps({'apps': self.apps}))

    def run_install(self, *args, expected=0, extra=None, stdin=None, cwd=None):
        env = dict(self.env, **(extra or {}))
        r = subprocess.run(['/bin/bash', str(INSTALL), *args], env=env, cwd=cwd,
                           input=stdin, text=True, capture_output=True, timeout=30)
        self.assertEqual(r.returncode, expected, r.stdout + r.stderr)
        return r.stdout + r.stderr


class InstallerTests(Fixture):
    def test_checksum_fails_closed(self):
        self.apps[0]['sha256'] = '0' * 64
        self.save_catalog()
        out = self.run_install('--yes', '--skip-mcp', expected=1)
        self.assertIn('CHECKSUM MISMATCH', out)
        self.assertFalse((Path(self.env['CRAFT_BIN_DIR'])/'fake1-cli').exists())
        self.assertFalse((Path(self.env['CRAFT_HOME'])/'.cache-zips/fake1.zip').exists())
        self.assertFalse((self.root/'hdiutil.log').exists())

    def test_success_mcp_workspace_and_idempotency(self):
        self.run_install('--group', 'all', '--yes')  # command from Episode 1
        log = [json.loads(x) for x in (self.root/'claude.log').read_text().splitlines()]
        adds = [x for x in log if x[:2] == ['mcp', 'add']]
        self.assertEqual(len(adds), 2)
        self.assertEqual(adds[0][2:5], ['--scope', 'user', 'fake1'])
        self.assertEqual(adds[0][-1], self.env['CRAFT_WORKSPACE'])
        self.assertTrue((Path(self.env['CRAFT_WORKSPACE'])/'setup-report.md').is_file())
        self.assertIn('already installed', self.run_install('--yes', '--skip-mcp'))
        self.assertFalse((self.root/'hdiutil.log').exists())
        self.assertEqual(len((self.root/'downloads').read_text().splitlines()), 2)

    def test_upgrades_old_cli(self):
        bindir = Path(self.env['CRAFT_BIN_DIR'])
        bindir.mkdir(parents=True)
        p = bindir/'fake1-cli'
        p.write_text('#!/bin/bash\necho fake1-cli 0.0.1\n')
        p.chmod(0o755)
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp')
        self.assertEqual(subprocess.check_output([str(p), '--version'], text=True).strip(), 'fake1-cli 9.9.9')

    def test_mcp_health_failure_missing_and_list_error(self):
        self.run_install('--yes', '--skip-mcp')
        for extra in ({'MCP_FAIL': 'fake2'}, {'MCP_MISSING': 'fake2'}, {'MCP_LIST_FAIL': '1'}):
            out = self.run_install('--mcp-only', '--yes', expected=2, extra=extra)
            self.assertIn('MCP NOT CONNECTED:', out)

    def test_declined_connections_are_not_health_failures(self):
        self.run_install('--yes', '--skip-mcp')
        self.run_install('--group', 'all', stdin='n\nn\nn\nn\n')
        log = self.root/'claude.log'
        self.assertNotIn('"add"', log.read_text() if log.exists() else '')

    def test_interactive_desktop_reads_user_answers(self):
        self.run_install('--skip-mcp', '--desktop', '--desktop-dir', str(self.target),
                         stdin='y\nn\ny\nn\n')
        for app in ('fake1', 'fake2'):
            self.assertTrue((Path(self.env['CRAFT_BIN_DIR'])/(app+'-cli')).is_file())
        self.assertFalse((self.root/'hdiutil.log').exists())

    def test_interactive_decline_and_eof_install_nothing(self):
        self.run_install('--skip-mcp', '--desktop', stdin='n\nn\n')
        self.run_install('--skip-mcp', '--desktop', stdin='')
        self.assertFalse((self.root/'downloads').exists())

    def test_interrupted_desktop_promotion_restores_previous(self):
        previous = self.target/'Fake One.app/Contents'
        previous.mkdir(parents=True)
        (previous/'payload').write_text('old desktop')
        self.write_stub('mv', r'''import os, signal, subprocess, sys
args=sys.argv[1:]
if '.craft-fake1.' in args[0] and args[0].endswith('/Fake One.app'):
    os.kill(os.getppid(), signal.SIGTERM)
    sys.exit(1)
sys.exit(subprocess.call(['/bin/mv', *args]))
''')
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                         '--desktop-dir', str(self.target), expected=1)
        self.assertEqual((previous/'payload').read_text(), 'old desktop')
        self.assertIn('detach ', (self.root/'hdiutil.log').read_text())

    def test_desktop_opt_in_copies_and_detaches(self):
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                         '--desktop-dir', str(self.target))
        self.assertEqual((self.target/'Fake One.app/Contents/payload').read_text(), 'desktop fixture')
        log = (self.root/'hdiutil.log').read_text()
        self.assertIn('attach -readonly -nobrowse', log)
        self.assertIn('detach ', log)
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                         '--desktop-dir', str(self.target))
        self.assertEqual(len(list(self.target.glob('*.app'))), 1)

    def test_desktop_hash_mismatch_never_mounts(self):
        self.apps[0]['desktop']['sha256'] = '0' * 64
        self.save_catalog()
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                         '--desktop-dir', str(self.target), expected=1)
        self.assertFalse((self.root/'hdiutil.log').exists())
        self.assertFalse(self.target.exists())

    def test_desktop_missing_asset_is_optional(self):
        self.apps[0].pop('desktop')
        self.save_catalog()
        out = self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                               '--desktop-dir', str(self.target))
        self.assertIn('no desktop', out)
        self.assertFalse((self.root/'hdiutil.log').exists())

    def test_desktop_failure_paths(self):
        for extra in ({'ATTACH_FAIL': '1'}, {'MISSING_APP': '1'}, {'DETACH_FAIL': '1'}):
            self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                             '--desktop-dir', str(self.target), expected=1, extra=extra)
        self.assertIn('detach ', (self.root/'hdiutil.log').read_text())

    def test_copy_failure_detaches(self):
        real_ditto = shutil.which('ditto')
        self.write_stub('ditto', '''
import os, subprocess, sys
if sys.argv[1:3]==['-x','-k']: sys.exit(subprocess.call([REAL,*sys.argv[1:]]))
sys.exit(1)
'''.replace('REAL', repr(real_ditto)))
        self.run_install('--only', 'fake1', '--yes', '--skip-mcp', '--desktop',
                         '--desktop-dir', str(self.target), expected=1)
        self.assertIn('detach ', (self.root/'hdiutil.log').read_text())
        self.assertFalse((self.target/'Fake One.app').exists())

    def test_detect_only_changes_nothing(self):
        self.run_install('--detect-only', '--desktop', '--desktop-dir', str(self.target))
        self.assertFalse((self.root/'downloads').exists())
        self.assertFalse(Path(self.env['CRAFT_HOME']).exists())

    def test_invalid_args(self):
        self.run_install('--group', expected=1)
        self.run_install('--group', 'unknown', '--yes', expected=1)
        self.run_install('--only', 'unknown', '--yes', expected=1)
        self.run_install('--desktop', '--mcp-only', expected=1)


class PublicContractTests(unittest.TestCase):
    def test_catalog_and_groups(self):
        catalog = json.loads((REPO/'catalog/apps.json').read_text())
        groups = json.loads((REPO/'catalog/groups.json').read_text())['groups']
        apps = catalog['apps']
        self.assertEqual(len(apps), 13)
        self.assertEqual(len({a['name'] for a in apps}), 13)
        for a in apps:
            self.assertEqual(a['tag'], 'v' + a['version'])
            self.assertEqual(a['asset'], f"{a['name']}-cli-{a['version']}-macos-universal.zip")
            self.assertRegex(a['sha256'], r'^[a-f0-9]{64}$')
            self.assertEqual(a['asset_url'], f"https://github.com/{a['repo']}/releases/download/{a['tag']}/{a['asset']}")
            self.assertTrue(a['checksum_url'].endswith('/SHA256SUMS.txt'))
            self.assertEqual(a['mcp_args'][0], 'mcp')
            d = a['desktop']
            self.assertEqual(d['asset'], f"{a['name']}-{a['version']}-macos-universal.dmg")
            self.assertRegex(d['sha256'], r'^[a-f0-9]{64}$')
            self.assertEqual(d['asset_url'], f"https://github.com/{a['repo']}/releases/download/{a['tag']}/{d['asset']}")
        self.assertEqual(len(groups['creator']['apps']), 6)
        self.assertEqual(len(groups['office']['apps']), 7)
        self.assertEqual(set(groups['all']['apps']), {a['name'] for a in apps})

    def test_episode_one_commands_still_resolve(self):
        marketplace = json.loads((REPO/'.claude-plugin/marketplace.json').read_text())
        plugin = json.loads((REPO/'.claude-plugin/plugin.json').read_text())
        self.assertEqual(marketplace['name'], 'craft-studio-setup')
        entry = next(p for p in marketplace['plugins'] if p['name'] == 'craft-studio')
        self.assertEqual(plugin['name'], entry['name'])
        self.assertEqual(plugin['version'], '0.3.0')
        self.assertEqual(entry['version'], plugin['version'])
        self.assertTrue((REPO/entry['source']/entry['commands']/'craft-setup.md').is_file())
        self.assertEqual(plugin['repository'], 'https://github.com/qualixar/craft-studio-setup')
        guide = (REPO/'GUIDE-PROMPT.md').read_text()
        for command in ('/plugin marketplace add qualixar/craft-studio-setup',
                        '/plugin install craft-studio@craft-studio-setup', '/craft-setup'):
            self.assertIn(command, guide)
        readme = (REPO/'README.md').read_text()
        self.assertIn('git clone https://github.com/qualixar/craft-studio-setup.git', readme)
        self.assertIn('bash scripts/install.sh --group all --yes', readme)
        self.assertTrue(INSTALL.is_file())


if __name__ == '__main__':
    unittest.main(verbosity=2)
