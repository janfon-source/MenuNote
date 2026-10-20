#!/bin/zsh
# Builds 隨手記.app without Xcode (Command Line Tools are enough).
# Usage:  ./build.sh            -> build/隨手記.app
#         ./build.sh install    -> also copies it to /Applications
set -euo pipefail
cd "${0:A:h}"

APP=build/隨手記.app
rm -rf build/MenuNote.app "$APP"   # MenuNote.app was the bundle name before 2026.1
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

[[ -f MenuNote/AppIcon.icns ]] || swift tools/make_icon.swift

swiftc -O -swift-version 5 -parse-as-library \
  -target "$(uname -m)-apple-macos13.0" \
  MenuNote/*.swift -o "$APP/Contents/MacOS/MenuNote"

cp MenuNote/AppIcon.icns "$APP/Contents/Resources/"

# LSUIElement keeps the app out of the Dock and ⌘-Tab; it lives only in the menu bar.
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>隨手記</string>
	<key>CFBundleDisplayName</key><string>隨手記</string>
	<key>CFBundleIdentifier</key><string>com.jeff.menunote</string>
	<key>CFBundleExecutable</key><string>MenuNote</string>
	<key>CFBundleIconFile</key><string>AppIcon</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>2026.a20</string>
	<key>CFBundleVersion</key><string>2026.a20</string>
	<key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
	<key>LSUIElement</key><true/>
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key><string>純文字</string>
			<key>CFBundleTypeRole</key><string>Editor</string>
			<key>LSHandlerRank</key><string>Alternate</string>
			<key>LSItemContentTypes</key><array><string>public.plain-text</string></array>
		</dict>
	</array>
	<key>NSHighResolutionCapable</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  # Quit politely so the app can ask about unsaved changes; pkill would skip that and lose them.
  if pgrep -x MenuNote >/dev/null; then
    osascript -e 'tell application id "com.jeff.menunote" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do pgrep -x MenuNote >/dev/null || break; sleep 0.5; done
    if pgrep -x MenuNote >/dev/null; then
      echo "隨手記 is still running (quit was cancelled?); not installing." >&2
      exit 1
    fi
  fi
  rm -rf /Applications/MenuNote.app "/Applications/隨手記.app"
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/隨手記.app"
fi
