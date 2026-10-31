# Security and installer scope

## Files and configuration

`scripts/install.sh` uses:

- `$CRAFT_HOME` (default `~/tools/craft`): extracted CLI folders and verified download cache.
- `$CRAFT_BIN_DIR` (default `~/.local/bin`): one symlink per CLI.
- The workspace (default `~/craft-workspace`): created for the apps and `setup-report.md`.
- `claude mcp add --scope user`: one server per selected app, unless `--skip-mcp` is set.
- With `--desktop` only: temporary read-only DMG mounts and `.app` copies in `/Applications`, or the directory supplied with `--desktop-dir`. Existing apps with the same name are replaced. Quit them before updating.

There is no `sudo`, credential storage, keychain access or shell-profile edit.
Downloads and redirects use HTTPS. `CRAFT_CURL_PROTO` is a developer override;
the offline tests replace curl entirely and do not use a network server.

`--verify-mcp` sends initialize and tools/list directly to installed CLIs. It
creates the workspace if needed and stops the processes afterwards. It does
not register servers or write Claude configuration. Runtime filesystem access
still depends on each app's supported launch flags. FilmCraft, GridCraft and
CADCraft currently have no folder restriction flags in this catalog.

To uninstall a CLI, remove its `~/tools/craft/<app>` directory and
`~/.local/bin/<app>-cli` symlink, then run
`claude mcp remove --scope user <name>`. Desktop apps can be removed separately
from the Applications directory you chose. This does not delete your documents.

## Checksums

The v0.2.0 catalog pins hashes from each 31 October 2026 release's
`SHA256SUMS.txt`. Every entry links its checksum source. All 13 CLI ZIPs were
also downloaded and hashed independently; every hash matched. Desktop DMG
pins come from the same upstream checksum files; SoundCraft's DMG was also
downloaded, hashed and installed into a temporary target for verification.

A mismatch removes the bad download and aborts the run with exit 1 before
extracting or mounting it. Earlier successful app installs remain. The tests
exercise CLI and DMG mismatches without real network access.

For a new release, update the version, tag, asset names, URLs, SHA-256 values
and provenance in the catalog, including the desktop entry when available.
Download and independently hash the CLI bytes before accepting the new pins.
A matching checksum establishes equality with the pinned bytes; it does not
replace a source or supply-chain audit.

## Signing and limits of testing

All 13 pinned CLIs passed `codesign --verify --strict` on 31 October 2026.
[SIGNING.md](SIGNING.md) preserves the older 22 October notarization checks
and distinguishes them from the current signature verification. A fresh
`spctl` notarization assessment was not performed for v0.2.0.

The installer downloads from the upstream GitHub releases. We have not
packet-captured the apps or audited their runtime network traffic. The tests
use temporary homes, fake downloads, fake DMGs and a fake Claude command.
Windows is untested here and the installer refuses non-macOS systems. The
current real install and MCP checks ran on macOS 26.6.2, Apple Silicon; the
Intel slice of the universal binaries was not executed. Real user-scope Claude
registration was not changed during the v0.2.0 checks.

## Report a problem

Open an issue at [qualixar/craft-studio-setup](https://github.com/qualixar/craft-studio-setup/issues).
Include the failing app, installer output and version/fingerprint lines from
`setup-report.md`. Review local paths before sharing the report.
