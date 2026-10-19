#!/bin/bash
# Stop the old agent before replacing its app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."
source_app="$PWD/dist/MX Forward.app"
destination="$(/usr/bin/python3 -c 'import os, sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "${1:-/Applications/MX Forward.app}")"
if [ ! -x "$source_app/Contents/MacOS/MXForward" ] || \
   [ ! -x "$source_app/Contents/Library/LoginItems/MX Forward Agent.app/Contents/MacOS/MXForwardAgent" ]; then
  printf 'Run ./scripts/build-app.sh first.\n' >&2; exit 1
fi
for name in MXForward MXForwardHeadless; do
  if /usr/bin/pgrep -x "$name" >/dev/null; then
    printf 'Quit %s before installing.\n' "$name" >&2; exit 1
  fi
done
app_signer="$(/usr/bin/python3 scripts/signing.py check "$source_app" local.baggie.mxforward)"
agent_signer="$(/usr/bin/python3 scripts/signing.py check "$source_app/Contents/Library/LoginItems/MX Forward Agent.app" local.baggie.mxforward.agent)"
if [ "$app_signer" != "$agent_signer" ]; then
  printf 'The app and agent must use the same signing certificate. Rebuild before installing.\n' >&2; exit 1
fi
/usr/bin/codesign --verify --deep --strict "$source_app"
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
