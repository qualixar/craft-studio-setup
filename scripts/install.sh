#!/usr/bin/env bash
# craft-studio-setup installer (macOS only, no sudo, safe to re-run).
#
#   bash scripts/install.sh [all|adobe|microsoft|creator|office] [options]
#
#   --group G          all (default), adobe (= creator), microsoft (= office)
#   --only APP         one app from catalog/apps.json, e.g. --only gridcraft
#   --yes, -y          answer yes to every question
#   --dry-run          print every file, folder and config it would touch; change nothing
#   --desktop          also install the desktop apps (DMG, read-only mount, no sudo)
#   --desktop-dir DIR  where desktop apps go (default /Applications)
#   --claude-code      connect the apps to Claude Code only
#   --claude-desktop   connect the apps to Claude Desktop only
#   --both             connect to both (default: Claude Code, plus Claude Desktop when found)
#   --skip-mcp         install apps only; connect nothing
#   --mcp-only         connect already-installed apps; install nothing
#   --verify-mcp       only check that each installed CLI answers MCP initialize
#                      and tools/list; install and register nothing
#   --no-verify        skip the automatic MCP check at the end of an install
#   --workspace DIR    folder the apps may use (default ~/craft-workspace)
#   --detect-only      print what is already installed; change nothing
#   --reinstall        reinstall CLIs even when the pinned version is present
#   --craft-home DIR   CLI install folder (default ~/tools/craft)
#   --bin-dir DIR      folder for CLI symlinks (default ~/.local/bin)
#   --catalog DIR      catalog folder (default: ../catalog next to this script)
#   --write-report DIR write setup-report.md to DIR (default: the workspace)
#   -h, --help         show this help
#
# Env overrides: CRAFT_CATALOG_DIR, CRAFT_HOME, CRAFT_BIN_DIR, CRAFT_WORKSPACE,
#                CRAFT_GROUP, CRAFT_YES=1, CRAFT_SKIP_MCP=1.
#
# Fails closed: a SHA-256 mismatch aborts the run (exit 1) and the bad download
# is deleted. Exit 2 means the apps installed but an MCP connection check failed.
set -euo pipefail
# Keep prompts on caller stdin; selection loops use here-strings on fd 0.
exec 3<&0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="${CRAFT_CATALOG_DIR:-$SCRIPT_DIR/../catalog}"
CRAFT_HOME="${CRAFT_HOME:-$HOME/tools/craft}"
BIN_DIR="${CRAFT_BIN_DIR:-$HOME/.local/bin}"
WORKSPACE="${CRAFT_WORKSPACE:-$HOME/craft-workspace}"
GROUP="${CRAFT_GROUP:-all}"
ONLY=""; YES="${CRAFT_YES:-0}"; SKIP_MCP="${CRAFT_SKIP_MCP:-0}"
MCP_ONLY=0; DETECT_ONLY=0; REINSTALL=0; REPORT_DIR=""; MCP_FAILED=""; MCP_CHECK_LIST=""
DESKTOP=0; DESKTOP_DIR="/Applications"; VERIFY_MCP=0; DRY_RUN=0; NO_VERIFY=0
TARGET_CODE=""; TARGET_DESKTOP=""; CHANGED=0
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --group|--only|--workspace|--catalog|--craft-home|--bin-dir|--write-report|--desktop-dir)
      [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "missing value for $1" >&2; usage 1; };;
  esac
  case "$1" in
    all|adobe|microsoft|creator|office) GROUP="$1"; shift;;
    --group) GROUP="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --yes|-y) YES=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    --mcp-only) MCP_ONLY=1; shift;;
    --desktop) DESKTOP=1; shift;;
    --desktop-dir) DESKTOP_DIR="$2"; shift 2;;
    --verify-mcp) VERIFY_MCP=1; shift;;
    --no-verify) NO_VERIFY=1; shift;;
    --claude-code) TARGET_CODE=1; TARGET_DESKTOP="${TARGET_DESKTOP:-0}"; shift;;
    --claude-desktop) TARGET_DESKTOP=1; TARGET_CODE="${TARGET_CODE:-0}"; shift;;
    --both) TARGET_CODE=1; TARGET_DESKTOP=1; shift;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --detect-only) DETECT_ONLY=1; shift;;
    --catalog) CATALOG_DIR="$2"; shift 2;;
    --craft-home) CRAFT_HOME="$2"; shift 2;;
    --bin-dir) BIN_DIR="$2"; shift 2;;
    --skip-mcp) SKIP_MCP=1; shift;;
    --reinstall) REINSTALL=1; shift;;
    --write-report) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage 0;;
    *) echo "unknown option: $1 (see --help)" >&2; usage 1;;
  esac
