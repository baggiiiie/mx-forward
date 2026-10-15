#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if /usr/bin/pgrep -x MXForward >/dev/null; then
  printf 'Quit MX Forward before rebuilding so its mouse cleanup can finish.\n' >&2
  exit 1
fi
swift build -c release --product MXForward
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/MX Forward.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/MXForward" "$app_path/Contents/MacOS/MXForward"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.baggie.mxforward</string>
<key>CFBundleName</key><string>MX Forward</string>
<key>CFBundleDisplayName</key><string>MX Forward</string>
<key>CFBundleExecutable</key><string>MXForward</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.2</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSInputMonitoringUsageDescription</key><string>Read the selected Logitech Bolt mouse buttons and held movement for shortcuts and zoom.</string>
</dict></plist>
PLIST
# Use normal signing requirements; local builds default to ad-hoc signing.
/usr/bin/codesign --force --sign "${MX_FORWARD_SIGN_IDENTITY:--}" \
  --identifier local.baggie.mxforward "$app_path"
/usr/bin/codesign --verify --strict "$app_path"
printf 'Built %s\n' "$app_path"
