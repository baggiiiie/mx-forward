#!/bin/bash
set -euo pipefail
# Stop Logitech until explicitly restored.
service="gui/$(id -u)/com.logi.cp-dev-mgr"
plist="/Library/LaunchAgents/com.logi.optionsplus.plist"
case "${1:-status}" in
  status)
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      printf 'Logitech device agent is loaded.\n'
    else
      printf 'Logitech device agent is not loaded in this session.\n'
    fi
    if /bin/launchctl print-disabled "gui/$(id -u)" | /usr/bin/grep -Eq '"com.logi.cp-dev-mgr" => (true|disabled)'; then
      printf 'Automatic launch is disabled until restored.\n'
    fi
    ;;
  stop)
    /bin/launchctl disable "$service"
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      /bin/launchctl bootout "$service"
    fi
    for attempt in {1..50}; do
      if ! /bin/launchctl print "$service" >/dev/null 2>&1; then break; fi
      sleep 0.1
    done
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      printf 'Logitech is still stopping. Retry the command.\n' >&2
      exit 1
    fi
    printf 'Logitech device agent stopped; automatic launch disabled.\n'
    printf 'Restore it with: ./scripts/logitech-session.sh start\n'
    ;;
  start)
    /bin/launchctl enable "$service"
    if /bin/launchctl print "$service" >/dev/null 2>&1; then
      printf 'Logitech device agent is already loaded.\n'
    else
      /bin/launchctl bootstrap "gui/$(id -u)" "$plist"
      printf 'Logitech device agent restored.\n'
    fi
    ;;
  *) printf 'Usage: %s [status|stop|start]\n' "$0" >&2; exit 2 ;;
esac
