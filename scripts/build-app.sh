#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
for name in MXForward MXForwardAgent MXForwardHeadless; do
  if /usr/bin/pgrep -x "$name" >/dev/null; then
    printf 'Stop %s before packaging so mouse cleanup can finish.\n' "$name" >&2
    exit 1
  fi
done
identity="$(/usr/bin/python3 scripts/signing.py identity)"
swift build -c release --product MXForward
swift build -c release --product MXForwardAgent
bin_path="$(swift build -c release --show-bin-path)"
app_path="$PWD/dist/MX Forward.app"
agent_path="$app_path/Contents/Library/LoginItems/MX Forward Agent.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$agent_path/Contents/MacOS"
/usr/bin/ditto "$bin_path/MXForward_MXForward.bundle" "$app_path/Contents/Resources/MXForward_MXForward.bundle"
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
                CFBundleShortVersionString='0.7.2', CFBundleVersion='13',
                LSMinimumSystemVersion='14.0', NSHighResolutionCapable=True,
                NSInputMonitoringUsageDescription='Read Logitech mouse buttons and movement over Bluetooth or Bolt.')
    if agent: info['LSUIElement'] = True
    with open(pathlib.Path(path) / 'Contents/Info.plist', 'wb') as f: plistlib.dump(info, f)
PY
/usr/bin/python3 scripts/signing.py sign "$agent_path" local.baggie.mxforward.agent --identity "$identity"
/usr/bin/python3 scripts/signing.py sign "$app_path" local.baggie.mxforward --identity "$identity"
/usr/bin/codesign --verify --deep --strict "$app_path"
printf 'Built %s\nInstall: ./scripts/install-app.sh\n' "$app_path"
