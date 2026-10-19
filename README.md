# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Every clickable button (Forward, Back, Gesture, Top, and pressing the wheel) has the same three kinds of action: **click**, **hold**, and **hold and drag** up, down, left, or right. Each slot can send a recorded shortcut, Mission Control, App Exposé, a desktop switch, Smart Zoom, a middle click, or nothing. Up and down can also zoom continuously.
- Defaults: Forward clicks **⌘]**, Back clicks **⌘[**. The gesture button opens Mission Control on click and drag up, App Exposé on drag down, and switches desktops on drag left/right. The top button Smart Zooms on click and pinch-zooms while dragged up or down. The wheel button starts off; turning it on replaces the native middle click with its actions.
- A hold fires once after the button's hold delay (150–1500 ms, initially 400 ms), and the click then doesn't fire. With no hold action, a long press is a click. Dragging before the hold delay cancels the hold.
- **Scroll & navigate**: select this in any drag-direction menu to link all four directions. Hold the button and move the mouse to scroll in two dimensions, with content following your hand like a trackpad. The cursor moves too (replayed from raw mouse movement; native pointer acceleration is not reproduced). Scroll speed is adjustable (25–300%). Uses native phased pixel-scroll events; navigation gestures depend on the receiving app. No momentum or multi-finger desktop gestures.
- Drag sensitivity (25–300%) and zoom speed (25–600%, initially 200%) are set per button.
- Main-wheel control: scroll speed (25–600%), natural or standard direction, adjustable acceleration, and ratchet/free-spin modes. Keep current mode preserves existing SmartShift behavior. Initially off.
- Horizontal thumb-wheel direction: Keep current, Standard, or Reversed. Applies independently of the main wheel and restores the previous direction on Pause or agent shutdown.
- Test mode shows actions without sending them; Scroll & navigate still moves the cursor. Pause restores the selected buttons.
- A lightweight **MX Forward Agent** owns the mouse and menu bar. The settings UI is a separate process: closing its window exits it without stopping mappings. The per-user LaunchAgent starts at login and restarts after a crash.
- Settings stay editable while mappings are active. Shortcuts and speeds apply immediately; changing selected controls or wheel mode briefly reconnects automatically.
- Automatic discovery on launch, wake, and reconnect. After you Enable once, mappings resume automatically; an explicit Pause keeps them off.

- Logitech Options–style window: click a button on the mouse picture to configure it. Pressed buttons light up while mappings are enabled.
- Every setting is also available as JSON, in the **JSON** tab or in `~/.config/mx-forward/config.json`.

The app talks directly to the Bolt receiver. Logitech's device agent must stay stopped; there is no Logitech runtime dependency. Rotation, pointer-speed controls, and per-app profiles are not implemented.

## Build

Requires macOS 14+ and Swift 6 command-line tools. No third-party dependencies.

```sh
cd ~/repos/mx-forward
swift run ForwardCoreChecks
swift run AgentChecks
swift run ProxyChecks
./scripts/check-agent-launchd.sh
# Close the settings UI, and stop any installed agent before packaging:
./scripts/agent-session.sh stop  # only if already installed
./scripts/build-app.sh
./scripts/install-app.sh
open '/Applications/MX Forward.app'
```

Stop the agent and close the settings UI before packaging/replacing the bundle. Packaged builds (`./scripts/build-app.sh`) use a **stable code-signing certificate**, not an ad-hoc signature, so routine rebuilds keep the same macOS permission identity. Builds are not notarized.

On the first build, the script uses the only valid code-signing identity in your Keychain, or you can select one with `MX_FORWARD_SIGN_IDENTITY` (its exact name or SHA-1 fingerprint). It remembers the fingerprint in `~/.config/mx-forward/signing-identity` and reuses it. The private key stays in Keychain. If the saved certificate is missing or expired, the build stops rather than silently changing identities. If no certificate exists, create a Code Signing certificate in Keychain Access or Xcode first.

**Switching from the old ad-hoc build requires one-time reapproval of existing permissions.** Remove and re-add the installed agent's Accessibility entry to approve the new signer; do the same for the settings UI if you use its system-shortcut recorder. After that, keep the same certificate, bundle identifiers, and installation path. Replacing the certificate or revoking permissions can still require a new grant. The installer rejects ad-hoc builds to prevent accidental regressions.

Run `./scripts/check-signing.sh` to verify that two different UI/agent builds have identical certificate requirements. This test signs temporary apps but never launches them or changes permissions.

The installer starts the per-user agent without opening or activating the UI. The UI also installs/starts the bundled agent when opened. The job is `~/Library/LaunchAgents/local.baggie.mxforward.agent.plist`; no root daemon is installed. Use the menu bar or **Setup → Stop agent and disable startup** to remove it, or:

```sh
./scripts/agent-session.sh status
./scripts/agent-session.sh pause   # restore controls; remain installed
./scripts/agent-session.sh enable
./scripts/agent-session.sh stop    # stop and remove login startup
./scripts/agent-session.sh start   # reinstall/start
```

See [architecture and lifecycle](docs/architecture.md) for IPC, permissions, recovery, and validation.

## Memory usage

The original combined app used about **100 MB** with its settings window closed.
The first headless prototype used **8.7–8.8 MB with mappings active**. The finished
agent, including its native menu bar, measured **13 MB connected** before its new
Accessibility permission was granted. These were short samples, not long-term budgets.

Close the settings UI and sample the installed agent:

```sh
pid=$(launchctl print "gui/$(id -u)/local.baggie.mxforward.agent" | awk '/pid =/ {print $3; exit}')
footprint -p "$pid" --noCategories
ps -p "$pid" -o pid,%cpu,rss
```

Use physical footprint rather than adding up framework sizes. Keep Test mode and
mappings unchanged when comparing samples. The old measurement executable has been
removed; `swift run MXForwardAgent --offline` provides a hardware-free baseline
without installing a service or creating a menu bar.

## Try it

1. In the **Buttons** tab, click a button on the mouse picture. Pick an action for its click, hold, and each drag direction. For **Keyboard shortcut**, click the recorder and press your keys; Escape cancels. **Restore defaults** resets the button. The timing pad previews the hold delay. Settings save automatically.
2. Add **MX Forward Agent** under **System Settings → Privacy & Security → Accessibility** for live actions. Its app is at `/Applications/MX Forward.app/Contents/Library/LoginItems/MX Forward Agent.app`. Add Input Monitoring only if discovery is blocked. The settings UI (**MX Forward**) may separately need Accessibility to record system shortcuts. The agent refreshes permissions automatically; restart it if macOS requires that.
3. The app discovers the mouse automatically. Move it to wake it if needed and allow a few seconds. **Discover mouse** remains available for a manual retry.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then click, hold, and drag each button. The footer shows which action each one would send, such as "Back hold → Mission Control".
6. Turn Test mode off while enabled, or turn it off before you Enable. Point at content in a browser or image viewer. Click the top button for Smart Zoom; hold it and move up to zoom in or down to zoom out. Higher **Zoom speed** needs less mouse movement.
7. For the main wheel, select it on the mouse picture, turn **Control main wheel** on, choose **Scroll speed**, **Natural scrolling**, **Acceleration**, and **Wheel mode**. Acceleration starts at 100%; set it to 0% for constant speed. If mappings are already enabled, changes apply automatically. Ratchet locks the notches; Free-spin removes them. Keep current mode leaves the existing SmartShift mode and threshold untouched. These controls affect only the MX Master 3S main wheel.
8. Select the **Thumb wheel** and choose **Standard** or **Reversed**. This applies automatically while enabled. Keep current direction leaves the native setting alone.
9. **Open zoom verification** (Top button or **Setup** tab) provides a native test canvas. Its buttons send real macOS gesture events; its status confirms whether they reached `magnify` / `smartMagnify` handlers. Test mode suppresses mouse actions, but these explicit verification buttons still send events into this test window.

```sh
./scripts/logitech-session.sh stop
# Pause mappings or stop the agent before restoring Logitech.
./scripts/logitech-session.sh start
```

The stop command disables Logitech's automatic launch and stops its device agent. This persists across logins until the start command restores automatic launch and the agent. It expects the standard Logitech LaunchAgent. Use `./scripts/logitech-session.sh status` to check it.

## JSON configuration

Settings are mirrored to `~/.config/mx-forward/config.json`. Every button has the same keys. Edit it in any editor; saved changes apply within a second. Changes made in the app are written back. If the file has an error, the app keeps your edits, shows the problem, and offers to replace the file with the current settings. The **JSON** tab has an editor (⌘S applies), import/export, and a reference.

```json
{
  "testMode": false,
  "buttons": {
    "forward": { "enabled": true, "click": "cmd+]", "hold": "cmd+shift+t", "holdDelayMs": 400 },
    "back": { "click": "cmd+[", "up": "missionControl", "down": "appExpose", "dragSensitivityPercent": 100 },
    "gesture": { "click": "missionControl", "left": "desktopLeft", "right": "desktopRight" },
    "top": { "click": "smartZoom", "up": "zoom", "down": "zoom", "zoomSpeedPercent": 200 },
    "wheelButton": { "enabled": false, "click": "middleClick" }
  },
  "wheel": { "enabled": true, "speedPercent": 150, "accelerationPercent": 100, "natural": true, "mode": "ratchet" },
  "thumbWheel": { "direction": "reversed" }
}
```

- Buttons are `forward`, `back`, `gesture`, `top`, and `wheelButton`. Each takes `enabled`, the action slots `click`, `hold`, `up`, `down`, `left`, `right`, and `holdDelayMs`, `dragSensitivityPercent`, `zoomSpeedPercent`.
- Actions are a shortcut such as `"cmd+shift+]"` or `"⌘⇧]"`, `"none"`, `"missionControl"`, `"appExpose"`, `"desktopLeft"`, `"desktopRight"`, `"smartZoom"`, `"middleClick"`, `"zoom"` (up and down only, and both together), or `"scroll"` (set all four directions together; `dragSensitivityPercent` controls scroll speed). `"default"` restores that slot's built-in action.
- Modifiers: `cmd`, `opt`, `ctrl`, `shift`, `fn`. Keys: letters, digits, punctuation, `return`, `tab`, `space`, `delete`, `escape`, arrow names, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`. Key names refer to US-layout key positions; shortcuts recorded on other layouts are written as `{"keyCode": 30, "modifiers": ["cmd"], "label": "+"}`.
- `wheel.mode`: `unchanged`, `ratchet`, `freeSpin`. `thumbWheel.direction`: `unchanged`, `standard`, `reversed`. Percentages use 100 for 100% and are clamped to the app's slider ranges.
- Any key can be omitted to keep its current value, so a file can contain just the settings you care about.

## Behavior and recovery

- Mission Control, App Exposé, and desktop actions follow your macOS keyboard shortcuts for them, including disabled ones. Record a shortcut instead if you want a fixed key.
- A drag fires one action when movement crosses the drag distance; release before the next one. While a button has any drag action, native pointer movement is diverted while that button is held. Scroll & navigate replays cursor movement and keeps scrolling the content under the initial press; other drag actions keep the pointer still. Buttons without drag actions leave the pointer alone. Holding two buttons with drag actions at once cancels both until they're released.
- Shortcuts store a keycode and modifiers and target the active app when they fire. Click a shortcut field and press your keys to replace it. Recording temporarily suppresses mouse shortcut and gesture actions; Escape, leaving the window, or disabling the recorder cancels it. System shortcuts are captured before macOS handles them when Accessibility is granted.
- Editing settings cancels any unfinished mouse gesture or hold, including its release action. Shortcut and speed changes do not release mouse ownership. Selected controls, wheel mode, and horizontal direction reconnect automatically, retaining the enabled state. Editing while explicitly paused leaves mappings paused.
- Closing the settings window saves pending edits and exits the UI process. If saving fails, quitting is cancelled so the edits aren't lost. The agent stays in the menu bar; Pause restores controls, and Stop agent and disable startup removes its LaunchAgent.
- Sleep, disconnect, permission loss, or a restarted Logitech agent suspends the mapping. It reconnects and resumes once the mouse and permissions are available and Logitech's agent is stopped. Explicit Pause disables automatic resume; Enable turns it back on. Stopping the agent restores hardware while preserving this choice for the next launch. Quitting only the settings UI leaves mappings running.
- Main-wheel control reads high-resolution wheel reports directly from Bolt and sends vertical pixel scrolling. At 100% baseline speed, slow scrolling moves 40 pixels per notch. Acceleration estimates wheel speed from notch distance and elapsed time, then smoothly boosts fast spins. At 100% acceleration the maximum boost is 5×; at 200% it is 9×. Pausing for 250 ms, reversing direction, or editing settings clears the boost. This approximates the fast-spin behavior; Logitech’s exact curve has not been measured. Horizontal direction is controlled separately through the thumb wheel’s native hardware setting. Keyboard modifiers are preserved. This does not add inertial scrolling.
- Pause and agent shutdown restore native main-wheel scrolling and the prior wheel mode/SmartShift threshold, then clear diversion for the selected buttons and preserve their current hardware remap targets. Raw movement reporting is also cleared for every button that used it. Sleep cleanup sends restoration commands without waiting for replies.
- Zoom uses native magnification and smart-zoom events, not Command-plus/minus. An app must support those gestures. The adapter uses undocumented macOS gesture fields, so compatibility is verified against the installed OS. Zoom speed tunes movement distance; exact Logitech sensitivity has not been measured.
- On button-feature version 5 and later, the first raw movement report is discarded to avoid the MX Master 3S stale-movement jump. A small dead zone separates clicks from drags.
- The agent records native hardware settings before changing them and recovers an interrupted session before reclaiming the mouse. If recovery or restoration fails, **turn the mouse off and on**. It reconnects automatically; click Enable if you previously paused it.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same side buttons in both apps.

## Validation

The 53 core checks cover two-axis drag scrolling, scroll lifecycle and fractional pixels, click, hold, and drag in all four directions, holds cancelled by drags, continuous zoom, cancellation, jitter, the stale first-report filter, signed movement parsing, button reporting, wheel packet decoding, speed/direction, fractional-pixel accumulation, acceleration strength, packet-rate independence, slow-scroll precision, reversals, idle reset, numeric bounds, and horizontal-direction reporting flags. macOS also decodes the generated events as native magnify / smart-magnify events with the expected phases.

Run the optional hardware checks with the settings UI closed, the agent stopped (`./scripts/agent-session.sh stop`), Logitech's device agent stopped, and an awake MX Master 3S connected through Bolt:

```sh
./scripts/check-hardware.sh
```

These use separate test preferences and send no keyboard, zoom, or scroll actions. They check preference migration, custom/cleared mapping persistence, JSON config round-trips, partial files, and error messages, recorder capture/cancellation, system-shortcut parsing and arrow-key event flags, claim and restore the selected buttons, simulate sleep/wake notifications, check that Enable is ignored during sleep, and verify Pause and quit behavior. Live shortcut/speed/acceleration changes, automatic hardware updates, and disabling/re-enabling all controls are also tested. They also verify all three wheel-mode choices, both horizontal directions, and restoration on the real mouse, and decode generated pixel-scroll events with macOS. They do not put the Mac to sleep.

Verified on the MX Master 3S in Bolt slot 2 with button-feature version 5. Manual checks confirmed Back, Forward, the Forward hold shortcut, smart zoom, and held zoom at 200%. Manual checks also confirmed thumb click/up for Mission Control, down for App Exposé, and left/right for desktop switching. Live main-wheel scrolling also works in the installed build; the speed, direction, and wheel-mode controls were tried without a reported failure. Live shortcut recording and playback while enabled are confirmed. Manual comparison also confirmed that fast-spin acceleration feels right while slow scrolling stays precise. Manual checks confirmed that Standard/Reversed flips horizontal scrolling while enabled. Those checks predate per-button click/hold/drag; hold and drag on Forward, Back, and the wheel button, and the top-button shortcut click, still need a manual check.

Protocol references: [MXControl's Special Keys implementation](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Features/SpecialKeysFeature.swift) and [USB transport](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Transport/USBTransport.swift). No MXControl source is included here.

Button control IDs are documented in [Solaar's control table](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/special_keys.py).

Zoom event reference: [Mac Mouse Fix TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m). First-report quirk: [Solaar issue 1662](https://github.com/pwr-Solaar/Solaar/issues/1662). These references document protocol facts; their source is not included here.

Main-wheel protocol reference: [Solaar high-resolution wheel and SmartShift settings](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py). No Solaar source is included here.

Thumb-wheel direction reference: [Solaar thumb-wheel mode and inversion settings](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py). Only the inversion bit changes; native reporting and other flags are preserved.
