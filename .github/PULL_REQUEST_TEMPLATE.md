## What this changes

<!-- One or two sentences. Link the issue if there is one. -->

## How you tested it

- [ ] `bash tests/test_install.sh` passes (temp HOME, no network)
- [ ] `shellcheck install.sh scripts/*.sh` and `ruff check .` are clean
- [ ] `python3 scripts/update_checksums.py --check` passes (run it without `--check` if you changed a script or the catalog)
- [ ] For catalog changes: I downloaded each new asset and its SHA-256 matches the upstream `SHA256SUMS.txt`

## Safety

- [ ] No `sudo`, no `eval`, no new download without a pinned SHA-256, HTTPS only
- [ ] Nothing outside the documented paths is written (see "What this changes on your Mac" in the README)
- [ ] The uninstaller removes anything new this change installs
