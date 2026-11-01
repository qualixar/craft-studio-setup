---
description: "Set up the Craft Studio apps step by step: checksum-verified install plus MCP registration. Asks before each action."
---

Follow the `craft-studio-setup` skill to set up the Craft Studio apps.

1. Start with Step 0 (detect: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --detect-only`) and show the plain-English table.
2. Ask which pack: creator (6 apps), office (7 apps), or everything (13 apps).
3. Ask: "Also install the desktop app so you can open the files yourself?" Default to CLI-only unless they say yes. Add `--desktop` to each install only when approved. For each app: explain in one plain sentence, ask permission, then run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh --group <group> --only <app> --yes --skip-mcp` (append `--desktop` when approved). If a fingerprint check fails, stop and say so plainly.
4. Handle any macOS first-run permission prompt (see SIGNING.md). Ask which folder and whether to connect Claude Code, Claude Desktop or both, show the plan with `--mcp-only --workspace <folder> --both --dry-run`, then run it without `--dry-run` after a yes. Tell the user to restart Claude Desktop if its config changed.
5. Print the "what you can do now" card and write `setup-report.md`.

Never install, download, or change anything without the user's yes. If the user says "yes to everything", pass `--yes` to the installer.
