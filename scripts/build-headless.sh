#!/bin/bash
# Standalone measurement target; production uses MXForwardAgent + XPC.
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  --check) swift run AgentChecks; exit ;;
  '') ;;
  *) printf 'Usage: %s [--check]\n' "$0" >&2; exit 2 ;;
esac
if /usr/bin/pgrep -x MXForwardHeadless >/dev/null; then
  printf 'Stop MXForwardHeadless before rebuilding.\n' >&2
  exit 1
fi
swift build -c release --product MXForwardHeadless
bin_path="$(swift build -c release --show-bin-path)"
mkdir -p .build/headless
cp "$bin_path/MXForwardHeadless" .build/headless/MXForwardHeadless
/usr/bin/codesign --force --sign "${MX_FORWARD_SIGN_IDENTITY:--}" \
  --identifier local.baggie.mxforward.headless .build/headless/MXForwardHeadless
printf 'Built %s/.build/headless/MXForwardHeadless\n' "$PWD"
