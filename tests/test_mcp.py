"""Exercise MCP handshake success, protocol errors, exit and timeout offline."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('verify_mcp', REPO/'scripts/verify_mcp.py')
assert spec is not None and spec.loader is not None
verify_mcp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_mcp)


class MCPTests(unittest.TestCase):
    def check(self, source, timeout=3):
        return verify_mcp.check_server([sys.executable, '-u', '-c', source], timeout=timeout)

    def test_initialize_and_tools(self):
        result = self.check('''
import json,sys
for line in sys.stdin:
    m=json.loads(line)
    if m['method']=='initialize':
        r={'protocolVersion':'2024-11-05','capabilities':{},'serverInfo':{'name':'fixture','version':'1'}}
    elif m['method']=='tools/list': r={'tools':[{'name':'fixture'}]}
    else: continue
    print(json.dumps({'jsonrpc':'2.0','id':m['id'],'result':r}),flush=True)
''')
        self.assertEqual(result, {'protocol': '2024-11-05', 'tools': 1})

    def test_error(self):
        with self.assertRaisesRegex(RuntimeError, 'returned an error'):
            self.check('import sys; sys.stdin.readline(); print(\'{"id":1,"error":{"code":-1}}\',flush=True)')

    def test_early_exit(self):
        with self.assertRaises((RuntimeError, BrokenPipeError)):
            self.check('raise SystemExit(0)')

    def test_timeout_kills_child(self):
        with tempfile.TemporaryDirectory(prefix='craft-timeout-') as tmp:
            pidfile = Path(tmp)/'pid'
            source = f"import os,pathlib,time; pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(60)"
            with self.assertRaises(TimeoutError):
                self.check(source, timeout=0.5)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pidfile.read_text()), 0)

    def test_descendants_are_killed_after_launcher_exit(self):
        for ignore_term in (False, True):
            with self.subTest(ignore_term=ignore_term), tempfile.TemporaryDirectory(prefix='craft-child-') as tmp:
                pidfile = Path(tmp)/'pid'
                child = (
                    'import os,pathlib,signal,time; '
                    + ('signal.signal(signal.SIGTERM, signal.SIG_IGN); ' if ignore_term else '')
                    + f'pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(60)'
                )
                launcher = f"""
import pathlib, subprocess, sys, time
subprocess.Popen([sys.executable, '-c', {child!r}], stdin=subprocess.DEVNULL,
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
while not pathlib.Path({str(pidfile)!r}).exists(): time.sleep(0.01)
"""
                with self.assertRaises(RuntimeError):
                    self.check(launcher)
                pid = int(pidfile.read_text())
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    status = subprocess.run(['ps', '-p', str(pid), '-o', 'stat='],
                                            capture_output=True, text=True).stdout.strip()
                    if not status or status.startswith('Z'):
                        break
                    time.sleep(0.02)
                else:
                    self.fail('MCP descendant survived cleanup')

    def test_invalid_response_shapes(self):
        for message in ('null', '[]', '{"id":1,"result":null}', '{"id":1,"result":[]}'):
            with self.subTest(message=message), self.assertRaises(RuntimeError):
                self.check(f'import sys,time; sys.stdin.readline(); print({message!r},flush=True); time.sleep(60)')

    def test_broken_stdin_still_reaps_child(self):
        with tempfile.TemporaryDirectory(prefix='craft-pipe-') as tmp:
            pidfile = Path(tmp)/'pid'
            source = f"""
import json, os, pathlib, sys, time
sys.stdin.readline()
os.close(0)
pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid()))
print(json.dumps({{'id': 1, 'result': {{'protocolVersion': '2024-11-05',
      'capabilities': {{}}, 'serverInfo': {{'name': 'fixture', 'version': '1'}}}}}}), flush=True)
time.sleep(60)
"""
            with self.assertRaises(BrokenPipeError):
                self.check(source)
            with self.assertRaises(ProcessLookupError):
                os.kill(int(pidfile.read_text()), 0)

    def test_verify_flag_never_registers(self):
        with tempfile.TemporaryDirectory(prefix='craft-verify-') as tmp:
            r = subprocess.run(['/bin/bash', str(REPO/'scripts/install.sh'), '--verify-mcp',
                                '--only', 'wordcraft', '--bin-dir', tmp, '--workspace', tmp],
                               capture_output=True, text=True, timeout=10)
            self.assertEqual(r.returncode, 2, r.stdout+r.stderr)
            self.assertIn('"status": "FAIL"', r.stdout)
            self.assertNotIn('claude mcp add', r.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
