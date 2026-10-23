#!/usr/bin/env bash
# Tests for scripts/install.sh. Runs the installer in a temp HOME with a fake
# catalog (no network beyond file://, no sudo, no real MCP changes).
#   bash tests/test_install.sh
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO_DIR/scripts/install.sh"
PASS=0; FAIL=0
HTTP_PIDS="$(mktemp)"
trap 'while read -r p; do [ -n "$p" ] && { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; } || true; done < "$HTTP_PIDS"; rm -f "$HTTP_PIDS"' EXIT

ok() { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# --- fixture: temp HOME, stub claude, two fake apps --------------------------
new_fixture() {
  FIX="$(mktemp -d)"
  # local HTTP server for fixture zips (system curl has file:// disabled)
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')"
  python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIX" >/dev/null 2>&1 &
  echo "$!" >> "$HTTP_PIDS"
  for _ in $(seq 1 50); do curl -sf -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
  export FIX_PORT="$PORT"
  export CRAFT_CURL_PROTO='=http,https'
  export HOME="$FIX/home"; mkdir -p "$HOME"
  export CRAFT_HOME="$HOME/tools/craft" CRAFT_BIN_DIR="$HOME/.local/bin"
  export CRAFT_WORKSPACE="$HOME/craft-workspace" CRAFT_CATALOG_DIR="$FIX/catalog"
  mkdir -p "$CRAFT_CATALOG_DIR" "$FIX/stubbin" "$FIX/src"
  # stub `claude`: logs mcp add/remove, pretends `mcp list` shows added servers
  cat > "$FIX/stubbin/claude" <<EOF
#!/usr/bin/env bash
LOG="$FIX/claude.log"; DB="$FIX/mcp.db"; touch "\$DB"
case "\$1 \$2" in
  "mcp list") cat "\$DB";;
  "mcp add") echo "add \$*" >> "\$LOG"; name="\$5"; grep -v "^\$name:" "\$DB" > "\$DB.tmp" 2>/dev/null || true; mv "\$DB.tmp" "\$DB"; echo "\$name: added" >> "\$DB";;
  "mcp remove") echo "remove \$*" >> "\$LOG";;
  *) echo "stub-claude: \$*" >> "\$LOG";;
esac
EOF
  chmod +x "$FIX/stubbin/claude"
  export PATH="$FIX/stubbin:/usr/bin:/bin:/usr/sbin:/sbin"
  # fake app zips: a tiny executable CLI each
  for app in fake1 fake2; do
    mkdir -p "$FIX/src/$app-payload"
    printf '#!/usr/bin/env bash\nif [ "${1:-}" = "--version" ]; then echo "%s-cli 9.9.9-test"; else echo "%s mcp running"; fi\n' "$app" "$app" > "$FIX/src/$app-payload/$app-cli"
    chmod +x "$FIX/src/$app-payload/$app-cli"
    (cd "$FIX/src" && ditto -c -k "$app-payload" "$FIX/$app.zip" --sequesterRsrc 2>/dev/null || (cd "$app-payload" && zip -qr "$FIX/$app.zip" .))
  done
}

write_catalog() { # write_catalog <sha-fake1> <sha-fake2>
  cat > "$CRAFT_CATALOG_DIR/apps.json" <<EOF
{"apps": [
  {"name":"fake1","version":"9.9.9","repo":"storytold/fake1","tag":"v9.9.9",
   "asset":"fake1.zip","asset_url":"http://127.0.0.1:$FIX_PORT/fake1.zip","sha256":"$1",
   "pin_obtained":"test fixture","binary":"fake1-cli","mcp_name":"fake1",
   "mcp_args":["mcp","--demo"],"group":"creator"},
  {"name":"fake2","version":"9.9.9","repo":"storytold/fake2","tag":"v9.9.9",
   "asset":"fake2.zip","asset_url":"http://127.0.0.1:$FIX_PORT/fake2.zip","sha256":"$2",
   "pin_obtained":"test fixture","binary":"fake2-cli","mcp_name":"fake2",
   "mcp_args":["mcp","--automation-write-root","{{WORKSPACE}}"],"group":"creator"}
]}
EOF
  cat > "$CRAFT_CATALOG_DIR/groups.json" <<EOF
{"groups":{"creator":{"pitch":"t","apps":["fake1","fake2"]},"office":{"pitch":"t","apps":[]},"all":{"pitch":"t","apps":["fake1","fake2"]}}}
EOF
}

