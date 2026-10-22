---
name: craft-studio-setup
description: Walk a non-technical creator through installing the 13 free Craft Studio apps step by step, asking before each action. Use when setting up photocraft, vectorcraft, filmcraft, lightcraft, effectcraft, soundcraft, or the office pack (pdf, word, grid, deck, design, fig, cad).
---

# Craft Studio setup — guided install for creators

You are setting up 13 free apps on the user's Mac. The user is a creator, not a
developer. Explain every step in one plain sentence. **Ask before each action and
wait for the answer. Never install, download, or change anything without a yes.**

The plugin root is `${CLAUDE_PLUGIN_ROOT}`. The catalog is
`${CLAUDE_PLUGIN_ROOT}/catalog/apps.json`, groups are in
`${CLAUDE_PLUGIN_ROOT}/catalog/groups.json`, and the installer is
`${CLAUDE_PLUGIN_ROOT}/scripts/install.sh`.

## Step 0 — Detect (read-only, no permission needed)

Tell the user: "First I'll check what your Mac already has. This changes nothing."

Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --detect-only` and show the
result as a plain table: macOS version, chip, which of the 13 apps are already
installed, whether `~/.local/bin` is on PATH.

## Step 1 — Explain the choice

Say, in plain words: "There are two packs. The creator pack (6 apps: free
versions of Photoshop, Illustrator, Premiere, Lightroom, After Effects and a
music studio) and the office pack (7 apps: free versions of Acrobat, Word,
Excel, PowerPoint, InDesign, Figma and CAD)."

Ask: "Which do you want? (a) creator, (b) office, (c) everything."

## Step 2 — Install, one app at a time

For EACH app in the chosen group, before touching anything, say one sentence,
for example: "PhotoCraft is a free Photoshop-style editor. I'm downloading
version 0.12.0 from its official GitHub page, checking the file's fingerprint,
and putting it where your Mac can find it. OK?"

On yes, run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --group <creator|office|all> --only <app>
```

The script downloads the zip, checks its SHA-256 fingerprint against
`catalog/apps.json`, and **stops if the fingerprint does not match**. If it
stops, tell the user plainly: "The downloaded file did not match the expected
fingerprint, so I stopped instead of installing it. Nothing was changed." Then
stop and report (do not retry with a different source).

If the user answers "yes to everything", you may pass `--yes` and install the
rest of the group without asking per app — but still report each app as it
finishes.

## Step 3 — First-run permission

If macOS blocks an app ("cannot be opened" / Gatekeeper dialog), explain: "Your
Mac sometimes asks once before opening software downloaded from the internet.
These apps are signed by Learning Machines LLC (Apple Developer ID, notarized —
see SIGNING.md). Right-click the app once and choose Open, or say yes in
System Settings, then tell me to continue." Re-run `--version` afterwards.

## Step 4 — Connect the apps to Claude Code (MCP)

Say: "Now I connect each app to Claude Code, so I can work the apps for you.
Each app is only allowed to read and write inside one folder you choose
(default: ~/craft-workspace). Nothing outside that folder can be changed by
these apps."

Ask: "Which folder may the apps use? (default ~/craft-workspace)" and "Connect
them for you now?"

On yes, run:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --group <group> --mcp-only --workspace <folder>
```

This runs `claude mcp add` at **user scope** for each app, then verifies with
`claude mcp list`.

## Step 5 — The card

Finish by printing the "what you can do now" card: one line per installed app
with something the user can say, e.g. "Grade these four photos to one look —
the folder is …". Then write `setup-report.md` in the workspace folder with
app versions and fingerprints, and say: "Here is what I installed, where, and
the fingerprint of each file. Keep it."
