# Agent / settings architecture

## Processes

- **MXForwardAgent**, bundled as `MX Forward.app/Contents/Library/LoginItems/MX Forward Agent.app`, owns the Bolt receiver, gesture interpretation, action output, configuration, and a small native AppKit menu bar. It does not import SwiftUI or create settings windows.
- **MXForward** is the SwiftUI settings client. It never opens HID devices. Closing its last window or choosing Quit exits the UI process after flushing edits. This does not pause or stop mappings.
- **MouseEngine** is the shared package module containing settings/JSON types, HID transport, gesture orchestration, and output adapters. **ForwardCore** remains the independently checked gesture/packet/event logic.
- **AgentSupport** contains the XPC wire types, transport, server, and per-user service installer. The standalone headless prototype is retained as an optional comparison target, not as the installed service.

The agent keeps AppKit for workspace/session notifications, screen bounds, and the native menu. It does not need SwiftUI's view graph, layout, window backing stores, or controls. Menu status is read on demand; no permanent UI-status subscription processes high-rate mouse input in the agent.

## Startup / updates

The installer (or opening the bundled settings app) writes:

`~/Library/LaunchAgents/local.baggie.mxforward.agent.plist`

The job runs in the user's Aqua session, publishes the `local.baggie.mxforward.agent` Mach service, starts at login, and uses launchd KeepAlive with a restart throttle. There is no privileged helper or system daemon. The agent uses an advisory `controller.lock` in the config directory to exclude other new controllers. Old pre-split builds do not implement that lock, so stop them before upgrading.

`./scripts/agent-session.sh stop` removes startup and boots out the job. This differs from **Pause**, which persists a disabled-resume choice and restores controls while leaving the agent installed. Restarting the agent preserves the user's Enable/Pause choice. Opening the UI deliberately reinstalls a removed agent; Setup also offers an explicit reconnect/start control.

Stop the agent and close the UI before packaging an update. `install-app.sh` copies the signed app bundle into its destination and installs/starts the nested agent without opening the settings UI. Both nested and outer bundles are signed and verified. For consistent TCC grants across builds, use `MX_FORWARD_SIGN_IDENTITY` with a stable signing identity. Ad-hoc builds are not notarized and can require renewed grants.

## Permissions / migration

**Grant Accessibility to MX Forward Agent**, not just MX Forward or the earlier standalone prototype. Input Monitoring is only needed if receiver access is blocked. The nested helper can be selected with Finder's Go to Folder using:

`/Applications/MX Forward.app/Contents/Library/LoginItems/MX Forward Agent.app`

The UI may independently need Accessibility for its system-shortcut recorder and explicit zoom-test buttons. Permission checks for actual mappings are performed in the agent. No code patches the TCC database, elevates privileges, or grants itself access.

The agent uses the original `local.baggie.mxforward` UserDefaults suite, preserving migrated preferences and the saved resume choice. JSON remains at `~/.config/mx-forward/config.json`. Only the agent writes production settings; UI edits are XPC requests. JSON errors preserve the user's file until an explicit repair. Existing mappings and defaults are unchanged.

## IPC / consistency

The interface has a single Data request/reply method with versioned Codable messages. The server accepts only connections whose effective UID matches its own. Both sides bound decoded messages to 256 KiB; the client has an exactly-once reply gate and a 40-second request timeout. No shell commands or arbitrary file paths are accepted over IPC.

The agent is the authoritative state owner. Settings requests are normalized and cannot change Enable/Pause by supplying a stale `resumeMappings` value. The settings proxy serializes requests, coalesces slider edits, tracks edit generations, and avoids applying stale preference snapshots over unacknowledged local edits. Pending edits are retried after reconnection. The UI polls state at 5 Hz while it exists; once it exits, there is no polling client or per-event XPC stream.

Shortcut recording is a per-connection lease. An explicit end, graceful UI exit, or XPC invalidation releases that client's lease. Multiple clients cannot clear each other's leases. A crashed/disconnected settings UI therefore cannot leave mouse actions suppressed indefinitely.

## Restoration / failures

Sleep, reconnect, permission loss, and Logitech-agent conflict handling remain in the shared engine. During shutdown the agent stops monitoring/config tasks, cancels unfinished input, waits for an in-flight hardware operation, and restores controls. launchd allows 30 seconds for exit. If restoration fails it logs the failure; power-cycle the mouse if needed.

Before changing hardware, the production transport atomically writes `~/.config/mx-forward/hardware-restore.json`. It records selected controls and original wheel/SmartShift/thumb-wheel settings. Confirmed restoration removes it. Immediate sleep cleanup keeps the journal because those writes cannot await confirmation. A new receiver discovery recovers the interrupted session before publishing it as ready or claiming controls again. This prevents a restarted agent from treating its own diverted wheel settings as the original native settings. Recovery failures block enabling and are retried, rather than overwriting the journal with newly claimed settings.

The journal is local recovery state, not an additional user configuration. Do not edit or delete it while the agent owns the mouse. Recovery is intentionally conservative about the Bolt slot. If hardware cannot respond, power-cycle it; changing receiver slots during an interrupted session may require manual inspection of the journal.

The agent's native menu provides Open Settings, Enable/Pause, and Stop agent and disable startup. A stopped or failed agent is reported by the UI; the UI never silently takes over the receiver. The service has no automatic Logitech-agent shutdown behavior.

## Validation

Hardware-free:

```sh
swift run ForwardCoreChecks
swift run AgentChecks
swift run MXForward --check-proxy
./scripts/check-agent-launchd.sh
```

These cover the 53 original core scenarios plus bounded/versioned IPC, settings authority, connection-scoped recording leases, disconnected-client cleanup, read-only config isolation, file reloads, exclusive ownership locks, safe shutdown, rapid UI edits, external settings changes, close-time flushing, and actual launchd startup/Mach IPC/crash restart/bootout. The launchd test uses a unique temporary service and `--offline`: its intentional SIGKILL never targets a hardware-owning process and does not change production preferences or install a persistent service.

With the agent stopped, UI closed, Logitech agent stopped, and an awake Bolt mouse:

```sh
./scripts/check-hardware.sh
```

This re-runs the original settings/recorder/hardware lifecycle checks and also verifies write-ahead journal creation/removal and restoration through a new controller after unconfirmed immediate cleanup. It sends no keyboard, scroll, or zoom actions. These checks passed on the real mouse during the split implementation. Actual login/logout and a real full-machine sleep are not automated by these tests.

## Memory measurements

On the development Mac, the previous combined process settled near **100 MB physical footprint** with its settings window closed. The no-menu headless prototype measured **8.7–8.8 MB with live mappings enabled**, in a short six-sample run. The finished agent with its native menu and XPC measured **13 MB connected**, before granting the new executable Accessibility; that is not yet a production-agent active-mapping measurement. Do not infer private memory by summing framework virtual sizes or shared RSS.

For further measurements, keep mappings/test mode unchanged, use `footprint -p <agent-pid> --noCategories`, and compare repeated samples with the UI fully exited. Include normal mouse use, prolonged scrolling/zoom, reconnects, and a longer soak before claiming a stable long-term budget.
