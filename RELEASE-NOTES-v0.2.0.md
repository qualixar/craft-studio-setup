# Release notes: v0.2.0

Prepared on 31 October 2026. Local changes only; no push, tag or publication.

## Changes

- Pin all 13 current macOS CLI ZIPs and matching desktop DMGs. Every SHA-256 comes from that release's SHA256SUMS.txt; all 13 CLI archives were independently downloaded and hashed, and all matched.
- Add `--desktop` and `--desktop-dir DIR`. The default stays CLI-only. Desktop installation verifies the hash before a read-only mount, stages the app copy, replaces the prior bundle and detaches. Failure or interruption restores the old bundle when promotion has not completed.
- Upgrade an older CLI instead of skipping every executable already installed. Validate the new binary's version before replacing the old CLI directory.
- Add `--verify-mcp`: initialize and list tools over stdio without Claude registration. Every existing catalog launch command and its extra arguments passed against the new binaries; no launch argument changes were needed.
- Preserve the MCP health check from ae665cf and report missing servers or health-command failures. Only servers approved for registration are checked.
- Fix interactive answers being consumed from the app-selection loop. Read caller stdin separately; EOF declines installation.
- Set both plugin manifests to 0.2.0. Update the setup prompt, desktop question, README, security/signing scope and changelog.

## Episode 1 compatibility

The exact names and commands remain:

```text
/plugin marketplace add qualixar/craft-studio-setup
/plugin install craft-studio@craft-studio-setup
/craft-setup
git clone https://github.com/qualixar/craft-studio-setup.git
bash scripts/install.sh --group all --yes
```

The offline compatibility test resolves marketplace name, plugin entry, relative source, command file and repository URL, checks these literal guide/README commands, and executes the unchanged `--group all --yes` installer command with fixture downloads and Claude. This is local compatibility evidence; the unpublished v0.2.0 plugin has not been installed from GitHub.

## Test results

```text
bash tests/test_install.sh
Ran 25 tests
OK

claude plugin validate .
Validation passed

shellcheck scripts/install.sh tests/test_install.sh
(exit 0, no diagnostics)

ruff check scripts/verify_mcp.py tests/test_install.py tests/test_mcp.py
All checks passed!

mypy scripts/verify_mcp.py tests/test_install.py tests/test_mcp.py
Success: no issues found in 3 source files
```

The suite uses temporary homes and application directories, fake curl/Claude/hdiutil commands, and ZIP/DMG fixtures. It needs no real network and never writes `/Applications` or real Claude settings. Tests cover CLI/DMG mismatch, hash-before-mount, default CLI-only, upgrades, repeated installs, copy/attach/detach failure, desktop replacement interruption, interactive acceptance/decline/EOF, health failures, exact film commands, and MCP errors, timeout, closed stdin and descendant cleanup.

The final process-group cleanup tests ran outside the restricted execution sandbox because it denies some signals to exited child process groups. Temporary fixture isolation remained in place.

## Real release checks

Host: macOS 26.6.2, Apple Silicon arm64. All checks below used a temporary HOME, explicit temporary Claude config location and absolute paths. No real Claude registration was performed.

The Office check ran the requested installer command against GitHub releases in a fresh temporary HOME:

```bash
HOME="$(mktemp -d)" bash scripts/install.sh --group office --yes --skip-mcp
```

Result: exit 0. All seven Office CLIs were downloaded by the installer, checked against their pins, extracted and linked. Each binary printed the expected version. Creator binaries were extracted from the separately downloaded and independently hashed archives for version/help/MCP smoke checks.

The final checker then ran `bash scripts/install.sh --group all --verify-mcp` in that isolated home. Result: exit 0; all 13 initialized using protocol 2024-11-05 and returned tools. No `.claude.json` was created. Full `claude mcp add` registration was tested with a fake Claude command only.