done

if [ "$DESKTOP" = 1 ] && { [ "$MCP_ONLY" = 1 ] || [ "$VERIFY_MCP" = 1 ]; }; then
  echo "--desktop cannot be combined with --mcp-only or --verify-mcp" >&2; exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1 ($2)" >&2; exit 1; }; }
need python3 "install Xcode Command Line Tools: xcode-select --install"
need curl "install curl"
need shasum "shasum ships with macOS"
need ditto "ditto ships with macOS"

APPS_JSON="$CATALOG_DIR/apps.json"
GROUPS_JSON="$CATALOG_DIR/groups.json"
MCP_CONFIG="$SCRIPT_DIR/mcp_config.py"
[ -f "$APPS_JSON" ] || { echo "catalog not found: $APPS_JSON" >&2; exit 1; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer supports macOS only (Apple silicon and Intel). Windows and Linux are not supported." >&2; exit 1
fi

STATE_FILE="$CRAFT_HOME/.craft-setup-state.json"

# --- app selection -----------------------------------------------------------
# NOTE: no `mapfile` here: macOS ships bash 3.2, which predates it.
WANTED_LIST="$(python3 -I - "$APPS_JSON" "$GROUPS_JSON" "$GROUP" "$ONLY" <<'EOF'
import json, sys
apps = json.load(open(sys.argv[1]))["apps"]
data = json.load(open(sys.argv[2]))
groups, aliases = data["groups"], data.get("aliases", {})
group, only = aliases.get(sys.argv[3], sys.argv[3]), sys.argv[4]
if only:
    names = [only]
else:
    if group not in groups:
        choices = "|".join(list(groups) + list(aliases))
        sys.stderr.write(f"unknown group: {sys.argv[3]} ({choices})\n"); sys.exit(1)
    names = groups[group]["apps"]
known = {a["name"] for a in apps}
for n in names:
    if n not in known:
        sys.stderr.write(f"unknown app: {n} (see catalog/apps.json)\n"); sys.exit(1)
print("\n".join(names))
EOF
)"
[ -n "$WANTED_LIST" ] || { echo "no apps selected" >&2; exit 1; }

field() { # field <app> <key>  (lists are printed one item per line)
  python3 -I - "$APPS_JSON" "$1" "$2" <<'EOF'
import json, sys
apps = json.load(open(sys.argv[1]))["apps"]
name, key = sys.argv[2], sys.argv[3]
app = next(a for a in apps if a["name"] == name)
v = app
for part in key.split('.'):
    v = v.get(part) if isinstance(v, dict) else None
if v is None:
    sys.exit(0)
print("\n".join(v) if isinstance(v, list) else v)
EOF
}

installed_version() { # echoes version or empty
  local bin="$BIN_DIR/$1-cli"
  [ -x "$bin" ] || return 0
  "$bin" --version 2>/dev/null | head -1 || true
}

version_matches() {
  python3 -I - "$1" "$2" <<'PY_VERSION'
import re, sys
sys.exit(0 if re.search(r"(?:^|\s)v?" + re.escape(sys.argv[2]) + r"(?:$|\s)", sys.argv[1]) else 1)
PY_VERSION
}

