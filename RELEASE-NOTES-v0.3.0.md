# Craft Studio Setup v0.3.0

Released 2026-11-01. macOS only (Apple silicon and Intel). The 13 app pins are
unchanged from v0.2.0 (31 October 2026 releases by
[Storytold](https://github.com/storytold)).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- all
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- adobe
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- microsoft
```

Uninstall: `... | bash -s -- uninstall`. Preview anything with `--dry-run`.

## What is new

- One-line, tag-pinned install that checks every script and catalog file it
  runs against SHA-256 values embedded in `install.sh`, shows the plan and asks
  once before changing anything.
- `adobe` and `microsoft` group aliases.
- Claude Desktop support: a backed-up, atomic, read-back-checked merge into
  `claude_desktop_config.json` that keeps every other server and setting.
- `--claude-code`, `--claude-desktop`, `--both`; workspace `.mcp.json`
  fallback when the `claude` CLI is missing.
- `--dry-run`, idempotent re-runs ("Already installed, nothing changed."),
  and `scripts/uninstall.sh`, which removes only what this installer added.
- An MCP handshake check (initialize + tools/list) after every install.
- CI on macOS 14 and 15, 61 offline tests, and community files.

Full list: [CHANGELOG.md](CHANGELOG.md).

## Checksums

`install.sh` at this tag:

<!-- INSTALL-SH-SHA256 -->`4347854b4476f1728c22c35d7957e593de87b709646b9331f1da69cb094e8ba3`<!-- /INSTALL-SH-SHA256 -->

Every file in the repository: [SHA256SUMS](SHA256SUMS).

Source tarball (optional extra check). GitHub builds it on request, so it is
measured after the tag is pushed and published in the GitHub release text,
not in this file:

```bash
curl -fsSL https://codeload.github.com/qualixar/craft-studio-setup/tar.gz/refs/tags/v0.3.0 | shasum -a 256
```

Anyone can then pin it: `CRAFT_SETUP_TARBALL_SHA256=<that value>` before
`bash -s -- all`. The per-file check runs either way.

## End-to-end verification on a real Mac

Machine: macOS 26.6.2 (build 25G83), Apple silicon (arm64), 1 November 2026
(final run after the review fixes; download times depend on the network),
Claude Code 2.1.304. Every run used a temporary home folder, so the real
`~/.claude`, `~/.claude.json` and Claude Desktop config were never read or
written. Real downloads from the pinned GitHub releases, real `claude mcp add`
in the temporary home, real MCP servers.

Set-up, with `T` a fresh temporary folder:

```bash
export HOME="$T/home"; unset CLAUDE_CONFIG_DIR
git archive --prefix=craft-studio-setup-0.3.0/ -o "$T/source.tar.gz" "$(git write-tree)"
export CRAFT_SETUP_TARBALL="$T/source.tar.gz"   # stands in for the GitHub download
COMMON=(--craft-home "$T/home/tools/craft" --bin-dir "$T/home/.local/bin" --workspace "$T/workspace")
boot() { bash -s -- "$@" < install.sh; }        # same as curl ... | bash -s --
```

A realistic Claude Desktop config was placed at
`$T/home/Library/Application Support/Claude/claude_desktop_config.json` first:
two existing servers (`filesystem` via npx, `github` via docker with an `env`
block holding an example value), plus `globalShortcut` and `preferences` keys.

| Step | Command | Result |
| --- | --- | --- |
| 1 | `boot all --dry-run --both "${COMMON[@]}"` | exit 0, 10 s. Listed all 13 downloads with URL and SHA-256, every folder, link, `claude mcp add` line and the Desktop config change. "DRY RUN complete: 27 change(s) would be made; nothing was changed." |
| 2 | `boot microsoft --yes --both "${COMMON[@]}"` | exit 0, 122 s. "Verified 6 files against the checksums in this script (v0.3.0)." 7 CLIs downloaded, checksum OK, installed; 7 `claude mcp add --scope user`; Desktop config backed up and 7 servers added; `claude mcp list` showed all 7 "✔ Connected"; handshake PASS for all 7. "DONE. 15 change(s) made." |
| 3 | `boot adobe --yes --both "${COMMON[@]}"` | exit 0, 110 s. Same for the 6 creator apps ("DONE. 13 change(s) made."); the 7 office servers in the Desktop config were kept. |
| 4 | `boot microsoft --yes --both "${COMMON[@]}"` (again) | exit 0, 6 s. Every app "already installed ... nothing changed", every server "already registered", Desktop config "nothing to change". "Already installed, nothing changed." |
| 5 | `bash scripts/install.sh all --verify-mcp "${COMMON[@]}"` | exit 0. All 13 PASS (protocol 2024-11-05). Tools: photocraft 26, vectorcraft 33, filmcraft 17, lightcraft 17, effectcraft 27, soundcraft 17, pdfcraft 17, wordcraft 17, gridcraft 22, deckcraft 25, designcraft 26, figcraft 19, cadcraft 12. |
| 6 | `claude mcp list` (from an empty folder, temporary home) | exit 0. All 13 servers "✔ Connected". |
| 7 | `boot uninstall --dry-run "${COMMON[@]}"` | exit 0. Listed every folder, link, Claude Code entry and Desktop entry it would remove. "DRY RUN complete: nothing was changed." |
| 8 | `boot uninstall --yes "${COMMON[@]}"` | exit 0, 16 s. 13 Claude Code servers removed, 13 Desktop entries removed, "MCP config: restored byte-for-byte from ...craft-backup-...", 13 links and folders removed, `~/tools/craft` removed. "Uninstall complete (40 item(s) removed)." |
| 9 | `cmp` of the Desktop config against the copy taken before step 2 | byte-identical. `~/.claude.json` in the temporary home lists no MCP servers. The workspace was kept. |

Desktop app path, separately, in another temporary home:
`boot adobe --only soundcraft --desktop --desktop-dir "$T/Applications" --skip-mcp --yes`
verified the DMG checksum, mounted it read-only, copied `SoundCraft.app`,
detached it ("DONE. 2 change(s) made."). `boot uninstall --only soundcraft --yes`
removed the app, link and folder; the Applications folder was left empty.

The end-to-end table above was re-run after the review fixes, with the same
results. A bug found by the first run and fixed before release: `claude mcp get` was run in
the caller's folder, so a project `.mcp.json` there (with servers of the same
names) made the installer skip Claude Code registration. The installer now
runs every `claude` command from an empty temporary folder; a regression test
covers it.

## Tests

`bash tests/test_install.sh`: 61 tests, all passing on the machine above, in
temporary home folders with fake downloads and a fake `claude`. They cover
aliases, dry run (no file under HOME changes), the Claude Desktop merge (other
servers and unknown keys kept, backup made, same-named foreign entry left
alone, empty file, four kinds of bad JSON refused untouched), idempotency,
uninstall (only our entries, byte-for-byte restore, later user edits kept,
decline changes nothing), the workspace `.mcp.json` fallback, a dead MCP
server (exit 2), the bootstrapper (pipe install, uninstall, dry run, no
terminal, tampered files, tarball pin) and checksum freshness.
`shellcheck`, `ruff` and `actionlint` are clean.

## Independent review (Codex, gpt-6.1-sol, read-only)

Twelve findings on the first v0.3.0 commit. A second read-only pass on the
fixes marked nine fixed and three incomplete (3, 6 and 12); those were then
completed as described below. Each fix has a test where one is practical.

| # | Finding | Fix |
| --- | --- | --- |
| 1 | Unlisted files in the downloaded tarball (for example a planted `scripts/json.py`) could be imported by the checked Python helpers | The bootstrapper copies only the listed files into a clean folder, checks them there and runs only from it; every Python helper runs with `python3 -I`. Test: planted modules never run. |
| 2 | Uninstall removed any catalog-named folder under `~/tools/craft` | CLI installs are recorded; uninstall removes a folder only when recorded, or when it is the target of our v0.2.0 link. Test: a hand-made folder is kept. |
| 3 | Uninstall removed Claude Code servers edited after install | It reads the exact user-scope entry from Claude Code's own config file (command, each argument, no added environment) and falls back to `claude mcp get` text; anything it cannot confirm is left alone. Tests added. |
| 4 | An identical pre-existing Claude Desktop entry was adopted and later removed | Identical entries the installer did not write are reported and never adopted. Test added. |
| 5 | A re-run could overwrite user edits to an entry the installer wrote | Entries are updated only while they still equal the recorded value. Test added. |
| 6 | A config edited by another program during the run could be overwritten | The rename happens only if the file still holds the bytes that were read; otherwise nothing is written and the run asks you to retry. A very short window remains between that check and the rename. A rollback after a failed check also restores only if the file still holds what this run wrote. Test added. |
| 7 | Backups were created with a check-then-write that follows symlinks | Backups use exclusive, no-follow creation with mode 600. Test added. |
| 8 | The byte-for-byte restore was not atomic | It now goes through the same synced temporary file and rename. |
| 9 | Config change and ownership record were not saved together | If the record cannot be saved, the previous config is put back. |
| 10 | A failed desktop-app record could still report success | It now stops with an error that names the app. |
| 11 | A crashed MCP checker could pass silently | Every app needs its own PASS line; anything else, or a non-zero checker exit, is a failure. |
| 12 | A failed `claude mcp remove` was reported as "already gone" and forgotten | A server counts as gone only when `claude mcp get` says "No MCP server named"; any other lookup error, or a failed removal, keeps the record and uninstall exits 1. Tests added. |

## Not verified

- CI on GitHub's macOS 14 and 15 runners runs after the push; it has not run yet.
- Intel Macs: the CLIs are universal binaries, but the Intel half was not run.
- A real Claude Desktop app loading the merged config (the merge was checked
  as a file; the servers themselves were checked with the MCP handshake and
  through Claude Code).
- A fresh macOS user account; the runs used a temporary home folder instead.
