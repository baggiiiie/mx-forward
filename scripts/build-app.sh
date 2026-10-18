#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for name in MXForward MXForwardAgent MXForwardHeadless; do
  if /usr/bin/pgrep -x "$name" >/dev/null; then
    printf 'Stop %s before packaging so mouse cleanup can finish.\n' "$name" >&2
    exit 1
  fi
done
swift build -c release --product MXForward
swift build -c release --product MXForwardAgent
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/MX Forward.app"
agent_path="$app_path/Contents/Library/LoginItems/MX Forward Agent.app"
mkdir -p "$app_path/Contents/MacOS" "$agent_path/Contents/MacOS"
cp "$bin_path/MXForward" "$app_path/Contents/MacOS/MXForward"
cp "$bin_path/MXForwardAgent" "$agent_path/Contents/MacOS/MXForwardAgent"
/usr/bin/python3 - "$app_path" "$agent_path" <<'PY'
import pathlib, plistlib, sys
for path, identifier, name, executable, agent in [
    (sys.argv[1], 'local.baggie.mxforward', 'MX Forward', 'MXForward', False),
    (sys.argv[2], 'local.baggie.mxforward.agent', 'MX Forward Agent', 'MXForwardAgent', True),
]:
    info = dict(CFBundleIdentifier=identifier, CFBundleName=name, CFBundleDisplayName=name,
                CFBundleExecutable=executable, CFBundlePackageType='APPL',
                CFBundleShortVersionString='0.7.0', CFBundleVersion='11',
                LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
                NSInputMonitoringUsageDescription='Read Logitech Bolt mouse buttons and held movement for mappings.')
    if agent: info['LSUIElement'] = True
    with open(pathlib.Path(path) / 'Contents/Info.plist', 'wb') as f: plistlib.dump(info, f)
PY
identity="${MX_FORWARD_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$identity" --identifier local.baggie.mxforward.agent "$agent_path"
/usr/bin/codesign --force --sign "$identity" --identifier local.baggie.mxforward "$app_path"
/usr/bin/codesign --verify --deep --strict "$app_path"
printf 'Built %s\nInstall: ./scripts/install-app.sh\n' "$app_path"
