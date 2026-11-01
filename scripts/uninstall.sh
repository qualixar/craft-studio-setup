#!/usr/bin/env bash
# craft-studio-setup uninstaller (macOS). Removes only what the installer added.
#
#   bash scripts/uninstall.sh [all|adobe|microsoft|creator|office] [options]
#
#   --group G          which apps to remove (default all)
#   --only APP         remove one app
#   --dry-run          print everything it would remove; change nothing
#   --yes, -y          do not ask for confirmation
#   --keep-desktop     leave desktop apps in place
#   --keep-mcp         leave MCP entries in place
#   --craft-home DIR   CLI install folder used at install time (default ~/tools/craft)
#   --bin-dir DIR      symlink folder used at install time (default ~/.local/bin)
#   --workspace DIR    workspace used at install time (default ~/craft-workspace)
#   --catalog DIR      catalog folder (default: ../catalog next to this script)
#   -h, --help         show this help
#
# What it removes, and nothing else:
#   * $CRAFT_HOME/<app> folders and the $BIN_DIR/<app>-cli links that point into them;
#   * desktop apps this installer recorded copying (not apps you installed yourself);
#   * MCP entries this installer recorded in Claude Code (user scope), Claude Desktop
#     and the workspace .mcp.json. Entries you edited afterwards are left alone.
#     Each config file is backed up before it is changed; when nothing else in it
#     changed since the install, it is restored byte-for-byte from the first backup.
#   * the download cache and the installer state file once everything is gone.
# Your workspace folder and documents are never deleted.
set -euo pipefail
exec 3<&0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="${CRAFT_CATALOG_DIR:-$SCRIPT_DIR/../catalog}"
CRAFT_HOME="${CRAFT_HOME:-$HOME/tools/craft}"
BIN_DIR="${CRAFT_BIN_DIR:-$HOME/.local/bin}"
WORKSPACE="${CRAFT_WORKSPACE:-$HOME/craft-workspace}"
GROUP="all"; ONLY=""; YES="${CRAFT_YES:-0}"; DRY_RUN=0; KEEP_DESKTOP=0; KEEP_MCP=0
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

usage() { sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --group|--only|--workspace|--catalog|--craft-home|--bin-dir)
      [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "missing value for $1" >&2; usage 1; };;
  esac
  case "$1" in
    all|adobe|microsoft|creator|office) GROUP="$1"; shift;;
    --group) GROUP="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --dry-run) DRY_RUN=1; shift;;
    --yes|-y) YES=1; shift;;
    --keep-desktop) KEEP_DESKTOP=1; shift;;
    --keep-mcp) KEEP_MCP=1; shift;;
    --craft-home) CRAFT_HOME="$2"; shift 2;;
    --bin-dir) BIN_DIR="$2"; shift 2;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --catalog) CATALOG_DIR="$2"; shift 2;;
    # Accepted so the bootstrapper can pass install-style target flags through.
    --claude-code|--claude-desktop|--both) shift;;
    -h|--help) usage 0;;
    *) echo "unknown option: $1 (see --help)" >&2; usage 1;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "missing required tool: python3" >&2; exit 1; }
APPS_JSON="$CATALOG_DIR/apps.json"
MCP_CONFIG="$SCRIPT_DIR/mcp_config.py"
STATE_FILE="$CRAFT_HOME/.craft-setup-state.json"
[ -f "$APPS_JSON" ] || { echo "catalog not found: $APPS_JSON" >&2; exit 1; }

WANTED_LIST="$(python3 - "$APPS_JSON" "$CATALOG_DIR/groups.json" "$GROUP" "$ONLY" <<'EOF'
import json, sys
apps = {a["name"]: a for a in json.load(open(sys.argv[1]))["apps"]}
data = json.load(open(sys.argv[2]))
group = data.get("aliases", {}).get(sys.argv[3], sys.argv[3])
if sys.argv[4]:
    names = [sys.argv[4]]
elif group in data["groups"]:
    names = data["groups"][group]["apps"]
