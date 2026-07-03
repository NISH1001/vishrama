#!/bin/zsh
# Build vishrama with SwiftPM, assemble dist/Vishrama.app, sign, and relaunch.
# No Xcode required — Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=dist/Vishrama.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Vishrama "$APP/Contents/MacOS/Vishrama"

BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo 0)
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>dev.nishparadox.vishrama</string>
    <key>CFBundleExecutable</key>
    <string>Vishrama</string>
    <key>CFBundleName</key>
    <string>Vishrama</string>
    <key>CFBundleDisplayName</key>
    <string>Vishrama</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.3</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Vishrama reads your calendar to avoid interrupting you with break reminders during meetings.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Vishrama reads your calendar to avoid interrupting you with break reminders during meetings.</string>
</dict>
</plist>
EOF

# Prefer a stable self-signed identity (create one named "VishramaDev" in
# Keychain Access to keep TCC grants across rebuilds); fall back to ad-hoc.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/VishramaDev/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

pkill -x Vishrama 2>/dev/null || true
if [[ "${VISHRAMA_NO_LAUNCH:-0}" != "1" ]]; then
    open "$APP"
fi
echo "Built and launched $APP (build ${BUILD_NUM}, identity: ${IDENTITY:-ad-hoc})"