is_current() { # is_current <app>: pinned version already installed
  local binary version
  binary="$(field "$1" binary)"; version="$(field "$1" version)"
  [ "$REINSTALL" = 0 ] && [ -x "$BIN_DIR/$binary" ] && version_matches "$(installed_version "$1")" "$version"
}

# --- detect-only -------------------------------------------------------------
if [ "$DETECT_ONLY" = 1 ]; then
  echo "OS: macOS $(sw_vers -productVersion) ($(uname -m))"
  echo "craft home: $CRAFT_HOME | bin: $BIN_DIR | workspace: $WORKSPACE"
  case ":$PATH:" in *":$BIN_DIR:"*) echo "PATH: $BIN_DIR is on PATH";; *) echo "PATH: $BIN_DIR is NOT on PATH (add: export PATH=\"\$HOME/.local/bin:\$PATH\")";; esac
  if command -v claude >/dev/null 2>&1; then echo "Claude Code CLI: found"; else echo "Claude Code CLI: not found"; fi
  if [ -f "$CLAUDE_DESKTOP_CONFIG" ]; then echo "Claude Desktop config: $CLAUDE_DESKTOP_CONFIG"; else echo "Claude Desktop config: not found"; fi
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    v="$(installed_version "$app")"
    [ -n "$v" ] && echo "$app: installed ($v)" || echo "$app: missing"
  done <<< "$WANTED_LIST"
  exit 0
fi

if [ "$VERIFY_MCP" = 1 ]; then
  exec python3 -I "$SCRIPT_DIR/verify_mcp.py" --catalog "$APPS_JSON" --bin-dir "$BIN_DIR" --workspace "$WORKSPACE" --apps "$WANTED_LIST"
fi

# --- MCP targets -------------------------------------------------------------
claude_desktop_present() {
  local app
  [ -d "$(dirname "$CLAUDE_DESKTOP_CONFIG")" ] && return 0
  local IFS=:
  for app in ${CRAFT_CLAUDE_DESKTOP_APPS:-/Applications/Claude.app:$HOME/Applications/Claude.app}; do
    [ -d "$app" ] && return 0
  done
  return 1
}
DESKTOP_NOTE=""
if [ "$SKIP_MCP" = 1 ]; then
  TARGET_CODE=0; TARGET_DESKTOP=0
elif [ -z "$TARGET_CODE" ] && [ -z "$TARGET_DESKTOP" ]; then
  TARGET_CODE=1
  if claude_desktop_present; then TARGET_DESKTOP=1; else TARGET_DESKTOP=0
    DESKTOP_NOTE="Claude Desktop not found, so its config was not changed (add --claude-desktop to write it anyway)."
  fi
fi
HAVE_CLAUDE=0; command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=1

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

say() { if [ "$DRY_RUN" = 1 ]; then echo "   [dry-run] would $*"; else echo "   $*"; fi; }

if [ "$DRY_RUN" = 1 ]; then
  echo "DRY RUN: nothing will be downloaded, written or registered."
  echo "Paths this run would use:"
  for d in "$CRAFT_HOME" "$BIN_DIR" "$WORKSPACE"; do
    if [ -d "$d" ]; then echo "   exists:        $d"; else echo "   would create:  $d"; fi
  done
  echo "   download cache: $CRAFT_HOME/.cache-zips"
  echo "   state file:     $STATE_FILE (records what this installer added, for uninstall)"
else
  mkdir -p "$CRAFT_HOME" "$BIN_DIR" "$WORKSPACE"
fi
CACHE_DIR="${CRAFT_HOME}/.cache-zips"
[ "$DRY_RUN" = 1 ] || mkdir -p "$CACHE_DIR"

ask() { # ask <prompt> ; returns 0 on yes
  [ "$YES" = 1 ] && return 0
  [ "$DRY_RUN" = 1 ] && return 0
  local ans
  printf '%s [Y/n/a(ll)] ' "$1" >&2
  if ! IFS= read -r ans <&3; then echo "No answer received; skipping." >&2; return 1; fi
  case "$ans" in [Nn]*) return 1;; [Aa]*) YES=1; return 0;; *) return 0;; esac
}

