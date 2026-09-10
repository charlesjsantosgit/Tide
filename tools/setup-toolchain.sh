#!/bin/bash
# Makes sure this Mac builds Tide with the newest Xcode toolchain (macOS 26 SDK), updating it if not.
# build.sh runs this automatically when the SDK is too old; you can also run it on its own.
#   tools/setup-toolchain.sh            # update if needed (asks for your password for the installs)
#   tools/setup-toolchain.sh --dry-run  # only report what it would do
set -uo pipefail
REQUIRED="${TIDE_REQUIRED_SDK:-26}"
DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
run() { if [ "$DRY" = 1 ]; then echo "    would run: $*"; else "$@"; fi; }

sdk_version() { xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0; }
sdk_major() { local v; v=$(sdk_version); echo "${v%%.*}"; }

if [ "$(sdk_major)" -ge "$REQUIRED" ]; then
  echo "toolchain ok: macOS SDK $(sdk_version) at $(xcode-select -p 2>/dev/null)"
  exit 0
fi
echo "==> toolchain too old: macOS SDK $(sdk_version) at $(xcode-select -p 2>/dev/null || echo none)"
echo "    Tide's Liquid Glass panel needs the macOS $REQUIRED SDK (Xcode $REQUIRED or its Command Line Tools)."

# 1. A new enough Xcode is already on disk but not selected.
for x in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
  [ -d "$x" ] || continue
  v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$x/Contents/Info.plist" 2>/dev/null || echo 0)
  if [ "${v%%.*}" -ge "$REQUIRED" ]; then
    echo "==> found $x ($v) — selecting it"
    run sudo xcode-select -s "$x/Contents/Developer"
    run sudo xcodebuild -license accept
    if [ "$(sdk_major)" -ge "$REQUIRED" ] || [ "$DRY" = 1 ]; then echo "==> toolchain ready"; exit 0; fi
  fi
done

# 2. Xcode 26 needs macOS 15.6 or newer.
os=$(sw_vers -productVersion)
os_major=${os%%.*}; os_minor=$(echo "$os" | cut -d. -f2); os_minor=${os_minor:-0}
if [ "$os_major" -lt 15 ] || { [ "$os_major" -eq 15 ] && [ "$os_minor" -lt 6 ]; }; then
  echo "==> macOS $os cannot run Xcode $REQUIRED (needs macOS 15.6 or newer)."
  echo "    Update macOS first (System Settings › General › Software Update), then run ./build.sh again."
  echo "    Until then ./build.sh still builds Tide with a frosted panel instead of Liquid Glass."
  exit 1
fi

# 3. Newest Command Line Tools through Software Update — a few hundred MB, no Apple ID.
echo "==> looking for the newest Command Line Tools in Software Update…"
trigger=/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
touch "$trigger"
label=$(softwareupdate -l 2>/dev/null | grep -o 'Command Line Tools for Xcode-[0-9][0-9.]*' | awk -F- '{print $NF" "$0}' | sort -n | tail -1 | cut -d' ' -f2-)
rm -f "$trigger"
if [ -n "$label" ]; then
  lv=${label##*-}
  if [ "${lv%%.*}" -ge "$REQUIRED" ]; then
    echo "==> installing \"$label\" (needs your password)"
    run sudo softwareupdate -i "$label" --verbose
    run sudo xcode-select -s /Library/Developer/CommandLineTools
    if [ "$(sdk_major)" -ge "$REQUIRED" ] || [ "$DRY" = 1 ]; then echo "==> toolchain ready: SDK $(sdk_version)"; exit 0; fi
  else
    echo "    Software Update only offers \"$label\" for macOS $os."
  fi
else
  echo "    Software Update offers no Command Line Tools right now."
fi

# 4. Full Xcode from the Mac App Store (several GB; you must be signed in to the App Store).
if ! command -v mas >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  echo "==> installing mas (Mac App Store CLI) with Homebrew"
  run brew install mas
fi
if command -v mas >/dev/null 2>&1; then
  echo "==> installing Xcode from the Mac App Store"
  run mas install 497799835
  run sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  run sudo xcodebuild -license accept
  if [ "$(sdk_major)" -ge "$REQUIRED" ] || [ "$DRY" = 1 ]; then echo "==> toolchain ready: SDK $(sdk_version)"; exit 0; fi
fi

echo "==> opening Xcode in the App Store. Install it, then run ./build.sh again."
run open "macappstore://apps.apple.com/app/id497799835"
exit 1
