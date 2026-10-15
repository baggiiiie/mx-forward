#!/bin/bash
set -euo pipefail
# Stop or restore Logitech for the current login session.
service="gui/$(id -u)/com.logi.cp-dev-mgr"
plist="/Library/LaunchAgents/com.logi.optionsplus.plist"
case "${1:-status}" in
  status)
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      printf 'Logitech device agent is loaded.\n'
    else
      printf 'Logitech device agent is not loaded in this session.\n'
    fi
    ;;
  stop)
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      /bin/launchctl bootout "$service"
      printf 'Logitech device agent stopped. Other Logitech custom mappings may stop working.\n'
    else
      printf 'Logitech device agent is already stopped.\n'
    fi
    printf 'Restore it with: ./scripts/logitech-session.sh start\n'
    ;;
  start)
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      printf 'Logitech device agent is already loaded.\n'
    else
      /bin/launchctl bootstrap "gui/$(id -u)" "$plist"
      printf 'Logitech device agent restored.\n'
    fi
    ;;
  *) printf 'Usage: %s [status|stop|start]\n' "$0" >&2; exit 2 ;;
esac
