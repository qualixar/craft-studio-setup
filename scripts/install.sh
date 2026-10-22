#!/usr/bin/env bash
# craft-studio-setup installer (macOS, no sudo, idempotent).
#
#   bash install.sh [--group creator|office|all] [--only <app>] [--yes]
#                    [--mcp-only] [--workspace DIR] [--detect-only]
#                    [--catalog DIR] [--craft-home DIR] [--bin-dir DIR]
#                    [--skip-mcp] [--reinstall] [--write-report DIR]
#
# Env overrides: CRAFT_CATALOG_DIR, CRAFT_HOME, CRAFT_BIN_DIR,
#                CRAFT_WORKSPACE, CRAFT_GROUP, CRAFT_YES=1, CRAFT_SKIP_MCP=1.
#
# Fails closed: a SHA-256 mismatch aborts the install (exit 1) and nothing
# from that download is kept. Never uses sudo. Only touches:
#   $CRAFT_HOME (default ~/tools/craft), $CRAFT_BIN_DIR (default ~/.local/bin),
#   the workspace dir (default ~/craft-workspace), and `claude mcp` user scope.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="${CRAFT_CATALOG_DIR:-$SCRIPT_DIR/../catalog}"
CRAFT_HOME="${CRAFT_HOME:-$HOME/tools/craft}"
BIN_DIR="${CRAFT_BIN_DIR:-$HOME/.local/bin}"
WORKSPACE="${CRAFT_WORKSPACE:-$HOME/craft-workspace}"
GROUP="${CRAFT_GROUP:-all}"
ONLY=""; YES="${CRAFT_YES:-0}"; SKIP_MCP="${CRAFT_SKIP_MCP:-0}"
MCP_ONLY=0; DETECT_ONLY=0; REINSTALL=0; REPORT_DIR=""

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --group) GROUP="$2"; shift 2;;
    --only) ONLY="$2"; shift 2;;
    --yes|-y) YES=1; shift;;
    --mcp-only) MCP_ONLY=1; shift;;
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

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1 ($2)" >&2; exit 1; }; }
need python3 "install Xcode Command Line Tools: xcode-select --install"
need curl "install curl"
need shasum "shasum ships with macOS"
need ditto "ditto ships with macOS"

APPS_JSON="$CATALOG_DIR/apps.json"
GROUPS_JSON="$CATALOG_DIR/groups.json"
[ -f "$APPS_JSON" ] || { echo "catalog not found: $APPS_JSON" >&2; exit 1; }

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Windows/Linux: not yet tested — see WINDOWS.md. Aborting." >&2; exit 1
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
v = app[key]
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

mkdir -p "$CRAFT_HOME" "$BIN_DIR" "$WORKSPACE"
CACHE_DIR="${CRAFT_HOME}/.cache-zips"; mkdir -p "$CACHE_DIR"

ask() { # ask <prompt> ; returns 0 on yes
  [ "$YES" = 1 ] && return 0
  local ans
  printf '%s [Y/n/a(ll)] ' "$1" >&2; read -r ans || true
  case "$ans" in [Nn]*) return 1;; [Aa]*) YES=1; return 0;; *) return 0;; esac
}

install_one() { # install_one <app>
  local app="$1"
  local version binary url sha zip
  version="$(field "$app" version)"; binary="$(field "$app" binary)"
  url="$(field "$app" asset_url)"; sha="$(field "$app" sha256)"
  zip="$CACHE_DIR/$(field "$app" asset)"

  if [ "$REINSTALL" = 0 ] && [ -x "$BIN_DIR/$binary" ] && "$BIN_DIR/$binary" --version >/dev/null 2>&1; then
    echo "== $app: already installed ($(installed_version "$app")), skipping"
    return 0
  fi

  echo "== $app $version"
  if [ ! -f "$zip" ]; then
    echo "   downloading $url"
    # CRAFT_CURL_PROTO defaults to '=https' (https-only). The test suite sets
    # '=http,https' to serve fixtures from a local HTTP server. Never relax
    # this for real installs: the SHA-256 pin is the trust anchor, and plain
    # HTTP exposes the download to tampering before the check.
    curl -fSL --proto "${CRAFT_CURL_PROTO:-=https}" -o "$zip" "$url"
  else
    echo "   reusing cached $(basename "$zip")"
  fi

  echo "   verifying SHA-256 against catalog/apps.json"
  local actual
  actual="$(shasum -a 256 "$zip" | awk '{print $1}')"
  if [ "$actual" != "$sha" ]; then
    echo "   CHECKSUM MISMATCH for $app" >&2
    echo "     expected: $sha" >&2
    echo "     actual:   $actual" >&2
    echo "   Aborting: removed the bad download, nothing installed." >&2
    rm -f "$zip"
    return 1
  fi
  echo "   checksum OK"

  rm -rf "$CRAFT_HOME/$app"; mkdir -p "$CRAFT_HOME/$app"
  ditto -x -k "$zip" "$CRAFT_HOME/$app"
  local found
  found="$(find "$CRAFT_HOME/$app" -maxdepth 3 -name "$binary" -type f | head -1)"
  [ -n "$found" ] || { echo "   ERROR: $binary not found after unzip" >&2; return 1; }
  chmod +x "$found"
  ln -sfn "$found" "$BIN_DIR/$binary"
  echo "   installed: $found -> $BIN_DIR/$binary"
  "$BIN_DIR/$binary" --version
}

# --- install phase -----------------------------------------------------------
if [ "$MCP_ONLY" = 0 ]; then
  while IFS= read -r app; do
    [ -z "$app" ] && continue
    version="$(field "$app" version)"
    if ask "Install $app $version into $CRAFT_HOME (symlinked to $BIN_DIR)?"; then
      install_one "$app" || exit 1   # fail closed: stop everything on mismatch
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
  done <<< "$WANTED_LIST"
  echo "--- claude mcp list ---"
  claude mcp list
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
  } > "$OUT_DIR/setup-report.md"
  echo "wrote $OUT_DIR/setup-report.md"
fi

echo "DONE."