state() { python3 -I "$MCP_CONFIG" state "$@" --state "$STATE_FILE"; }
state_set() { # state_set <kind> <key> <json>
  local rc=0
  state set --kind "$1" --key "$2" --value "$3" >/dev/null || rc=$?
  [ "$rc" = 0 ] || [ "$rc" = 10 ] || return "$rc"
}

verified_download() { # url, SHA-256, destination, label
  local url="$1" sha="$2" dest="$3" label="$4" actual
  case "$url" in https://*) ;; *) [ -n "${CRAFT_CURL_PROTO:-}" ] || { echo "refusing non-HTTPS URL: $url" >&2; return 1; };; esac
  if [ ! -f "$dest" ]; then
    echo "   downloading $url"
    if ! curl -fSL --retry 3 --connect-timeout 20 --proto "${CRAFT_CURL_PROTO:-=https}" --proto-redir "${CRAFT_CURL_PROTO:-=https}" -o "$dest.part" "$url"; then
      rm -f "$dest.part"; return 1
    fi
    mv "$dest.part" "$dest" || return 1
  fi
  actual="$(shasum -a 256 "$dest" | awk '{print $1}')" || return 1
  if [ "$actual" != "$sha" ]; then
    echo "CHECKSUM MISMATCH for $label (expected $sha, actual $actual). Removing download; aborting." >&2
    rm -f "$dest"; return 1
  fi
  echo "   checksum OK: $label"
}

install_one() {
  local app="$1" version binary zip found stage relative
  version="$(field "$app" version)"; binary="$(field "$app" binary)"
  if is_current "$app"; then
    echo "== $app: already installed ($(installed_version "$app")), nothing changed"
    return 0
  fi
  echo "== $app $version"
  zip="$CACHE_DIR/$(field "$app" asset)"
  if [ "$DRY_RUN" = 1 ]; then
    say "download $(field "$app" asset_url)"
    say "save it as $zip and check SHA-256 $(field "$app" sha256)"
    say "extract it to $CRAFT_HOME/$app (replacing any older copy)"
    say "link $BIN_DIR/$binary -> $CRAFT_HOME/$app/.../$binary"
    CHANGED=$((CHANGED + 1)); return 0
  fi
  verified_download "$(field "$app" asset_url)" "$(field "$app" sha256)" "$zip" "$app CLI" || return 1
  stage="$(mktemp -d "$CRAFT_HOME/.$app.XXXXXX")" || return 1
  if ! ditto -x -k "$zip" "$stage"; then rm -rf "$stage"; return 1; fi
  found="$(find "$stage" -maxdepth 3 -name "$binary" -type f | head -1)"
  if [ -z "$found" ]; then echo "ERROR: $binary not found after unzip" >&2; rm -rf "$stage"; return 1; fi
  chmod +x "$found"
  local output
  if ! output="$("$found" --version)" || ! version_matches "$output" "$version"; then
    echo "ERROR: $binary did not report pinned version $version" >&2; rm -rf "$stage"; return 1
  fi
  relative="${found#"$stage/"}"
  rm -rf "${CRAFT_HOME:?}/${app:?}"
  mv "$stage" "$CRAFT_HOME/$app" || return 1
  ln -sfn "$CRAFT_HOME/$app/$relative" "$BIN_DIR/$binary" || return 1
  state_set clis "$app" "$(python3 -I -c 'import json,sys; print(json.dumps({"dir": sys.argv[1], "link": sys.argv[2], "target": sys.argv[3], "version": sys.argv[4]}))' \
    "$CRAFT_HOME/$app" "$BIN_DIR/$binary" "$CRAFT_HOME/$app/$relative" "$version")" || {
    echo "ERROR: $app installed, but the installer could not record it in $STATE_FILE" >&2; return 1; }
  CHANGED=$((CHANGED + 1))
  echo "   installed: $output"
}

