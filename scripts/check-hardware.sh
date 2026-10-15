#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if /usr/bin/pgrep -x MXForward >/dev/null; then
  printf 'Quit MX Forward before running hardware checks.\n' >&2
  exit 1
fi
if launchctl print "gui/$(id -u)/com.logi.cp-dev-mgr" >/dev/null 2>&1; then
  printf 'Stop Logitech with ./scripts/logitech-session.sh stop first.\n' >&2
  exit 1
fi
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/mx-forward-check.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
swiftc -swift-version 5 -emit-library -emit-module -module-name ForwardCore \
  Sources/ForwardCore/*.swift -o "$check_dir/libForwardCore.dylib" \
  -emit-module-path "$check_dir/ForwardCore.swiftmodule"
swiftc -swift-version 5 -I "$check_dir" -L "$check_dir" -lForwardCore \
  -Xlinker -rpath -Xlinker "$check_dir" \
  Sources/MXForward/AppModel.swift Sources/MXForward/BoltMouse.swift \
  Sources/MXForward/Settings.swift Sources/MXForward/ZoomOutput.swift \
  Sources/MXForward/ZoomTestWindow.swift Sources/MXForward/WindowNavigationOutput.swift Sources/MXForward/WheelOutput.swift Sources/MXForward/ShortcutRecorder.swift Tests/AppSettingsChecks.swift Tests/HardwareChecks.swift \
  -o "$check_dir/HardwareChecks"
"$check_dir/HardwareChecks"