| App / pinned release | Version output (first line) | Independent CLI hash | Fresh Office install | MCP initialize / tools |
| --- | --- | --- | --- | --- |
| [photocraft](https://github.com/storytold/photocraft/releases/tag/v0.18.0) | `photocraft-cli 0.18.0 (8a87a457a, 2026-10-31)` | MATCH | Creator smoke check | PASS / 26 tools |
| [vectorcraft](https://github.com/storytold/vectorcraft/releases/tag/v0.19.0) | `vectorcraft-cli 0.19.0` | MATCH | Creator smoke check | PASS / 33 tools |
| [filmcraft](https://github.com/storytold/filmcraft/releases/tag/v0.15.0) | `filmcraft-cli 0.15.0` | MATCH | Creator smoke check | PASS / 17 tools |
| [lightcraft](https://github.com/storytold/lightcraft/releases/tag/v0.16.0) | `lightcraft-cli 0.16.0` | MATCH | Creator smoke check | PASS / 17 tools |
| [effectcraft](https://github.com/storytold/effectcraft/releases/tag/v0.19.0) | `effectcraft-cli 0.19.0` | MATCH | Creator smoke check | PASS / 27 tools |
| [soundcraft](https://github.com/storytold/soundcraft/releases/tag/v0.15.0) | `soundcraft-cli 0.15.0 (macos aarch64)` | MATCH | Creator smoke check | PASS / 17 tools |
| [pdfcraft](https://github.com/storytold/pdfcraft/releases/tag/v0.16.1) | `pdfcraft-cli 0.16.1` | MATCH | PASS | PASS / 17 tools |
| [wordcraft](https://github.com/storytold/wordcraft/releases/tag/v0.13.2) | `wordcraft-cli 0.13.2` | MATCH | PASS | PASS / 17 tools |
| [gridcraft](https://github.com/storytold/gridcraft/releases/tag/v0.14.2) | `gridcraft-cli 0.14.2` | MATCH | PASS | PASS / 22 tools |
| [deckcraft](https://github.com/storytold/deckcraft/releases/tag/v0.13.1) | `deckcraft-cli 0.13.1` | MATCH | PASS | PASS / 25 tools |
| [designcraft](https://github.com/storytold/designcraft/releases/tag/v0.15.2) | `designcraft-cli 0.15.2` | MATCH | PASS | PASS / 26 tools |
| [figcraft](https://github.com/storytold/figcraft/releases/tag/v0.13.1) | `figcraft-cli 0.13.1` | MATCH | PASS | PASS / 19 tools |
| [cadcraft](https://github.com/storytold/cadcraft/releases/tag/v0.15.1) | `cadcraft-cli 0.15.1 (660e15c9f494ce647e87de10adbb01a8786e0901)` | MATCH | PASS | PASS / 12 tools |

Each catalog entry links its tagged README and SHA256SUMS.txt source. `mcp --help` and the full catalog argument list were checked for every pinned binary. The existing `mcp` subcommand still works for all 13.

All 13 CLIs also passed `codesign --verify --strict` outside the restricted sandbox. A new notarization assessment with `spctl` was not performed; SIGNING.md keeps the old 22 October evidence clearly dated.

Real desktop sample: SoundCraft 0.15.0 downloaded from the pinned DMG URL, matched its hash, mounted read-only, copied `SoundCraft.app` into a temporary directory containing spaces, and detached successfully. Exit 0. The other 12 desktop hashes are pinned from upstream checksum files; their real DMGs were not mounted or opened.

## First-time viewer notes

- Python 3 is required. The installer points missing Python users to `xcode-select --install`; that Apple installation may need a separate download and user interaction.
- The CLI archives total 1.06 GB and unpack to 2.15 GB. Allow at least 4 GB free for the CLI installation and cache; desktop apps require more.
- `~/.local/bin` may need adding to PATH for commands typed in a new terminal. MCP uses absolute paths.
- A standard account may not be able to write `/Applications`. Use `--desktop-dir "$HOME/Applications"` and quit an existing app before replacing it.
- macOS can ask about downloaded software. Review the publisher in the prompt. These checks do not claim a fresh Gatekeeper/notarization result for every current app.
- The workspace flag is not a universal sandbox. FilmCraft, GridCraft and CADCraft have no folder restriction flags in this catalog; use scratch projects and review MCP permissions.
- A mismatch stops that download before extraction or mounting; apps installed earlier in the run remain. Re-running retries failed downloads and rechecks cached files.
- A desktop copy can succeed but detach can fail, for example when a file on the mounted volume is in use. The installer exits nonzero and reports the mount to eject in Finder.
- Windows installers exist upstream, but this repo is Mac-only and untested on Windows. Intel binaries were not executed; this run used Apple Silicon. Desktop launch/UI behavior, document round trips and the other 12 real DMG installations remain outside this check.

## Lead handoff

Source changes and verification are complete pending the final independent review verdict. The execution harness forbids this worker from touching Git branches, so creation of `release/v0.2.0` and the requested local conventional commit remain for the lead. Current history is unchanged. No push, tag or publication occurred.

Local evidence logs remain in `/tmp/craft-release-v020/`: release metadata, tagged READMEs, upstream checksum files, independent CLI hashes, version outputs, Office install output, final MCP JSON lines and the SoundCraft desktop install output. Test logs are in `/tmp/craft-tests-final-validated.log`.