else:
    sys.stderr.write(f"unknown group: {sys.argv[3]}\n"); sys.exit(1)
for n in names:
    if n not in apps:
        sys.stderr.write(f"unknown app: {n}\n"); sys.exit(1)
    print(n, apps[n]["binary"], apps[n]["mcp_name"])
EOF
)"

state() { python3 "$MCP_CONFIG" state "$@" --state "$STATE_FILE"; }
# Run `claude` from an empty folder so a project .mcp.json in the current
# folder (or its parents) is never mistaken for a user-scope server.
CLAUDE_CWD=""
claude_cmd() {
  if [ -z "$CLAUDE_CWD" ]; then
    CLAUDE_CWD="$(mktemp -d "${TMPDIR:-/tmp}/craft-claude.XXXXXX")"
    trap 'rmdir "$CLAUDE_CWD" 2>/dev/null || true' EXIT
  fi
  (cd "$CLAUDE_CWD" && claude "$@")
}

act() { if [ "$DRY_RUN" = 1 ]; then echo "   [dry-run] would $*"; else echo "   $*"; fi; }
REMOVED=0

# --- plan --------------------------------------------------------------------
echo "Craft Studio Setup uninstall$([ "$DRY_RUN" = 1 ] && echo ' (DRY RUN: nothing will be changed)')"
PLAN=""
while read -r app binary mcp_name; do
  [ -z "$app" ] && continue
  [ -d "$CRAFT_HOME/$app" ] && PLAN="${PLAN}   remove folder $CRAFT_HOME/$app"$'\n'
  link="$BIN_DIR/$binary"
  if [ -L "$link" ]; then
    target="$(readlink "$link")"
    case "$target" in "$CRAFT_HOME"/*) PLAN="${PLAN}   remove link $link"$'\n';; esac
  fi
  if [ "$KEEP_DESKTOP" = 0 ] && [ -n "$(state get --kind desktop_apps --key "$app")" ]; then
    PLAN="${PLAN}   remove desktop app recorded for $app"$'\n'
  fi
  if [ "$KEEP_MCP" = 0 ] && [ -n "$(state get --kind claude_code --key "$mcp_name")" ]; then
    PLAN="${PLAN}   claude mcp remove --scope user $mcp_name"$'\n'
  fi
done <<< "$WANTED_LIST"
if [ "$KEEP_MCP" = 0 ]; then
  while IFS= read -r config; do
    [ -n "$config" ] && PLAN="${PLAN}   remove this installer's MCP entries from $config"$'\n'
  done <<< "$(state keys --kind configs)"
fi
if [ -z "$PLAN" ]; then
  echo "Nothing from this installer was found under $CRAFT_HOME and $BIN_DIR. Nothing to do."
  exit 0
fi
echo "Plan:"; printf "%s" "$PLAN"
if [ "$DRY_RUN" = 0 ] && [ "$YES" != 1 ]; then
  printf 'Remove these? Your workspace and documents are kept. [y/N] ' >&2
  ans=""; IFS= read -r ans <&3 || true
  case "$ans" in [Yy]*) ;; *) echo "Nothing removed."; exit 1;; esac
fi

# --- MCP entries -------------------------------------------------------------
if [ "$KEEP_MCP" = 0 ]; then
  NAMES=""
  while read -r app binary mcp_name; do
    [ -z "$app" ] && continue
    NAMES="${NAMES}${mcp_name},"
    if [ -n "$(state get --kind claude_code --key "$mcp_name")" ]; then
      if ! command -v claude >/dev/null 2>&1; then
        echo "   $mcp_name: Claude Code CLI not found; run 'claude mcp remove --scope user $mcp_name' later" >&2
      elif [ "$DRY_RUN" = 1 ]; then
        act "run: claude mcp remove --scope user $mcp_name"
      else
        if claude_cmd mcp remove --scope user "$mcp_name" </dev/null >/dev/null 2>&1; then
          act "removed Claude Code server $mcp_name"
        else
          act "Claude Code server $mcp_name was already gone"
        fi
        state delete --kind claude_code --key "$mcp_name" >/dev/null || true
        REMOVED=$((REMOVED + 1))
      fi
    fi
  done <<< "$WANTED_LIST"
  DRY_FLAG=(); [ "$DRY_RUN" = 1 ] && DRY_FLAG=(--dry-run)
  while IFS= read -r config; do
    [ -z "$config" ] && continue
    rc=0
    python3 "$MCP_CONFIG" remove --config "$config" --label "MCP config" --state "$STATE_FILE" \
      --names "$NAMES" "${DRY_FLAG[@]+"${DRY_FLAG[@]}"}" || rc=$?
    case "$rc" in 0) ;; 10) REMOVED=$((REMOVED + 1))
      case "$config" in "$CLAUDE_DESKTOP_CONFIG"|*/Claude/claude_desktop_config.json)
        echo "   Quit and reopen Claude Desktop to unload the removed servers.";; esac;;
      *) echo "ERROR: could not update $config; it was left unchanged" >&2; exit 1;; esac
  done <<< "$(state keys --kind configs)"
