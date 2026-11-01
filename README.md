<p align="center">
  <img src="media/logo.svg" alt="Craft Studio Setup logo: seven app tiles wired into one connector" width="128" height="128">
</p>

<h1 align="center">Craft Studio Setup</h1>

<p align="center">
  <strong>Free Microsoft Office and Adobe alternatives for your Mac, connected to Claude Code and Claude Desktop in one command.</strong>
</p>

<p align="center">
  <a href="https://github.com/qualixar/craft-studio-setup/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/qualixar/craft-studio-setup/ci.yml?branch=main&label=CI"></a>
  <a href="https://github.com/qualixar/craft-studio-setup/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/qualixar/craft-studio-setup?sort=semver"></a>
  <a href="LICENSE"><img alt="Licence: MIT" src="https://img.shields.io/github/license/qualixar/craft-studio-setup"></a>
  <img alt="Platform: macOS" src="https://img.shields.io/badge/platform-macOS-141413">
  <a href="https://github.com/qualixar/craft-studio-setup/stargazers"><img alt="GitHub stars" src="https://img.shields.io/github/stars/qualixar/craft-studio-setup?style=flat"></a>
</p>

This repository installs thirteen free, open source desktop apps made by
[Storytold](https://github.com/storytold) and connects them to Claude over
MCP (Model Context Protocol), so you can ask Claude to write the Word file,
fill the Excel sheet, build the PowerPoint deck or stamp the PDF for you. If
you have been looking for a free Microsoft Office alternative, a free Excel
alternative, a free PowerPoint alternative or a free PDF editor for Mac that
an AI assistant can actually operate, this is a working Claude Code MCP setup
and Claude Desktop MCP setup for an open source office suite, with every
download checked against a pinned SHA-256 before anything is installed.

If this saved you a licence fee, a ⭐ helps others find it.

## Install

You need a Mac (Apple silicon or Intel) and Apple's command line tools, which
provide `python3` (`xcode-select --install` if you have never installed
them). Open the Terminal app, paste one of these lines and press Return. It
shows exactly what it will change and asks once before doing anything.

**Everything (all 13 apps):**

```bash
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- all
```

**The Adobe-style apps (6):**

```bash
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- adobe
```

**The Microsoft-style apps (7):**

```bash
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- microsoft
```

| Command | Installs | Downloads (CLIs) |
| --- | --- | --- |
| `all` | all 13 apps below | about 1.1 GB |
| `adobe` | PhotoCraft, LightCraft, VectorCraft, EffectCraft, FilmCraft, SoundCraft | about 520 MB |
| `microsoft` | WordCraft, GridCraft, DeckCraft, PdfCraft, DesignCraft, FigCraft, CADCraft | about 545 MB |

Add options after the group word: `--dry-run` shows the plan and changes
nothing, `--yes` skips the question, `--only gridcraft` installs one app,
`--desktop` also installs the desktop apps so you can open the files yourself,
and `--claude-code`, `--claude-desktop` or `--both` choose what to connect.
Keep at least 4 GB of free disk space. Each line is pinned to the `v0.3.0`
tag, so it always installs the same, checked versions.

Prefer not to pipe a script into your shell? Clone and run it instead:

```bash
git clone https://github.com/qualixar/craft-studio-setup.git
cd craft-studio-setup
bash install.sh all          # or: bash scripts/install.sh --group all --yes
```

## The apps and what they stand in for

The apps are made by [Storytold](https://github.com/storytold) and released
under the Apache 2.0 licence. Microsoft, Adobe and the other product names are
used only to say what each app is comparable to; this project is not
affiliated with or endorsed by any of them.

| App | Stands in for | Group | Pinned version |
| --- | --- | --- | --- |
| [PhotoCraft](https://github.com/storytold/photocraft) | Adobe Photoshop | adobe | 0.18.0 |
| [LightCraft](https://github.com/storytold/lightcraft) | Adobe Lightroom | adobe | 0.16.0 |
| [VectorCraft](https://github.com/storytold/vectorcraft) | Adobe Illustrator | adobe | 0.19.0 |
| [EffectCraft](https://github.com/storytold/effectcraft) | Adobe After Effects | adobe | 0.19.0 |
| [FilmCraft](https://github.com/storytold/filmcraft) | Adobe Premiere Pro | adobe | 0.15.0 |
| [SoundCraft](https://github.com/storytold/soundcraft) | a music studio (DAW) | adobe | 0.15.0 |
| [WordCraft](https://github.com/storytold/wordcraft) | Microsoft Word | microsoft | 0.13.2 |
| [GridCraft](https://github.com/storytold/gridcraft) | Microsoft Excel | microsoft | 0.14.2 |
| [DeckCraft](https://github.com/storytold/deckcraft) | Microsoft PowerPoint | microsoft | 0.13.1 |
| [PdfCraft](https://github.com/storytold/pdfcraft) | Adobe Acrobat | microsoft | 0.16.1 |
| [DesignCraft](https://github.com/storytold/designcraft) | Adobe InDesign | microsoft | 0.15.2 |
| [FigCraft](https://github.com/storytold/figcraft) | Figma | microsoft | 0.13.1 |
| [CADCraft](https://github.com/storytold/cadcraft) | AutoCAD | microsoft | 0.15.1 |

The `microsoft` group is the office set: documents, spreadsheets, slides,
PDFs, page layout, interface mock-ups and floor plans. Fingerprints, download
links and MCP launch arguments for every app are in
[catalog/apps.json](catalog/apps.json).

## Use the apps from Claude Code

1. Run one of the install commands above. When the `claude` command is on
   your Mac, each app is added with `claude mcp add --scope user`, so it works
   in every folder.
2. Open a new Claude Code session (`claude` in Terminal) and type `/mcp`. The
   apps you installed are listed as connected.
3. Ask for something, for example: "Make a one-page proposal as a Word file
   in ~/craft-workspace, then read it back to me."

If the `claude` command is not installed, the servers are written to
`~/craft-workspace/.mcp.json` instead. Open Claude Code in that folder and
approve them when it asks.

## Use the apps from Claude Desktop

1. Install Claude Desktop first, then run one of the install commands. When
   Claude Desktop is installed, it is connected automatically (add
   `--claude-desktop` to connect it without Claude Code, or `--both` to force
   both).
2. The installer backs up
   `~/Library/Application Support/Claude/claude_desktop_config.json`, adds one
   entry per app, keeps every other server and setting, and checks the file
   afterwards. It prints what it added.
3. Quit Claude Desktop completely (Claude > Quit Claude, or Cmd+Q) and open
   it again. The apps appear under the tools button in a new chat.

## What this changes on your Mac

Run any command with `--dry-run` to see this list for your own Mac before
anything happens.

| Path | What goes there |
| --- | --- |
| `~/tools/craft/<app>/` | each app's command-line tool |
| `~/tools/craft/.cache-zips/` | the verified downloads |
| `~/tools/craft/.craft-setup-state.json` | a record of what this installer added (used by uninstall) |
| `~/.local/bin/<app>-cli` | a shortcut to each tool |
| `~/craft-workspace/` | the folder the apps may use, and `setup-report.md` |
| `~/.claude.json` | Claude Code's user settings: one MCP entry per app, added by `claude mcp add` |
| `~/Library/Application Support/Claude/claude_desktop_config.json` | Claude Desktop: one MCP entry per app, plus a `.craft-backup-<date>` copy beside it |
| `~/craft-workspace/.mcp.json` | only when the `claude` command is missing |
| `/Applications/<App>.app` | only with `--desktop` |

No `sudo`, no password prompt, no changes to your shell profile. Running the
same command again changes nothing and says "Already installed, nothing
changed."

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh | bash -s -- uninstall
```

From a clone: `bash scripts/uninstall.sh` (add `--dry-run` to preview). It
removes the tools, the desktop apps it installed and the MCP entries it added,
and nothing else. Servers you added yourself, other settings and your
workspace files stay. If nobody else edited the Claude Desktop config since
the install, it is restored byte-for-byte from the backup. Use `adobe` or
`microsoft` after `uninstall` to remove one group, and `--keep-desktop` to
keep the desktop apps.

## Compatibility

| Tested | Result | Date |
| --- | --- | --- |
| macOS 26.6.2, Apple silicon (arm64) | full install of all 13 CLIs from the pinned releases, MCP handshake and tool list for each, Claude Code user-scope registration, Claude Desktop config merge and uninstall, all in a temporary home folder | 1 November 2026 |
| macOS 14 and macOS 15 (GitHub Actions runners) | lint, the test suite, and a real install of the `microsoft` group with MCP checks and uninstall, on every push | see the CI badge |

The 13 app versions in the table above are the ones tested. The CLIs are
universal binaries; the Intel half was not run on Intel hardware. Windows and
Linux are not supported by this installer. The apps publish their own Windows
and Linux builds on their release pages.

## Known issues

These are behaviours of the pinned app versions, found while making the
ArtCraft Episode 2 film and reproduced three times each on 31 October 2026.
The habit that catches all of them: ask Claude to open the finished file and
read it back (row counts, formulas, slide count, page count) before you send
it to anyone.

1. **GridCraft drops rows from very large sheets.** Importing a sheet with
   about one million XML elements (here, more than about 47,000 rows of 8
   columns) keeps only part of it, prints a warning, and still exports with
   success. Fix: split big data across several sheets (40k / 40k / 20k rows
   worked for 100,000 rows) and count the rows after saving. Upstream:
   [gridcraft#2819](https://github.com/storytold/gridcraft/issues/2819).
2. **GridCraft formula fill can produce a $0.00 column.** `range.fill` writes
   shifted references when the active cell is not the first cell of the
   range. Fix: select the range with its first cell active before filling, or
   set each formula, then read the formulas and values back.
3. **DesignCraft ignores styling of existing text right after creating a
   frame.** Formatting at a caret applies only to text typed next. Fix: select
   the text frame first (`selection.set`), then style it. Upstream:
   [designcraft#289](https://github.com/storytold/designcraft/issues/289)
   (closed; the "nothing changed" signal it asked for was not added).
4. **WordCraft carries bold into the next table cell.** Fix: turn bold off
   before typing the body text.
5. **DeckCraft adds an empty first slide.** A new deck starts with one title
   slide, so an imported outline ends up one slide longer. Fix: delete slide
   1 after importing, then count the slides.
6. **PdfCraft places a stamp by its centre.** Fix: give the coordinates of
   where the centre should go, and read the annotation's rectangle back
   before saving.
7. **CADCraft dimension text is tiny on millimetre drawings.** Fix: set a
   dimension scale that suits the drawing (DIMSCALE 100 worked for the test
   floor plan) and check the label at the size you will print.

No upstream issue was found for items 2, 4, 5, 6 and 7 on 1 November 2026.
If you hit one, report it to the app's repository, not here.

## Troubleshooting

**"command not found: python3" or a prompt to install developer tools.** Run
`xcode-select --install`, finish the installer, then run the command again.

**"CHECKSUM MISMATCH".** The download did not match the pinned fingerprint,
so nothing from it was installed. Run the command again (a damaged download
is deleted first). If it repeats, open an issue with the full output.

**"refusing" or "is not valid JSON" for `claude_desktop_config.json`.** The
file is damaged, so the installer did not touch it. Open it, fix the JSON (or
restore one of the `.craft-backup-` copies next to it), and run again.

**"left alone: an entry with this name exists".** You already have an MCP
server with the same name that this installer did not create. It is kept as
it is. Rename or remove yours if you want the installer's entry.

**"MCP NOT CONNECTED" (exit code 2).** The app installed but its server did
not start. Run `bash scripts/install.sh --only <app> --verify-mcp` from a
clone to see the error, and open an issue with the output.

**macOS asks before opening a downloaded app.** Check the publisher shown in
the dialog. [SIGNING.md](SIGNING.md) records the signature checks.

**No terminal question appears and it says "Re-run with --yes".** The
installer could not find a terminal to ask in (for example inside another
script). Read the plan it printed, then add `--yes`.

## Verify before you run

The one-line command downloads `install.sh` from the `v0.3.0` tag. Its
SHA-256 is:

<!-- INSTALL-SH-SHA256 -->`7167a013144b7c179e10131c088b80ad875f4b0c1848698801b6d6fc6f868cb1`<!-- /INSTALL-SH-SHA256 -->

To check it yourself before running anything:

```bash
curl -fsSLO https://raw.githubusercontent.com/qualixar/craft-studio-setup/v0.3.0/install.sh
shasum -a 256 install.sh      # compare with the value above
less install.sh               # read it
bash install.sh all --dry-run # see the plan, change nothing
```

That script then checks every file it runs from the downloaded source against
SHA-256 values written inside it, and every app download against
[catalog/apps.json](catalog/apps.json). [SHA256SUMS](SHA256SUMS) lists every
file in the repository.

## Security

No `sudo`, no `eval`, HTTPS only, every download checked against a pinned
SHA-256, and one question before any change unless you pass `--yes`.
[SECURITY.md](SECURITY.md) has the full list of what is trusted, what is
written where, and how to report a problem privately.

## Guided setup inside Claude Code (no terminal)

Paste the three lines from [GUIDE-PROMPT.md](GUIDE-PROMPT.md) into Claude
Code. They install this repository as a plugin and run `/craft-setup`, which
explains each step in plain words and asks before every install:

```
/plugin marketplace add qualixar/craft-studio-setup
/plugin install craft-studio@craft-studio-setup
/craft-setup
```

## Video and guide

Watch the walkthrough by searching for **Qualixar AI on YouTube** (ArtCraft
Episode 2: Claude Code and seven free Office alternatives). Written guides,
including the Episode 1 guide to the creative apps, are at
[qualixar.com/learn/guides](https://qualixar.com/learn/guides).

## For developers

```bash
bash tests/test_install.sh                    # 59 tests, temporary HOME, no network
shellcheck install.sh scripts/*.sh tests/*.sh
ruff check .
python3 scripts/update_checksums.py --check   # the embedded checksums are current
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and the [changelog](CHANGELOG.md).

## Licence and credit

The installer in this repository is MIT licensed: see [LICENSE](LICENSE).
The apps it installs are made by [Storytold](https://github.com/storytold)
and released under their own licences (Apache 2.0 at the pinned versions).
This repository only downloads, checks and connects them; it does not modify
or redistribute them. Qualixar is not affiliated with Storytold, Anthropic,
Microsoft or Adobe.

## Support

If this helped you:

- ⭐ Star the repository so other people searching for a free Office
  alternative for Claude can find it.
- Share it with someone who pays for a licence they barely use.
- [Report a problem](https://github.com/qualixar/craft-studio-setup/issues/new/choose)
  with the installer, or report app bugs to [Storytold](https://github.com/storytold).
- Watch the walkthrough: search for **Qualixar AI on YouTube**.
