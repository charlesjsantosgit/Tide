#!/bin/bash
# End-to-end self-update test. Installs a copy of the current build in a temp folder, packages a
# bumped version, serves it with tools/serve.py on 127.0.0.1, and lets the copy update itself.
set -euo pipefail
cd "$(dirname "$0")/.."
PORT="${PORT:-8791}"
CUR=$(tr -d '[:space:]' < VERSION)
NEXT="${CUR%.*}.$(( ${CUR##*.} + 1 ))"
TEST=$(mktemp -d /tmp/tide-update-test.XXXXXX)
FEED="http://127.0.0.1:$PORT/releases/latest"

echo "==> building $CUR"
./build.sh >/dev/null
cp -R build.nosync/Tide.app "$TEST/Tide.app"
echo "==> packaging $NEXT"
VERSION_OVERRIDE="$NEXT" ./build.sh --package | tail -2

python3 tools/serve.py --port "$PORT" --host 127.0.0.1 > "$TEST/server.log" 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for _ in $(seq 1 40); do curl -sf "$FEED" >/dev/null 2>&1 && break; sleep 0.25; done
echo "==> feed"
curl -s "$FEED" | python3 -c 'import json,sys; d=json.load(sys.stdin); a=d["assets"][0]; print("   ", d["tag_name"], a["browser_download_url"], a["size"], "bytes")'
echo "==> download page: HTTP $(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/") ; /download -> $(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$PORT/download")"

BIN="$TEST/Tide.app/Contents/MacOS/Tide"
echo "==> copy reports: $("$BIN" --version 2>/dev/null)"
echo "==> --update-check"; "$BIN" --update-check "$FEED" 2>/dev/null | sed 's/^/    /'
echo "==> --update-dryrun"; "$BIN" --update-dryrun "$FEED" 2>/dev/null | sed 's/^/    /'
echo "==> --update-now"; "$BIN" --update-now "$FEED" 2>/dev/null | sed 's/^/    /' || true
sleep 4
GOT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TEST/Tide.app/Contents/Info.plist")
echo "==> bundle on disk is now $GOT (expected $NEXT)"
xattr -l "$TEST/Tide.app" | grep -q quarantine && echo "    (quarantine flag still present)" || echo "    no quarantine flag on the new bundle"
pkill -f "$TEST/Tide.app" 2>/dev/null || true
echo "==> restoring the $CUR package"
./build.sh --package | tail -1
rm -rf "$TEST"
if [ "$GOT" = "$NEXT" ]; then echo "PASS  self-update $CUR -> $NEXT"; else echo "FAIL  self-update"; exit 1; fi
