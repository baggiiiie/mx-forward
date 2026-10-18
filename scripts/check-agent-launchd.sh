#!/bin/bash
# Isolated launchd/XPC/restart test. No HID, real preferences, or windows.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --product MXForwardAgent
agent="$(swift build --show-bin-path)/MXForwardAgent"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/mx-launchd-check.XXXXXX")"
service="local.baggie.mxforward.check.$(uuidgen | tr '[:upper:]' '[:lower:]')"
domain="gui/$(id -u)"
cleanup() {
  launchctl bootout "$domain/$service" >/dev/null 2>&1 || true
  rm -rf "$check_dir"
}
trap cleanup EXIT
/usr/bin/python3 - "$check_dir/job.plist" "$service" "$agent" "$check_dir" <<'PY'
import plistlib, sys
path, service, agent, logs = sys.argv[1:]
with open(path, 'wb') as f:
    plistlib.dump(dict(Label=service, ProgramArguments=[agent, '--offline'],
        MachServices={service: True}, KeepAlive=True, RunAtLoad=True, ThrottleInterval=1,
        EnvironmentVariables={'MX_FORWARD_AGENT_TEST_SERVICE': service},
        StandardOutPath=logs+'/stdout.log', StandardErrorPath=logs+'/stderr.log'), f)
PY
launchctl bootstrap "$domain" "$check_dir/job.plist"
MX_FORWARD_AGENT_TEST_SERVICE="$service" "$agent" --status > "$check_dir/status.json"
/usr/bin/python3 - "$check_dir/status.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r['version'] == 1 and not r.get('error')
assert not r['state']['enabled'] and not r['state']['connected']
PY
pid="$(launchctl print "$domain/$service" | awk '/pid =/ {print $3; exit}')"
test -n "$pid"
# Intentional crash of a hardware-disabled test process ONLY.
kill -KILL "$pid"
sleep 2
MX_FORWARD_AGENT_TEST_SERVICE="$service" "$agent" --status > "$check_dir/restarted.json"
new_pid="$(launchctl print "$domain/$service" | awk '/pid =/ {print $3; exit}')"
test -n "$new_pid" && test "$new_pid" != "$pid"
launchctl bootout "$domain/$service"
for i in $(seq 1 20); do
  if ! launchctl print "$domain/$service" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
if launchctl print "$domain/$service" >/dev/null 2>&1; then
  printf 'FAIL: test agent survived bootout\n' >&2; exit 1
fi
printf 'PASS: launchd startup, Mach-service IPC, crash restart, graceful bootout; no hardware touched\n'
