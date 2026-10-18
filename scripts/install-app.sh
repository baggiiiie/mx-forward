#!/bin/bash
# Install/update only after all hardware owners have completed cleanup.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/dist/MX Forward.app"
destination="${1:-/Applications/MX Forward.app}"
if [ ! -x "$source_app/Contents/MacOS/MXForward" ]; then
  printf 'Run ./scripts/build-app.sh first.\n' >&2; exit 1
fi
for name in MXForward MXForwardHeadless; do
  if /usr/bin/pgrep -x "$name" >/dev/null; then
    printf 'Quit %s before installing.\n' "$name" >&2; exit 1
  fi
done
job="gui/$(id -u)/local.baggie.mxforward.agent"
if launchctl print "$job" >/dev/null 2>&1; then
  launchctl bootout "$job"
fi
for i in $(seq 1 35); do
  if ! /usr/bin/pgrep -x MXForwardAgent >/dev/null; then break; fi
  sleep 1
done
if /usr/bin/pgrep -x MXForwardAgent >/dev/null; then
  printf 'Agent is still restoring the mouse; not replacing the bundle.\n' >&2; exit 1
fi
if [ "$source_app" != "$destination" ]; then
  mkdir -p "$(dirname "$destination")"
  /usr/bin/ditto "$source_app" "$destination"
fi
"$destination/Contents/Library/LoginItems/MX Forward Agent.app/Contents/MacOS/MXForwardAgent" \
  --install "$destination"
printf 'Installed %s; settings UI was not opened.\n' "$destination"