install_desktop() ( # subshell makes the mount cleanup local to this app
  app="$1"
  asset="$(field "$app" desktop.asset)"
  if [ -z "$asset" ]; then echo "== $app: no desktop DMG in this release, skipping desktop"; exit 0; fi
  recorded="$(state get --kind desktop_apps --key "$app")"
  version="$(field "$app" version)"
  if [ "$REINSTALL" = 0 ] && [ -n "$recorded" ] && python3 -I - "$recorded" "$version" <<'PY_DESKTOP'
import json, os, sys
r = json.loads(sys.argv[1])
sys.exit(0 if r.get("version") == sys.argv[2] and os.path.isdir(r.get("path", "")) else 1)
PY_DESKTOP
  then
    echo "== $app desktop: already installed, nothing changed"; exit 0
  fi
  dmg="$CACHE_DIR/$asset"
  if [ "$DRY_RUN" = 1 ]; then
    say "download $(field "$app" desktop.asset_url)"
    say "save it as $dmg and check SHA-256 $(field "$app" desktop.sha256)"
    say "mount it read-only, copy its .app into $DESKTOP_DIR (replacing an app with the same name), detach"
    exit 10
  fi
  need hdiutil "hdiutil ships with macOS"
  verified_download "$(field "$app" desktop.asset_url)" "$(field "$app" desktop.sha256)" "$dmg" "$app desktop" || exit 1
  mount="$(mktemp -d "${TMPDIR:-/tmp}/craft-mount.XXXXXX")"; mounted=0; stage=""; name=""
  # shellcheck disable=SC2329 # Called by the EXIT trap in this subshell.
  cleanup_desktop() {
    rc=$?
    trap - EXIT
    # A signal may arrive after moving the old app aside, before promotion.
    if [ -n "$stage" ] && [ -e "$stage/previous.app" ] && [ ! -e "$DESKTOP_DIR/$name" ]; then
      if ! mv "$stage/previous.app" "$DESKTOP_DIR/$name"; then
        echo "ERROR: previous app retained at $stage/previous.app" >&2
        stage=""; rc=1
      fi
    fi
    if [ "$mounted" = 1 ]; then
      if ! hdiutil detach "$mount"; then echo "ERROR: could not detach $mount; eject it in Finder" >&2; rc=1; fi
    fi
    rmdir "$mount" 2>/dev/null || true
    [ -z "$stage" ] || rm -rf "$stage"
    exit "$rc"
  }
  trap cleanup_desktop EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  hdiutil attach -readonly -nobrowse -mountpoint "$mount" "$dmg" || exit 1
  mounted=1
  bundle="$(find "$mount" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print)"
  [ -n "$bundle" ] && [ "$(printf '%s\n' "$bundle" | wc -l | tr -d ' ')" = 1 ] || { echo "ERROR: expected one .app in $asset" >&2; exit 1; }
  mkdir -p "$DESKTOP_DIR" || { echo "Cannot write to $DESKTOP_DIR; use --desktop-dir \"\$HOME/Applications\"" >&2; exit 1; }
  stage="$(mktemp -d "$DESKTOP_DIR/.craft-$app.XXXXXX")" || exit 1
  name="$(basename "$bundle")"
  ditto "$bundle" "$stage/$name" || exit 1
  if [ -e "$DESKTOP_DIR/$name" ]; then mv "$DESKTOP_DIR/$name" "$stage/previous.app" || exit 1; fi
  if ! mv "$stage/$name" "$DESKTOP_DIR/$name"; then
    if [ -e "$stage/previous.app" ]; then
      mv "$stage/previous.app" "$DESKTOP_DIR/$name" || { echo "ERROR: previous app retained at $stage/previous.app" >&2; stage=""; }
    fi
    exit 1
  fi
  if ! state_set desktop_apps "$app" "$(python3 -I -c 'import json,sys; print(json.dumps({"path": sys.argv[1], "version": sys.argv[2]}))' "$DESKTOP_DIR/$name" "$version")"; then
    echo "ERROR: $DESKTOP_DIR/$name was installed, but could not be recorded in $STATE_FILE; uninstall will not remove it" >&2
    exit 1
  fi
  echo "   desktop installed: $DESKTOP_DIR/$name"
  exit 10
)

