#!/usr/bin/env bash
# craft-studio-setup installer (macOS, no sudo, idempotent).
#
#   bash install.sh [--group creator|office|all] [--only <app>] [--yes]
#                    [--mcp-only] [--workspace DIR] [--detect-only]
#                    [--catalog DIR] [--craft-home DIR] [--bin-dir DIR]
#                    [--skip-mcp] [--reinstall] [--write-report DIR]
#                    [--desktop] [--desktop-dir DIR] [--verify-mcp]
#
# Env overrides: CRAFT_CATALOG_DIR, CRAFT_HOME, CRAFT_BIN_DIR,
#                CRAFT_WORKSPACE, CRAFT_GROUP, CRAFT_YES=1, CRAFT_SKIP_MCP=1.
#
# Fails closed: a SHA-256 mismatch aborts the install (exit 1) and nothing
# from that download is kept. Never uses sudo. Only touches:
#   $CRAFT_HOME (default ~/tools/craft), $CRAFT_BIN_DIR (default ~/.local/bin),
#   the workspace dir (default ~/craft-workspace), and `claude mcp` user scope.
#   With --desktop: copies apps to /Applications (or --desktop-dir), no sudo.
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
DESKTOP=0; DESKTOP_DIR="/Applications"; VERIFY_MCP=0

usage() {
  sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --group|--only|--workspace|--catalog|--craft-home|--bin-dir|--write-report|--desktop-dir)
      [ $# -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "missing value for $1" >&2; usage 1; };;
  esac
  case "$1" in
    --group) GROUP="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --yes|-y) YES=1; shift;;
    --mcp-only) MCP_ONLY=1; shift;;
    --desktop) DESKTOP=1; shift;;
    --desktop-dir) DESKTOP_DIR="$2"; shift 2;;
    --verify-mcp) VERIFY_MCP=1; shift;;
    --workspace) WORKSPACE="$2"; shift 2;;
    --detect-only) DETECT_ONLY=1; shift;;
    --catalog) CATALOG_DIR="$2"; shift 2;;
    --craft-home) CRAFT_HOME="$2"; shift 2;;
    --bin-dir) BIN_DIR="$2"; shift 2;;
    --skip-mcp) SKIP_MCP=1; shift;;
    --reinstall) REINSTALL=1; shift;;
    --write-report) REPORT_DIR="$2"; shift 2;;
    -h|--help) usage 0;;
    *) echo "unknown flag: $1" >&2; usage 1;;
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
[ -f "$APPS_JSON" ] || { echo "catalog not found: $APPS_JSON" >&2; exit 1; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "This installer supports macOS only. Windows installers are available upstream; Windows is untested here." >&2; exit 1
fi

# --- app selection -----------------------------------------------------------
# NOTE: no `mapfile` here — macOS ships bash 3.2, which predates it.
WANTED_LIST="$(python3 - "$APPS_JSON" "$GROUPS_JSON" "$GROUP" "$ONLY" <<'EOF'
import json, sys
apps = json.load(open(sys.argv[1]))["apps"]
groups = json.load(open(sys.argv[2]))["groups"]
group, only = sys.argv[3], sys.argv[4]
if only:
    names = [only]
else:
    if group not in groups:
        sys.stderr.write(f"unknown group: {group} (creator|office|all)\n"); sys.exit(1)
    names = groups[group]["apps"]
known = {a["name"] for a in apps}
for n in names:
    if n not in known:
        sys.stderr.write(f"unknown app: {n}\n"); sys.exit(1)
print("\n".join(names))
EOF
)"
[ -n "$WANTED_LIST" ] || { echo "no apps selected" >&2; exit 1; }

field() { # field <app> <key>  (mcp_args printed space-separated, one per line anchor)
  python3 - "$APPS_JSON" "$1" "$2" <<'EOF'
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

# --- detect-only -------------------------------------------------------------
if [ "$DETECT_ONLY" = 1 ]; then
  echo "OS: macOS $(sw_vers -productVersion) ($(uname -m))"
  echo "craft home: $CRAFT_HOME | bin: $BIN_DIR | workspace: $WORKSPACE"
  case ":$PATH:" in *":$BIN_DIR:"*) echo "PATH: $BIN_DIR is on PATH";; *) echo "PATH: $BIN_DIR is NOT on PATH (add: export PATH=\"\$HOME/.local/bin:\$PATH\")";; esac
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    v="$(installed_version "$app")"
    [ -n "$v" ] && echo "$app: installed ($v)" || echo "$app: missing"
  done <<< "$WANTED_LIST"
  exit 0
fi

if [ "$VERIFY_MCP" = 1 ]; then
  exec python3 "$SCRIPT_DIR/verify_mcp.py" --catalog "$APPS_JSON" --bin-dir "$BIN_DIR" --workspace "$WORKSPACE" --apps "$WANTED_LIST"
fi

mkdir -p "$CRAFT_HOME" "$BIN_DIR" "$WORKSPACE"
CACHE_DIR="${CRAFT_HOME}/.cache-zips"; mkdir -p "$CACHE_DIR"

ask() { # ask <prompt> ; returns 0 on yes
  [ "$YES" = 1 ] && return 0
  local ans
  printf '%s [Y/n/a(ll)] ' "$1" >&2
  if ! IFS= read -r ans <&3; then echo "No answer received; skipping." >&2; return 1; fi
  case "$ans" in [Nn]*) return 1;; [Aa]*) YES=1; return 0;; *) return 0;; esac
}

