#!/bin/bash
# Experimental build target: same engine sources, no SwiftUI or window code.
set -euo pipefail
cd "$(dirname "$0")/.."
if /usr/bin/pgrep -x MXForwardHeadless >/dev/null; then
  printf 'Stop MXForwardHeadless before rebuilding.\n' >&2
  exit 1
fi
entry=Sources/HeadlessPrototype/Headless.swift
product=MXForwardHeadless
case "${1:-}" in
  '') ;;
  --check) entry=Tests/HeadlessChecks.swift; product=HeadlessChecks ;;
  *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac
out="$PWD/.build/headless"
mkdir -p "$out"
swiftc -O -swift-version 5 -emit-library -emit-module -module-name ForwardCore \
  Sources/ForwardCore/*.swift -o "$out/libForwardCore.dylib" \
  -emit-module-path "$out/ForwardCore.swiftmodule" \
  -Xlinker -install_name -Xlinker @rpath/libForwardCore.dylib
swiftc -O -swift-version 5 -D MX_HEADLESS -I "$out" -L "$out" -lForwardCore \
  -Xlinker -rpath -Xlinker @executable_path \
  Sources/MXForward/AppModel.swift Sources/MXForward/BoltMouse.swift \
  Sources/MXForward/Settings.swift Sources/MXForward/ConfigJSON.swift \
  Sources/MXForward/ActionOutput.swift Sources/MXForward/WindowNavigationOutput.swift \
  Sources/MXForward/WheelOutput.swift Sources/MXForward/PointerOutput.swift \
  "$entry" -o "$out/$product"
/usr/bin/codesign --force --sign "${MX_FORWARD_SIGN_IDENTITY:--}" \
  --identifier local.baggie.mxforward.headless "$out/$product"
printf 'Built %s/%s\n' "$out" "$product"
if [ "$product" = HeadlessChecks ]; then "$out/$product"; fi