fi

# --- desktop apps ----------------------------------------------------------------
if [ "$KEEP_DESKTOP" = 0 ]; then
  while read -r app binary mcp_name; do
    [ -z "$app" ] && continue
    recorded="$(state get --kind desktop_apps --key "$app")"
    [ -n "$recorded" ] || continue
    path="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["path"])' "$recorded")"
    case "$path" in *.app) ;; *) echo "   skipping unexpected desktop path: $path" >&2; continue;; esac
    if [ -d "$path" ]; then
      act "remove desktop app $path"
      if [ "$DRY_RUN" = 0 ]; then rm -rf "${path:?}"; REMOVED=$((REMOVED + 1)); fi
    else
      act "forget desktop app $path (already gone)"
    fi
    [ "$DRY_RUN" = 1 ] || state delete --kind desktop_apps --key "$app" >/dev/null || true
  done <<< "$WANTED_LIST"
fi

# --- CLIs ------------------------------------------------------------------------
while read -r app binary mcp_name; do
  [ -z "$app" ] && continue
  link="$BIN_DIR/$binary"
  if [ -L "$link" ]; then
    case "$(readlink "$link")" in
      "$CRAFT_HOME"/*) act "remove link $link"; [ "$DRY_RUN" = 1 ] || { rm -f "$link"; REMOVED=$((REMOVED + 1)); };;
      *) echo "   leaving $link: it does not point into $CRAFT_HOME";;
    esac
  fi
  if [ -d "$CRAFT_HOME/$app" ]; then
    act "remove folder $CRAFT_HOME/$app"
    [ "$DRY_RUN" = 1 ] || { rm -rf "${CRAFT_HOME:?}/${app:?}"; REMOVED=$((REMOVED + 1)); }
  fi
done <<< "$WANTED_LIST"

# --- shared leftovers ------------------------------------------------------------
if [ "$DRY_RUN" = 0 ] && [ -d "$CRAFT_HOME" ]; then
  remaining="$(find "$CRAFT_HOME" -mindepth 1 -maxdepth 1 ! -name .cache-zips ! -name .craft-setup-state.json -print | head -1)"
  if [ -z "$remaining" ]; then
    rm -rf "${CRAFT_HOME:?}/.cache-zips"
    if [ -f "$STATE_FILE" ] && [ "$(state keys --kind configs)$(state keys --kind claude_code)$(state keys --kind desktop_apps)" = "" ]; then
      rm -f "$STATE_FILE"
    fi
    rmdir "$CRAFT_HOME" 2>/dev/null && echo "   removed empty folder $CRAFT_HOME" || true
  fi
fi

if [ "$DRY_RUN" = 1 ]; then echo "DRY RUN complete: nothing was changed."; exit 0; fi
echo "Uninstall complete ($REMOVED item(s) removed). Your workspace $WORKSPACE was kept."