version_matches() {
  python3 - "$1" "$2" <<'PY_VERSION'
import re, sys
sys.exit(0 if re.search(r"(?:^|\s)v?" + re.escape(sys.argv[2]) + r"(?:$|\s)", sys.argv[1]) else 1)
PY_VERSION
}

verified_download() { # url, SHA-256, destination, label
  local url="$1" sha="$2" dest="$3" label="$4" actual
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
  if [ "$REINSTALL" = 0 ] && [ -x "$BIN_DIR/$binary" ] && version_matches "$(installed_version "$app")" "$version"; then
    echo "== $app: already installed ($(installed_version "$app")), skipping"
    return 0
  fi
  echo "== $app $version"
  zip="$CACHE_DIR/$(field "$app" asset)"
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
  echo "   installed: $output"
}

install_desktop() ( # subshell makes the mount cleanup local to this app
  app="$1"
  asset="$(field "$app" desktop.asset)"
  if [ -z "$asset" ]; then echo "== $app: no desktop DMG in this release, skipping desktop"; exit 0; fi
  need hdiutil "hdiutil ships with macOS"
  dmg="$CACHE_DIR/$asset"
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
  echo "   desktop installed: $DESKTOP_DIR/$name"
)

# --- install phase -----------------------------------------------------------
if [ "$MCP_ONLY" = 0 ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    version="$(field "$app" version)"
    if ask "Install $app $version into $CRAFT_HOME (symlinked to $BIN_DIR)?"; then
      install_one "$app" || exit 1   # fail closed: stop everything on mismatch
      if [ "$DESKTOP" = 1 ] && ask "Also install the desktop app for $app into $DESKTOP_DIR so you can open the files yourself?"; then
        install_desktop "$app" || exit 1
      fi
    else
      echo "== $app: skipped by user"
    fi
  done <<< "$WANTED_LIST"
fi

# --- MCP phase ---------------------------------------------------------------
if [ "$SKIP_MCP" = 0 ]; then
  need claude "install Claude Code: https://code.claude.com/docs/en/quickstart"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    binary="$(field "$app" binary)"; mcp_name="$(field "$app" mcp_name)"
    MARGS_LIST="$(field "$app" mcp_args)"
    margs=()
    while IFS= read -r a; do
      [ -z "$a" ] && continue
      margs[${#margs[@]}]="${a//\{\{WORKSPACE\}\}/$WORKSPACE}"
    done <<< "$MARGS_LIST"
    bin="$BIN_DIR/$binary"
    [ -x "$bin" ] || { echo "== $mcp_name: $binary not installed, skipping MCP"; continue; }
    if [ "$MCP_ONLY" = 0 ] && [ "$YES" != 1 ]; then
      ask "Connect $mcp_name to Claude Code (user scope, workspace $WORKSPACE)?" || { echo "== $mcp_name: MCP skipped by user"; continue; }
    fi
    if claude mcp list 2>/dev/null | grep -Eq "^${mcp_name}(:| )"; then
      claude mcp remove --scope user "$mcp_name" >/dev/null 2>&1 || true
    fi
    echo "== claude mcp add --scope user $mcp_name"
    claude mcp add --scope user "$mcp_name" -- "$bin" "${margs[@]}"
    MCP_CHECK_LIST="${MCP_CHECK_LIST}${app}"$'\n'
  done <<< "$WANTED_LIST"
  # Health check: a server that registers but cannot start is a silent failure for the user, so name it.
  echo "--- claude mcp list ---"
  MCP_LIST_OK=1
  MCP_STATUS="$(claude mcp list 2>&1)" || MCP_LIST_OK=0
  echo "$MCP_STATUS"
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    mcp_name="$(field "$app" mcp_name)"
    [ -x "$BIN_DIR/$(field "$app" binary)" ] || continue
    if [ "$MCP_LIST_OK" = 0 ] || ! echo "$MCP_STATUS" | grep -Eq "^${mcp_name}:" || echo "$MCP_STATUS" | grep -Eq "^${mcp_name}:.*(Failed|✘)"; then
      MCP_FAILED="$MCP_FAILED $mcp_name"
    fi
  done <<< "$MCP_CHECK_LIST"
  if [ -n "$MCP_FAILED" ]; then
    echo "MCP NOT CONNECTED:$MCP_FAILED (installed, but Claude Code cannot start it; re-run with --mcp-only, then report it)" >&2
  fi
fi

# --- report ------------------------------------------------------------------
OUT_DIR="${REPORT_DIR:-$WORKSPACE}"
if [ -n "$REPORT_DIR" ] || [ "$MCP_ONLY" = 0 ]; then
  mkdir -p "$OUT_DIR"
  {
    echo "# setup-report.md — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo; echo "group: $GROUP | craft home: $CRAFT_HOME | bin: $BIN_DIR | workspace: $WORKSPACE"; echo
    while IFS= read -r app; do
      [ -z "$app" ] && continue
      echo "- $app $(field "$app" version) sha256:$(field "$app" sha256) installed:$([ -x "$BIN_DIR/$(field "$app" binary)" ] && echo yes || echo no)"
    done <<< "$WANTED_LIST"
    [ -n "$MCP_FAILED" ] && echo && echo "MCP not connected:$MCP_FAILED"
  } > "$OUT_DIR/setup-report.md"
  echo "wrote $OUT_DIR/setup-report.md"
fi

[ -n "$MCP_FAILED" ] && { echo "DONE, with MCP problems:$MCP_FAILED"; exit 2; }
echo "DONE."
