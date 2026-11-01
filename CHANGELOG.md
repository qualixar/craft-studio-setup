# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2026-11-01

### Added

- One-line install pinned to the release tag:
  `curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- all`.
  The root `install.sh` downloads the tagged source over HTTPS, checks the
  SHA-256 of every script and catalog file it will run against a list
  embedded in itself, shows a dry-run plan and asks once before changing
  anything (`--yes` skips the question). It also runs from a git clone.
- Group aliases `adobe` (= `creator`) and `microsoft` (= `office`), usable as
  a first word or with `--group`.
- Claude Desktop support: servers are merged into
  `~/Library/Application Support/Claude/claude_desktop_config.json` with a
  timestamped backup first. Other servers and unknown keys are kept, a
  same-named server the installer did not write is left alone, the write is
  atomic and the JSON is read back and checked. Invalid JSON is refused with
  a clear message and the file is not touched.
- `--claude-code`, `--claude-desktop` and `--both`. By default Claude Code is
  always connected and Claude Desktop is connected when it is installed.
- Without the `claude` CLI, servers go to the workspace `.mcp.json` instead.
- `--dry-run` prints every file, folder, download and config change; nothing
  is written.
- `scripts/uninstall.sh` (also `bash -s -- uninstall`): removes the CLIs, the
  desktop apps and the MCP entries this installer recorded, and nothing else.
  A config file that nobody else edited is restored byte-for-byte from its
  first backup. Supports `--dry-run`.
- An installer state file (`~/tools/craft/.craft-setup-state.json`) that
  records what was added, so uninstall and re-runs know what is theirs.
- An automatic MCP handshake check (initialize + tools/list) at the end of
  every install; `--no-verify` skips it.
- `scripts/update_checksums.py` and a committed `SHA256SUMS`.
- CI on macOS 14 and macOS 15: shellcheck, ruff, the test suite, checksum
  freshness, and a real install of the office group in a temporary HOME
  through the piped bootstrapper, with MCP verification and uninstall.
- Logo, social preview, CONTRIBUTING, Code of Conduct (Contributor Covenant
  2.1), issue and pull request templates, CODEOWNERS and Dependabot for
  GitHub Actions.
- Tests for aliases, dry run, Claude Desktop merge, bad JSON, idempotency,
  uninstall and the bootstrapper's checksum check (50 tests in total).

### Changed

- Re-running is idempotent: when nothing needs doing, the installer says
  "Already installed, nothing changed." and writes nothing.
- Claude Code registration no longer removes a same-named server it did not
  add; it leaves it alone and says so.
- README rewritten: three copy-paste commands, Claude Code and Claude Desktop
  steps, exact paths changed, uninstall, a compatibility table, known issues
  with fixes and troubleshooting.

### Removed

- Stray `.DS_Store` and tool caches from the working tree; they are now
  ignored.

## [0.2.0] - 2026-10-31

### Added

- Pin all 13 macOS CLI releases from 31 October and their SHA256SUMS.txt hashes.
- Pin the matching desktop DMGs. Optional `--desktop` installation and
  `--desktop-dir` for user or temporary Applications folders.
- `--verify-mcp` for direct initialization and tool-list checks without
  Claude registration.
- Offline ZIP/DMG/MCP fixtures and compatibility checks.

### Changed

- Upgrade older CLIs instead of skipping any working installation.
- Read interactive answers from caller stdin, treat EOF as decline, and
  restore the previous desktop app if replacement is interrupted.
- MCP check cleanup: treat macOS EPERM on an already-exited process group as gone.
- Keep the Episode 1 marketplace, plugin, slash command and shell commands.

## [0.1.0] - 2026-10-22

### Added

- First draft of the Craft Studio setup plugin, guided `/craft-setup`
  command and checksum-verified installer.

[Unreleased]: https://github.com/qualixar/craft-studio-setup/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/qualixar/craft-studio-setup/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/qualixar/craft-studio-setup/compare/c47d8e5...v0.2.0
[0.1.0]: https://github.com/qualixar/craft-studio-setup/commit/c47d8e5