run_desktop() { # map the subshell's "changed" exit code
  local rc=0
  install_desktop "$1" || rc=$?
  case "$rc" in 0) ;; 10) CHANGED=$((CHANGED + 1));; *) return "$rc";; esac
}

# --- install phase -----------------------------------------------------------
if [ "$MCP_ONLY" = 0 ]; then
  [ "$DRY_RUN" = 1 ] && echo "Apps:"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    version="$(field "$app" version)"
    if is_current "$app" || ask "Install $app $version into $CRAFT_HOME (symlinked to $BIN_DIR)?"; then
      install_one "$app" || exit 1   # fail closed: stop everything on mismatch
      if [ "$DESKTOP" = 1 ] && ask "Also install the desktop app for $app into $DESKTOP_DIR so you can open the files yourself?"; then
        run_desktop "$app" || exit 1
      fi
    else
      echo "== $app: skipped by user"
    fi
  done <<< "$WANTED_LIST"
fi

# --- MCP phase ---------------------------------------------------------------
app_ready() { [ -x "$BIN_DIR/$(field "$1" binary)" ] || { [ "$DRY_RUN" = 1 ] && [ "$MCP_ONLY" = 0 ]; }; }

READY_LIST=""
while IFS= read -r app; do
  [ -z "$app" ] && continue
  if app_ready "$app"; then READY_LIST="${READY_LIST}${app}"$'\n'
  elif [ "$SKIP_MCP" = 0 ]; then echo "== $(field "$app" mcp_name): $(field "$app" binary) not installed, skipping MCP"
  fi
done <<< "$WANTED_LIST"

