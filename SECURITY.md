# SECURITY.md — what the scripts touch, and what we did NOT verify

## What our scripts touch

- `scripts/install.sh` (the only installer) touches exactly four things:
  1. `$CRAFT_HOME` (default `~/tools/craft`): one folder per app with the unzipped CLI.
  2. `$CRAFT_BIN_DIR` (default `~/.local/bin`): one symlink per app CLI.
  3. The workspace folder (default `~/craft-workspace`, created): the folder the apps may read/write, plus `setup-report.md`.
  4. `claude mcp add --scope user` entries: one MCP server per app, removable with `claude mcp remove --scope user <name>`.
- No `sudo`, ever. No credentials asked for or stored. No keychain, no shell-profile edits (if `~/.local/bin` is not on PATH, the script tells you the export line; it does not add it). Downloads are https-only (`curl --proto '=https'`); the `CRAFT_CURL_PROTO` override exists only for the localhost test fixtures.
- To uninstall: delete `~/tools/craft/<app>`, remove the `~/.local/bin/<app>-cli` symlink, and run `claude mcp remove --scope user <name>` per app.

## What "nothing phones home" means here

It means **our scripts** (install.sh, the tests) make no network requests
except downloading the release zips from `github.com/storytold/<app>`. It does
**not** mean the Craft apps themselves are silent: **we never packet-captured
the 13 Craft CLIs**, so we make no claim about what network traffic the apps
generate at runtime. That check is explicitly untested — see below.

## Checksums: ours, and why

- Every pin in `catalog/apps.json` is **our own SHA-256**, computed 2026-10-22
  on the M5 from the zips in `~/tools/craft/zips/` that were smoke-tested here
  (see each entry's `pin_obtained`). Craft releases ship no verified checksum
  file, so our pins are the trust anchor.
- `install.sh` fails closed: expected vs actual mismatch → the bad download is
  deleted and the whole run aborts (exit 1). Verified by `tests/test_install.sh`
  (test 1).
- Repinning for a new version = update `version`/`tag`/`asset`/`asset_url`/
  `sha256`/`pin_obtained` in `catalog/apps.json` from a tested machine. Never
  copy a hash from a release page or chat without hashing the tested bytes.

## Signing

All 13 CLIs are signed by Developer ID Application: Learning Machines LLC and
`spctl --assess --type install` reports `accepted, source=Notarized Developer
ID`. Raw outputs: [SIGNING.md](SIGNING.md). Note: bare `spctl -a` (app-type
assessment) says "rejected (the code is valid but does not seem to be an app)"
— expected for CLI tools; the install-type assessment is the correct one.

## Explicitly NOT tested

- Packet capture / egress audit of any Craft CLI or MCP server.
- Windows (`winget` names, asset names) — marked not yet tested; `install.sh` refuses non-macOS.
- Supply-chain review of the Craft app sources beyond building/running the pinned zips.
- The `claude mcp add --scope user` flag surface across Claude Code versions (tested with the CLI on this machine, 2026-10-22).

## Report a problem

Checksum mismatch, unexpected prompt, or anything the installer did that this
file says it should not: open an issue at
`github.com/qualixar/craft-studio-setup` with `setup-report.md` attached (it
contains versions and fingerprints, no secrets).
