#!/usr/bin/env bash
# Offline fixtures only; never installs real apps or registers real MCP servers.
set -euo pipefail
exec python3 -m unittest discover -s "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" -p 'test_*.py' -v