if [ "$TARGET_CODE" = 1 ] || [ "$TARGET_DESKTOP" = 1 ]; then
  if [ -n "$READY_LIST" ] && [ "$MCP_ONLY" = 0 ] && [ "$YES" != 1 ] && [ "$DRY_RUN" = 0 ]; then
    targets=""
    [ "$TARGET_CODE" = 1 ] && targets="Claude Code"
    [ "$TARGET_DESKTOP" = 1 ] && targets="${targets:+$targets and }Claude Desktop"
    ask "Connect the installed apps to $targets (workspace $WORKSPACE)?" || { echo "== MCP connection skipped by user"; READY_LIST=""; }
  fi
  SERVERS_JSON="$(python3 -I "$MCP_CONFIG" servers --catalog "$APPS_JSON" --bin-dir "$BIN_DIR" --workspace "$WORKSPACE" --apps "$READY_LIST")"
  DRY_FLAG=(); [ "$DRY_RUN" = 1 ] && DRY_FLAG=(--dry-run)
  merge_config() { # merge_config <config path> <label>
    local rc=0
    python3 -I "$MCP_CONFIG" merge --config "$1" --label "$2" --state "$STATE_FILE" --servers "$SERVERS_JSON" "${DRY_FLAG[@]+"${DRY_FLAG[@]}"}" || rc=$?
    case "$rc" in 0) ;; 10) CHANGED=$((CHANGED + 1));; *) echo "ERROR: could not update $1 (see the message above)" >&2; exit 1;; esac
  }
  if [ -n "$READY_LIST" ] && [ "$TARGET_CODE" = 1 ] && [ "$HAVE_CLAUDE" = 0 ]; then
    echo "== Claude Code CLI not found: writing the servers to $WORKSPACE/.mcp.json instead."
    echo "   Open Claude Code in $WORKSPACE and approve the servers when it asks."
    merge_config "$WORKSPACE/.mcp.json" "workspace .mcp.json"
  elif [ -n "$READY_LIST" ] && [ "$TARGET_CODE" = 1 ]; then
    echo "== Claude Code (user scope)"
    while IFS= read -r app; do
      [ -z "$app" ] && continue
      binary="$(field "$app" binary)"; mcp_name="$(field "$app" mcp_name)"
      bin="$BIN_DIR/$binary"
      entry="$(python3 -I -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])[sys.argv[2]], sort_keys=True))' "$SERVERS_JSON" "$mcp_name")"
      margs=()
      while IFS= read -r a; do
        [ -z "$a" ] && continue
        margs[${#margs[@]}]="${a//\{\{WORKSPACE\}\}/$WORKSPACE}"
      done <<< "$(field "$app" mcp_args)"
      recorded="$(state get --kind claude_code --key "$mcp_name")"
      existing=""
      if existing="$(claude_cmd mcp get "$mcp_name" 2>/dev/null </dev/null)"; then
        ours=0
        if [ -n "$recorded" ]; then
          # Ours only while it still matches what we recorded writing.
          python3 -I "$MCP_CONFIG" cc-match --entry "$recorded" <<< "$existing" && ours=1
        else
          # Registered by v0.2.0 of this installer, which kept no record: same scope and binary.
          case "$existing" in *"Scope: User"*"Command: $bin"$'\n'*) ours=1;; esac
        fi
        if [ "$ours" = 1 ] && [ "$recorded" = "$entry" ] && [ "$REINSTALL" = 0 ]; then
          echo "   $mcp_name: already registered, nothing changed"
          MCP_CHECK_LIST="${MCP_CHECK_LIST}${app}"$'\n'
          continue
        elif [ "$ours" = 1 ]; then
          say "replace the existing $mcp_name entry (written by this installer)"
          if [ "$DRY_RUN" = 0 ] && ! claude_cmd mcp remove --scope user "$mcp_name" </dev/null >/dev/null 2>&1; then
            echo "   $mcp_name: could not remove the old entry; left as it is" >&2
            MCP_FAILED="$MCP_FAILED $mcp_name"; continue
          fi
        else
          echo "   $mcp_name: left alone: a server with this name exists that this installer did not add (or you edited it)" >&2
          continue
        fi
      fi
      if [ "$DRY_RUN" = 1 ]; then
        say "run: claude mcp add --scope user $mcp_name -- $bin ${margs[*]}"
        CHANGED=$((CHANGED + 1)); continue
      fi
      echo "   claude mcp add --scope user $mcp_name"
      claude_cmd mcp add --scope user "$mcp_name" -- "$bin" "${margs[@]}" </dev/null
      state_set claude_code "$mcp_name" "$entry" || {
        echo "ERROR: $mcp_name was added to Claude Code but could not be recorded in $STATE_FILE" >&2; exit 1; }
      CHANGED=$((CHANGED + 1))
      MCP_CHECK_LIST="${MCP_CHECK_LIST}${app}"$'\n'
    done <<< "$READY_LIST"
  fi
  if [ -n "$READY_LIST" ] && [ "$TARGET_DESKTOP" = 1 ]; then
    echo "== Claude Desktop"
    BEFORE=$CHANGED
    merge_config "$CLAUDE_DESKTOP_CONFIG" "Claude Desktop config"
    if [ "$CHANGED" != "$BEFORE" ]; then
      echo "   Quit Claude Desktop completely (Claude > Quit Claude, or Cmd+Q) and open it again to load the apps."
    fi
  fi
  [ -n "$DESKTOP_NOTE" ] && echo "== $DESKTOP_NOTE"
fi

if [ "$DRY_RUN" = 1 ]; then
  if [ "$CHANGED" = 0 ]; then
    echo "Already installed, nothing changed."
  else
    echo "Report: would write ${REPORT_DIR:-$WORKSPACE}/setup-report.md"
    echo "DRY RUN complete: $CHANGED change(s) would be made; nothing was changed."
  fi
  exit 0
fi

# --- health checks -------------------------------------------------------------
if [ -n "$MCP_CHECK_LIST" ]; then
  # A server that registers but cannot start is a silent failure for the user, so name it.
  echo "--- claude mcp list ---"
  MCP_LIST_OK=1
  MCP_STATUS="$(claude_cmd mcp list 2>&1 </dev/null)" || MCP_LIST_OK=0
  echo "$MCP_STATUS"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    mcp_name="$(field "$app" mcp_name)"
    if [ "$MCP_LIST_OK" = 0 ] || ! echo "$MCP_STATUS" | grep -Eq "^${mcp_name}:" || echo "$MCP_STATUS" | grep -Eq "^${mcp_name}:.*(Failed|✘)"; then
      MCP_FAILED="$MCP_FAILED $mcp_name"
    fi
  done <<< "$MCP_CHECK_LIST"
fi
if [ "$NO_VERIFY" = 0 ] && [ -n "$READY_LIST" ] && { [ "$TARGET_CODE" = 1 ] || [ "$TARGET_DESKTOP" = 1 ]; }; then
  echo "--- MCP handshake check (initialize + tools/list, nothing registered) ---"
  VERIFY_RC=0
  VERIFY_OUT="$(python3 -I "$SCRIPT_DIR/verify_mcp.py" --catalog "$APPS_JSON" --bin-dir "$BIN_DIR" --workspace "$WORKSPACE" --apps "$READY_LIST" 2>&1)" || VERIFY_RC=$?
  echo "$VERIFY_OUT"
  # Every app needs its own PASS line; a crash or a missing line counts as a failure.
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    case "$VERIFY_OUT" in *"{\"app\": \"$app\", \"status\": \"PASS\""*) continue;; esac
    case " $MCP_FAILED " in *" $app "*) ;; *) MCP_FAILED="$MCP_FAILED $app";; esac
  done <<< "$READY_LIST"
  if [ "$VERIFY_RC" != 0 ] && [ -z "$MCP_FAILED" ]; then MCP_FAILED=" (handshake checker exit $VERIFY_RC)"; fi
