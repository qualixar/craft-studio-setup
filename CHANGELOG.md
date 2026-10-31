# Changelog

## 0.2.0 - 2026-10-31

- Pin all 13 macOS CLI releases from 31 October and their SHA256SUMS.txt hashes.
- Pin the matching desktop DMGs. Add optional `--desktop` installation and
  `--desktop-dir` for user or temporary Applications folders.
- Upgrade older CLIs instead of skipping any working installation.
- Read interactive answers from caller stdin, treat EOF as decline, and restore
  the previous desktop app if replacement is interrupted.
- Add `--verify-mcp` for direct initialization and tool-list checks without
  Claude registration. Preserve the existing MCP health check and report
  missing servers or health-command failures.
- MCP check cleanup: treat macOS EPERM on an already-exited process group as gone.
- Keep the Episode 1 marketplace, plugin, slash command and shell commands.
- Add offline ZIP/DMG/MCP fixtures and compatibility checks. Clarify Mac-only
  support and the availability of upstream Windows installers.
