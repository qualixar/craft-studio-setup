#!/usr/bin/env python3
"""Check stdio MCP initialization without writing any Claude configuration."""
import argparse
from contextlib import suppress
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import tempfile
import time


def check_server(command, timeout=30):
    """Initialize, acknowledge, then list tools; stop the child on every exit path."""
    with tempfile.TemporaryFile() as errors:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, start_new_session=True)
        selector = selectors.DefaultSelector()
        selector.register(process.stdout, selectors.EVENT_READ)
        buffered = b''
        deadline = time.monotonic() + timeout

        def send(message):
            process.stdin.write(json.dumps(message).encode() + b'\n')
            process.stdin.flush()

        def response(request_id):
            nonlocal buffered
            while True:
                while b'\n' in buffered:
                    line, buffered = buffered.split(b'\n', 1)
                    if not line.strip():
                        continue
                    message = json.loads(line)
                    if not isinstance(message, dict):
                        raise RuntimeError('MCP response must be an object')
                    if message.get('id') == request_id:
                        if 'error' in message:
                            raise RuntimeError(f'MCP request {request_id} returned an error')
                        result = message.get('result')
                        if not isinstance(result, dict):
                            raise RuntimeError('MCP result must be an object')
                        return result
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(remaining):
                    raise TimeoutError('MCP handshake timed out')
                chunk = os.read(process.stdout.fileno(), 65536)
                if not chunk:
                    raise RuntimeError('MCP server exited before responding')
                buffered += chunk

        try:
            send({'jsonrpc': '2.0', 'id': 1, 'method': 'initialize',
                  'params': {'protocolVersion': '2024-11-05', 'capabilities': {},
                             'clientInfo': {'name': 'craft-setup-check', 'version': '0.2.0'}}})
            result = response(1)
            if not (isinstance(result.get('protocolVersion'), str)
                    and isinstance(result.get('capabilities'), dict)
                    and isinstance(result.get('serverInfo'), dict)):
                raise RuntimeError('MCP initialize response is incomplete')
            send({'jsonrpc': '2.0', 'method': 'notifications/initialized'})
            send({'jsonrpc': '2.0', 'id': 2, 'method': 'tools/list', 'params': {}})
            tools = response(2).get('tools')
            if not isinstance(tools, list):
                raise RuntimeError('MCP tools/list response is incomplete')
            return {'protocol': result['protocolVersion'], 'tools': len(tools)}
        finally:
            try:
                selector.close()
                for stream in (process.stdin, process.stdout):
                    with suppress(BrokenPipeError):
                        stream.close()
            finally:
                # The group can outlive its launcher. Signal it even if the
                # direct child has exited, then kill any remaining descendants.
                with suppress(ProcessLookupError, PermissionError):
                    os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=0.5)
                except subprocess.TimeoutExpired:
                    pass
                finally:
                    with suppress(ProcessLookupError, PermissionError):
                        os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', required=True, type=Path)
    parser.add_argument('--bin-dir', required=True, type=Path)
    parser.add_argument('--workspace', required=True, type=Path)
    parser.add_argument('--apps', required=True, help='newline-separated catalog names')
    args = parser.parse_args()
    catalog = {a['name']: a for a in json.loads(args.catalog.read_text())['apps']}
    args.workspace.mkdir(parents=True, exist_ok=True)
    failed = False
    for name in args.apps.splitlines():
        app = catalog[name]
        command = [str(args.bin_dir / app['binary']),
                   *[v.replace('{{WORKSPACE}}', str(args.workspace)) for v in app['mcp_args']]]
        try:
            result = check_server(command)
            print(json.dumps({'app': name, 'status': 'PASS', **result}), flush=True)
        except (OSError, ValueError, KeyError, RuntimeError, TimeoutError) as error:
            failed = True
            print(json.dumps({'app': name, 'status': 'FAIL', 'error': str(error)}), flush=True)
    return 2 if failed else 0


if __name__ == '__main__':
    raise SystemExit(main())
