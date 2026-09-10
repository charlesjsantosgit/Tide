#!/bin/bash
# Builds Tide.app. Flags: --install (copy to ~/Applications and register), --run, --test, --shots
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Tide"
BUNDLE_ID="com.charlessantos.tide"
VERSION="${VERSION_OVERRIDE:-$(tr -d '[:space:]' < VERSION)}"
OUT="build.nosync"
APP="$OUT/$APP_NAME.app"
OPT="${OPT:--O}"
# Liquid Glass needs the macOS 26 SDK (Xcode 26); with Xcode 16 the panel falls back to a frosted
# material. Either way the app runs from macOS 14 up. Override with MIN_OS=…, ARCH=…, UNIVERSAL=1.
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
if [ "${SDK_VERSION%%.*}" -lt 26 ] && [ "${NO_TOOLCHAIN_UPDATE:-0}" != "1" ]; then
  # Older Xcode: update to the newest toolchain first (tools/setup-toolchain.sh), then carry on.
  if tools/setup-toolchain.sh; then
    SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)"
  else
    echo "==> continuing with SDK $SDK_VERSION: the panel will be frosted glass instead of Liquid Glass"
  fi
fi
MIN_OS="${MIN_OS:-14.0}"
ARCH="${ARCH:-$(uname -m)}"
SWIFTFLAGS="$OPT -swift-version 5 -module-name $APP_NAME -framework AppKit -framework SwiftUI -framework WebKit -framework AVFoundation -framework UniformTypeIdentifiers -lcompression ${EXTRA_SWIFTFLAGS:-}"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

compile() { # arch, output
  swiftc $SWIFTFLAGS -target "$1-apple-macos$MIN_OS" Sources/*.swift -o "$2"
}
echo "==> compiling ($OPT, SDK $SDK_VERSION, min macOS $MIN_OS)"
if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "    universal: arm64 + x86_64"
  compile arm64 "$OUT/$APP_NAME-arm64"
  compile x86_64 "$OUT/$APP_NAME-x86_64"
  lipo -create "$OUT/$APP_NAME-arm64" "$OUT/$APP_NAME-x86_64" -output "$APP/Contents/MacOS/$APP_NAME"
  rm -f "$OUT/$APP_NAME-arm64" "$OUT/$APP_NAME-x86_64"
else
  echo "    $ARCH"
  compile "$ARCH" "$APP/Contents/MacOS/$APP_NAME"
fi

echo "==> resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

DOCX_UTI="org.openxmlformats.wordprocessingml.document"
MD_UTI="net.daringfireball.markdown"

doc_type() { # name, uti, rank
cat <<PL
    <dict>
      <key>CFBundleTypeName</key><string>$1</string>
      <key>LSItemContentTypes</key><array><string>$2</string></array>
      <key>CFBundleTypeRole</key><string>Editor</string>
      <key>LSHandlerRank</key><string>$3</string>
      <key>NSDocumentClass</key><string>$APP_NAME.TideDocument</string>
    </dict>
PL
}

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>NSHumanReadableCopyright</key><string>A small, glassy word processor.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
$(doc_type "Word Document" "$DOCX_UTI" "Alternate")
$(doc_type "Rich Text with Attachments" "com.apple.rtfd" "Alternate")
$(doc_type "Rich Text Document" "public.rtf" "Alternate")
$(doc_type "Markdown Document" "$MD_UTI" "Alternate")
$(doc_type "Plain Text Document" "public.plain-text" "Alternate")
$(doc_type "Web Page" "public.html" "Alternate")
  </array>
  <key>UTImportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>$DOCX_UTI</string>
      <key>UTTypeDescription</key><string>Word Document</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string><string>public.composite-content</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>docx</string></array>
        <key>public.mime-type</key><array><string>application/vnd.openxmlformats-officedocument.wordprocessingml.document</string></array>
      </dict>
    </dict>
    <dict>
      <key>UTTypeIdentifier</key><string>$MD_UTI</string>
      <key>UTTypeDescription</key><string>Markdown Document</string>
      <key>UTTypeConformsTo</key><array><string>public.plain-text</string></array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key><array><string>md</string><string>markdown</string><string>mdown</string></array>
        <key>public.mime-type</key><array><string>text/markdown</string></array>
      </dict>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "==> signing (ad-hoc)"
xattr -cr "$APP"
codesign --force --deep --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --verbose=1 "$APP" 2>&1 | sed 's/^/    /'
echo "==> built $APP"
du -sh "$APP" | sed 's/^/    /'

for arg in "$@"; do
  case "$arg" in
    --install)
      echo "==> installing to ~/Applications/$APP_NAME.app"
      rm -rf "$HOME/Applications/$APP_NAME.app"
      mkdir -p "$HOME/Applications"
      cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
      /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/$APP_NAME.app" >/dev/null 2>&1 || true
      ;;
    --test)
      echo "==> self-test"
      "$APP/Contents/MacOS/$APP_NAME" --selftest
      ;;
    --shots)
      echo "==> screenshots -> docs/"
      "$APP/Contents/MacOS/$APP_NAME" --snapshot "$(pwd)/docs"
      ;;
    --run)
      open "$APP"
      ;;
    --package)
      DIST="$OUT/dist"
      mkdir -p "$DIST"
      ZIP="$DIST/$APP_NAME-$VERSION.zip"
      rm -f "$ZIP"
      echo "==> packaging $ZIP"
      ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
      SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
      NOTES=$(python3 tools/notes.py "$VERSION")
      python3 -c 'import json,sys,datetime; print(json.dumps({"version": sys.argv[1], "asset": sys.argv[2], "sha256": sys.argv[3], "notes": sys.argv[4], "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}, indent=2))' "$VERSION" "$(basename "$ZIP")" "$SHA" "$NOTES" > "$DIST/release.json"
      ls -la "$ZIP" | sed 's/^/    /'
      echo "    sha256 $SHA"
      ;;
  esac
done