fi
if [ -n "$MCP_FAILED" ]; then
  echo "MCP NOT CONNECTED:$MCP_FAILED (installed, but the server did not start; re-run with --mcp-only, then report it)" >&2
fi

# --- report ------------------------------------------------------------------
OUT_DIR="${REPORT_DIR:-$WORKSPACE}"
if [ -n "$REPORT_DIR" ] || { [ "$MCP_ONLY" = 0 ] && { [ "$CHANGED" != 0 ] || [ ! -f "$OUT_DIR/setup-report.md" ]; }; }; then
  mkdir -p "$OUT_DIR"
  {
    echo "# setup-report.md: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo; echo "group: $GROUP | craft home: $CRAFT_HOME | bin: $BIN_DIR | workspace: $WORKSPACE"; echo
    while IFS= read -r app; do
      [ -z "$app" ] && continue
      echo "- $app $(field "$app" version) sha256:$(field "$app" sha256) installed:$([ -x "$BIN_DIR/$(field "$app" binary)" ] && echo yes || echo no)"
    done <<< "$WANTED_LIST"
    if [ -n "$MCP_FAILED" ]; then echo; echo "MCP not connected:$MCP_FAILED"; fi
  } > "$OUT_DIR/setup-report.md"
  echo "wrote $OUT_DIR/setup-report.md"
fi

case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Note: $BIN_DIR is not on your PATH. Claude does not need it; to type the commands yourself add: export PATH=\"$BIN_DIR:\$PATH\"";; esac
[ -n "$MCP_FAILED" ] && { echo "DONE, with MCP problems:$MCP_FAILED"; exit 2; }
if [ "$CHANGED" = 0 ]; then echo "Already installed, nothing changed."; else echo "DONE. $CHANGED change(s) made."; fi
