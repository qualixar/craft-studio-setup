# Security

## Reporting a problem

Please report security problems privately through
[GitHub security advisories](https://github.com/qualixar/craft-studio-setup/security/advisories/new),
or by email to the maintainer listed in `.github/CODEOWNERS`. Do not open a
public issue for a security problem. Problems inside an app itself belong
with its maker, [Storytold](https://github.com/storytold).

## What the installer trusts

1. **The bootstrapper (`install.sh`)** is fetched from the release tag on
   `raw.githubusercontent.com` over HTTPS. Its own SHA-256 is printed in the
   README and the release notes, so you can download it, check it and read it
   before running it.
2. **The scripts and catalog it runs.** The bootstrapper downloads the tagged
   source tarball from `codeload.github.com` over HTTPS and checks the SHA-256
   of each file it will execute or read (`scripts/*.sh`, `scripts/*.py`,
   `catalog/*.json`) against a list embedded in itself. Only those files are
   copied out of the download into a clean folder and run from there, and the
   Python helpers run with `python3 -I`, so nothing else in the download can be
   executed or imported. One mismatch stops the run before anything is installed. GitHub generates the tarball on request,
   so this per-file check does not depend on the tarball's own bytes. If the
   release notes publish a tarball SHA-256, set `CRAFT_SETUP_TARBALL_SHA256`
   to check that as well.
3. **The apps.** Each CLI ZIP and desktop DMG is downloaded from the app's
   GitHub release over HTTPS (redirects must stay on HTTPS) and checked against
   the SHA-256 pinned in `catalog/apps.json`. The pins come from each release's
   `SHA256SUMS.txt`, and the CLI archives were also downloaded and hashed
   independently. A mismatch deletes the download and stops the run (exit 1)
   before anything is extracted or mounted.

A matching checksum proves the bytes are the ones that were pinned. It is not
a source or supply-chain audit of the apps.

## What it does not do

No `sudo`, no `eval` of downloaded text, no keychain access, no credentials,
no shell-profile edits, no telemetry. Every variable is quoted and every
script runs under `set -euo pipefail`. Changes are listed by `--dry-run` and
the one-line installer asks once before making them unless you pass `--yes`.

## Files and configuration it changes

| Path | What | Removed by uninstall |
| --- | --- | --- |
| `~/tools/craft/<app>/` | extracted CLI | yes |
| `~/tools/craft/.cache-zips/` | verified downloads | yes |
| `~/tools/craft/.craft-setup-state.json` | record of what was added | yes |
| `~/.local/bin/<app>-cli` | symlink to the CLI | yes (only links into `~/tools/craft`) |
| `~/craft-workspace/` | folder the apps may use, plus `setup-report.md` | no, your files stay |
| `~/.claude.json` (via `claude mcp add --scope user`) | one server per app | yes, only entries this installer added |
| `~/craft-workspace/.mcp.json` | only when the `claude` CLI is missing | yes |
| `~/Library/Application Support/Claude/claude_desktop_config.json` | one server per app, timestamped backup next to it | yes, only entries this installer added |
| `/Applications/<App>.app` | only with `--desktop` | yes, only apps it recorded |

Flags `--craft-home`, `--bin-dir`, `--workspace` and `--desktop-dir` move
these paths; pass the same flags to the uninstaller.

Config edits (`scripts/mcp_config.py`): invalid JSON is refused untouched; a
byte-for-byte backup is created exclusively (never through a symlink, mode
600) before the first change; an entry is added only under a free name, and
updated or removed only while it still equals what this installer recorded
writing. The new file is written to a temporary file, synced, and renamed into
place only if the original still holds the bytes that were read, so an edit
made by another program during the run is detected instead of overwritten
(a window of a few microseconds remains between that check and the rename). It is then read back; if any other key or
server changed, or the ownership record cannot be saved, the previous file is
put back and the run stops.

Uninstall removes a CLI folder only when the state file records it (or, for
v0.2.0 installs, when our link points into it), a Claude Code server only when
`claude mcp get` still shows the recorded command and arguments at user scope,
and a desktop app only when it is recorded.

## Limits of testing

Signing: all 13 pinned CLIs passed `codesign --verify --strict` on 31 October
2026 ([SIGNING.md](SIGNING.md)). A fresh `spctl` notarization assessment was
not run for these versions. The apps' runtime network traffic has not been
audited. Folder access varies by app: FilmCraft, GridCraft and CADCraft have
no folder restriction flags in this catalog, so the workspace is not a
universal sandbox. Use a scratch project with them.
