# Agent and settings UI

## What runs where

- **MXForwardAgent** owns the Bluetooth mouse or Bolt receiver, mouse actions, settings, and native menu bar. It uses AppKit but not SwiftUI.
- **MXForward** is the SwiftUI settings window. Closing it saves pending edits and exits the UI process, leaving mappings running. If saving fails, quitting is cancelled so the edits aren't lost.
- **MouseEngine** handles HID, gestures, configuration, and event output. **ForwardCore** holds packet parsing and gesture calculations.
- **AgentSupport** handles XPC and login startup. **SettingsClient** holds the UI's connection and editable state. Test programs are separate targets and aren't shipped in the app.

## Startup and permissions

The bundled helper is:

`MX Forward.app/Contents/Library/LoginItems/MX Forward Agent.app`

The installer, or opening the settings app, creates `~/Library/LaunchAgents/local.baggie.mxforward.agent.plist`. launchd starts the agent at login and restarts it after a crash. No root daemon is installed. A file lock prevents two agents from owning the mouse; another lock serializes service installation and removal.

**Pause** restores controls and remembers not to resume. **Stop agent and disable startup** removes the login job and restores controls, but keeps the saved Enable/Pause choice. Opening the settings UI installs the agent again; Setup also has a reconnect button. Closing the UI does neither of those things.

Grant Accessibility to **MX Forward Agent**, not just the settings app or the old prototype. Add Input Monitoring only if discovery is blocked. The settings UI may separately need Accessibility to record system shortcuts and run its zoom verification buttons. Installation registers both bundles with LaunchServices without activating either app. Hardware-free engines don't query input permissions. Nothing edits the TCC database or grants itself permission.

Preferences still use the original `local.baggie.mxforward` UserDefaults suite. JSON stays at `~/.config/mx-forward/config.json`. Only the agent writes production settings. Broken JSON is left alone until the user repairs or replaces it.

## XPC and editing

The agent accepts connections from its own user ID. Requests and replies are versioned JSON carried over XPC, limited to 256 KiB. Requests time out after 40 seconds; cancellation, disconnection, and explicit close finish pending calls immediately. A late reply from an old connection cannot close a new one.

Settings requests include the values the editor started with. The agent applies only changed fields, keeping unrelated edits from another window or the JSON file. A settings request cannot change Enable/Pause. The UI queues requests, combines rapid slider edits, and keeps any edits or Undo made while a save is pending. Save errors remain visible and prevent the UI from silently exiting with unsaved edits.

The UI polls at 5 Hz while connected, backing off when unavailable. Once it exits, there is no polling client. Recording suppression belongs to each connection: ending recording or disconnecting removes that client's suppression without affecting another recorder.

## Restoration

Before changing hardware, the agent saves native settings in `~/.config/mx-forward/hardware-restore.json`. Successful, confirmed restoration removes this file. Sleep cleanup keeps it because writes during sleep cannot wait for replies.

On reconnect, recovery finishes before controls can be claimed. The reconnect timer doesn't cancel an active recovery. Shutdown cancels discovery, stops monitoring and unfinished input, waits for hardware work, and restores controls. launchd allows 30 seconds for exit.

If recovery fails, the file is kept for another attempt. Power-cycle an unresponsive mouse. Recovery checks the mouse unit ID across Bluetooth and Bolt connections. Older recovery files check the original connection address. Don't edit or delete it while the agent owns the mouse.

## Building and testing

Stop the installed agent and close the UI before packaging or replacing the app. The build signs both bundles with a saved certificate fingerprint and a designated requirement pinned to that certificate and bundle ID—not the binary's changing hash. The identity is selected once from Keychain or `MX_FORWARD_SIGN_IDENTITY`, then saved in `~/.config/mx-forward/signing-identity`. Missing or expired saved certificates fail the build; they aren't silently replaced. Private keys aren't exported.

Installation checks the stable requirements and matching certificates before stopping the old agent, and rejects ad-hoc builds. Moving from the old ad-hoc signature requires one fresh permission grant. Routine rebuilds using the same certificate, identifiers, and install path should then retain grants. Certificate changes, revocation, and OS policy can still require approval. Builds aren't notarized.

Hardware-free checks:

```sh
swift run ForwardCoreChecks
swift run AgentChecks
swift run ProxyChecks
./scripts/check-agent-launchd.sh
./scripts/check-signing.sh  # requires the selected certificate
```

These check core behavior, message limits, cancellation and reconnection, concurrent settings edits, in-flight Undo, failed saves, recording cleanup, config reloads, file locks, shutdown, and launchd restart. The launchd test kills only its own hardware-disabled process under a temporary service name. It doesn't touch the installed agent or production preferences. Signing checks build two different versions of a temporary app and nested helper, verify that their code hashes differ but their designated requirements match, and check that an ad-hoc replacement is rejected. The temporary apps never run and no permission grants are changed.

With the UI closed, both agents stopped, and an awake mouse connected over Bluetooth or Bolt:

```sh
./scripts/check-hardware.sh
```

These checks cover native restoration, wheel modes, the recovery file, live settings changes, and simulated sleep/wake notifications. They send no keyboard, zoom, or scroll actions. Actual login/logout, full-machine sleep, and long-term memory use still need manual testing. See the README for the short memory measurements.
