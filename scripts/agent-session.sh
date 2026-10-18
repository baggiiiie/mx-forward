#!/bin/bash
set -euo pipefail
app="${MX_FORWARD_APP:-/Applications/MX Forward.app}"
agent="$app/Contents/Library/LoginItems/MX Forward Agent.app/Contents/MacOS/MXForwardAgent"
case "${1:-status}" in
  start|install) exec "$agent" --install "$app" ;;
  stop|uninstall) exec "$agent" --uninstall ;;
  status|pause|enable) exec "$agent" "--${1:-status}" ;;
  *) printf 'Usage: %s {start|stop|status|pause|enable}\n' "$0" >&2; exit 2 ;;
esac
