# Contributing

Thanks for helping. This repository is a small installer: it downloads the
Craft apps made by [Storytold](https://github.com/storytold), checks their
fingerprints, and connects them to Claude Code and Claude Desktop. Bugs inside
an app belong in that app's own repository.

## Ground rules

- macOS only. The scripts must run on the stock macOS bash 3.2 and the Python 3
  that ships with Apple's Command Line Tools (3.9). No `mapfile`, no
  third-party Python packages.
- No `sudo`, no `eval`, HTTPS only, and every download pinned to a SHA-256.
- Nothing is written outside the paths listed under "What this changes on your
  Mac" in the README. Anything new the installer adds, the uninstaller removes.
- Config files are edited by `scripts/mcp_config.py` only: backup first, keep
  every key we did not write, atomic write, read back and check.

## Run the checks

```bash
bash tests/test_install.sh          # whole suite: temporary HOME, fake downloads, fake claude
shellcheck install.sh scripts/*.sh tests/*.sh
ruff check .
python3 scripts/update_checksums.py --check
actionlint                          # if you changed .github/workflows
```

The tests never touch your real `~/.claude`, `~/.claude.json` or Claude Desktop
config. Keep it that way: new tests use the `Fixture` class in
`tests/test_install.py`, which sets `HOME` to a temporary folder.

## Changing a script or the catalog

The one-line installer checks the SHA-256 of every script and catalog file it
runs, against a list embedded in `install.sh`. After any change to
`scripts/*.sh`, `scripts/*.py` or `catalog/*.json`, stage your files and run:

```bash
git add -A
python3 scripts/update_checksums.py
```

It refreshes the list in `install.sh`, the `install.sh` fingerprint in the
README and release notes, and `SHA256SUMS`. CI fails if you forget.

## Pinning a new app release

1. Read the release's `SHA256SUMS.txt` on GitHub.
2. Download the macOS CLI ZIP and DMG yourself and hash them with
   `shasum -a 256`. Both numbers must match.
3. Update the entry in `catalog/apps.json` (version, tag, asset names, URLs,
   SHA-256 values, `pin_obtained`).
4. Run the real install for that app in a temporary HOME and `--verify-mcp`.
5. Note the change in `CHANGELOG.md`.

## Pull requests

Small and focused, with the test output in the description. The maintainer
(@varun369, see `.github/CODEOWNERS`) reviews every change. By contributing
you agree that your work is released under the MIT licence in `LICENSE`, and
you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
