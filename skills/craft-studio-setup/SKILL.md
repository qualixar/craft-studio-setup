---
name: craft-studio-setup
description: Walk a non-technical creator through installing the 13 free Craft Studio apps step by step, asking before each action. Use when setting up photocraft, vectorcraft, filmcraft, lightcraft, effectcraft, soundcraft, or the office pack (pdf, word, grid, deck, design, fig, cad).
---

# Craft Studio setup: guided install for creators

You are setting up 13 free apps on the user's Mac. The user is a creator, not a
developer. Explain every step in one plain sentence. **Ask before each action and
wait for the answer. Never install, download, or change anything without a yes.**

The plugin root is `${CLAUDE_PLUGIN_ROOT}`. The catalog is
`${CLAUDE_PLUGIN_ROOT}/catalog/apps.json`, groups are in
`${CLAUDE_PLUGIN_ROOT}/catalog/groups.json`, and the installer is
`${CLAUDE_PLUGIN_ROOT}/scripts/install.sh`.

## Step 0: Detect (read-only, no permission needed)

Tell the user: "First I'll check what your Mac already has. This changes nothing."

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --detect-only` and show the
result as a plain table: macOS version, chip, which of the 13 apps are already
installed, whether `~/.local/bin` is on PATH.

## Step 1: Explain the choice

Say, in plain words: "There are two packs. The creator pack (6 apps: free
versions of Photoshop, Illustrator, Premiere, Lightroom, After Effects and a
music studio) and the office pack (7 apps: free versions of Acrobat, Word,
Excel, PowerPoint, InDesign, Figma and CAD)."

Ask: "Which do you want? (a) creator, (b) office, (c) everything."

Before installing, ask: "Also install the desktop app so you can open the files
yourself?" Keep CLI-only as the default. If they say yes, append `--desktop` to
the install commands. Explain that apps go to `/Applications`; if that folder
is not writable, offer `--desktop-dir "$HOME/Applications"`.

## Step 2: Install, one app at a time

For EACH app in the chosen group, before touching anything, say one sentence,
for example: "PhotoCraft is a free Photoshop-style editor. I'm downloading
version <the pinned version in catalog/apps.json> from its official GitHub page, checking the file's fingerprint,
and putting it where your Mac can find it. OK?"

On yes, run the approved per-app install (`--yes` avoids repeating the same
question inside the script):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --group <creator|office|all> --only <app> --yes --skip-mcp
```

The script downloads the zip, checks its SHA-256 fingerprint against
`catalog/apps.json`, and **stops if the fingerprint does not match**. If it
stops, tell the user plainly: "The downloaded file did not match the expected
fingerprint, so I stopped before installing that download. Earlier installs remain." Then
stop and report (do not retry with a different source).

If the user answers "yes to everything", you may pass `--yes` and install the
rest of the group without asking per app: but still report each app as it
finishes.

## Step 3: First-run permission

If macOS asks before opening downloaded software, explain: "Review the publisher
shown in the dialog. SIGNING.md records the checks and their dates. Approve the
prompt if you trust the publisher, then tell me to continue." Re-run
`--version` afterwards.

## Step 4: Connect the apps to Claude Code and Claude Desktop (MCP)

Say: "Now I connect each app, so Claude can work the apps for you. Choose a
workspace folder (default: ~/craft-workspace). Folder access differs by app;
the catalog supplies restrictions where supported. FilmCraft, GridCraft and
CADCraft currently have no folder restriction flags in this catalog, so use a
scratch project and review permissions. The workspace is not a universal sandbox."

Ask: "Which folder may the apps use? (default ~/craft-workspace)" and "Connect
them to Claude Code, Claude Desktop, or both?" (default: both, if Claude
Desktop is installed).

First show the plan without changing anything:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --group <group> --mcp-only --workspace <folder> --both --dry-run
```

On yes, run the same command without `--dry-run` (use `--claude-code` or
`--claude-desktop` instead of `--both` if they chose one). Claude Code servers
are added with `claude mcp add` at **user scope**. For Claude Desktop the
script backs up `claude_desktop_config.json`, adds only our servers, keeps
everything else and checks the file afterwards. Then tell the user: "Quit
Claude Desktop completely (Cmd+Q) and open it again to load the apps."

The script finishes with a handshake check of every server. If it reports a
connection failure (exit 2), name the server and stop claiming success. If it
refuses to edit the Claude Desktop config because the file is not valid JSON,
say so plainly and do not edit the file yourself.

To remove everything later: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/uninstall.sh --dry-run`
shows what would go; without `--dry-run` it asks, then removes only what this
installer added.

## Step 5: The card

Finish by printing the "what you can do now" card: one line per installed app
with something the user can say, e.g. "Grade these four photos to one look:
the folder is …". Then write `setup-report.md` in the workspace folder with
app versions and fingerprints, and say: "Here is what I installed, where, and
the fingerprint of each file. Keep it."