# --- test 1: checksum mismatch fails closed ----------------------------------
echo "--- test 1: checksum mismatch must fail closed ---"
new_fixture; FIX1="$FIX"
REAL1="$(shasum -a 256 "$FIX/fake1.zip" | awk '{print $1}')"
REAL2="$(shasum -a 256 "$FIX/fake2.zip" | awk '{print $1}')"
write_catalog "0000000000000000000000000000000000000000000000000000000000000000" "$REAL2"
if bash "$INSTALL" --group creator --yes --skip-mcp >/tmp/t1.log 2>&1; then
  bad "installer exited 0 despite checksum mismatch"
else
  ok "installer exited nonzero on checksum mismatch"
fi
[ -e "$CRAFT_BIN_DIR/fake1-cli" ] && bad "symlink created despite mismatch" || ok "no symlink created on mismatch"
grep -q "CHECKSUM MISMATCH" /tmp/t1.log && ok "mismatch message printed" || bad "no mismatch message"
[ -f "$CRAFT_HOME/.cache-zips/fake1.zip" ] && bad "bad download kept" || ok "bad download removed"

# --- test 2: success path ----------------------------------------------------
echo "--- test 2: success path installs, links, registers MCP ---"
new_fixture; FIX2="$FIX"
REAL1="$(shasum -a 256 "$FIX/fake1.zip" | awk '{print $1}')"
REAL2="$(shasum -a 256 "$FIX/fake2.zip" | awk '{print $1}')"
write_catalog "$REAL1" "$REAL2"
if bash "$INSTALL" --group creator --yes >/tmp/t2.log 2>&1; then
  ok "installer exited 0 on success path"
else
  bad "installer failed on success path (see /tmp/t2.log)"
fi
[ -x "$CRAFT_BIN_DIR/fake1-cli" ] && [ -x "$CRAFT_BIN_DIR/fake2-cli" ] \
  && ok "symlinks created in bin dir" || bad "symlinks missing"
[ "$("$CRAFT_BIN_DIR/fake1-cli" --version)" = "fake1-cli 9.9.9-test" ] \
  && ok "--version check works through symlink" || bad "--version mismatch"
grep -q "add --scope user fake1" "$FIX/claude.log" && grep -q "add --scope user fake2" "$FIX/claude.log" \
  && ok "claude mcp add called at user scope for both apps" || bad "mcp add calls missing"
grep -q -- "--automation-write-root $CRAFT_WORKSPACE" "$FIX/claude.log" \
  && ok "{{WORKSPACE}} substituted in MCP args" || bad "workspace substitution missing"
grep -q "fake1" "$FIX/mcp.db" && ok "claude mcp list shows registered server" || bad "mcp list empty"
[ -f "$CRAFT_WORKSPACE/setup-report.md" ] && ok "setup-report.md written" || bad "setup-report.md missing"

# --- test 3: idempotency ------------------------------------------------------
echo "--- test 3: second run is a no-op skip ---"
if bash "$INSTALL" --group creator --yes --skip-mcp >/tmp/t3.log 2>&1; then
  ok "second run exited 0"
else
  bad "second run failed"
fi
grep -q "already installed" /tmp/t3.log && ok "second run skipped installed apps" || bad "no idempotent skip"

# --- test 4: a registered server that cannot start is reported ---------------
echo "--- test 4: MCP health check names a server that fails to connect ---"
echo "fake2: $CRAFT_BIN_DIR/fake2-cli mcp - ✘ Failed to connect" > "$FIX2/mcp.db.fail"
sed -i '' "s|\"mcp list\") cat \"\\\$DB\";;|\"mcp list\") cat \"\\\$DB\"; cat \"$FIX2/mcp.db.fail\";;|" "$FIX2/stubbin/claude"
bash "$INSTALL" --group creator --yes --mcp-only >/tmp/t4.log 2>&1; rc=$?
[ "$rc" = 2 ] && ok "installer exits 2 when a server fails to connect" || bad "exit was $rc, expected 2"
grep -q "MCP NOT CONNECTED: fake2" /tmp/t4.log && ok "failing server named" || bad "failing server not named"

rm -rf "$FIX1" "$FIX2"
echo "=== $PASS passed, $FAIL failed ==="
[ "$FAIL" = 0 ]
