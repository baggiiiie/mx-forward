# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Every clickable button (Forward, Back, Gesture, Top, and pressing the wheel) has the same three kinds of action: **click**, **hold**, and **hold and drag** up, down, left, or right. Each slot can send a recorded shortcut, Mission Control, App Exposé, a desktop switch, Smart Zoom, a middle click, or nothing. Up and down can also zoom continuously.
- Defaults: Forward clicks **⌘]**, Back clicks **⌘[**. The gesture button opens Mission Control on click and drag up, App Exposé on drag down, and switches desktops on drag left/right. The top button Smart Zooms on click and pinch-zooms while dragged up or down. The wheel button starts off; turning it on replaces the native middle click with its actions.
- A hold fires once after the button's hold delay (150–1500 ms, initially 400 ms), and the click then doesn't fire. With no hold action, a long press is a click. Dragging before the hold delay cancels the hold.
- **Scroll & navigate**: select this in any drag-direction menu to link all four directions. Hold the button and move the mouse to scroll in two dimensions, with content following your hand like a trackpad. The cursor moves too (replayed from raw mouse movement; native pointer acceleration is not reproduced). Scroll speed is adjustable (25–300%). Uses native phased pixel-scroll events; navigation gestures depend on the receiving app. No momentum or multi-finger desktop gestures.
- Drag sensitivity (25–300%) and zoom speed (25–600%, initially 200%) are set per button.
- Main-wheel control: scroll speed (25–600%), natural or standard direction, adjustable acceleration, and ratchet/free-spin modes. Keep current mode preserves existing SmartShift behavior. Initially off.
- Horizontal thumb-wheel direction: Keep current, Standard, or Reversed. Applies independently of the main wheel and restores the previous direction on Pause or Quit.
- Test mode shows actions without sending them; Scroll & navigate still moves the cursor. Pause restores the selected buttons.
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
./scripts/build-app.sh
open 'dist/MX Forward.app'
```

Quit MX Forward before rebuilding. Builds are ad-hoc signed by default; macOS may require you to grant permissions again after a rebuild. Set `MX_FORWARD_SIGN_IDENTITY` to use your signing certificate. Builds are not notarized.

## Headless measurement prototype

This is an experimental build target, **not yet a LaunchAgent or a split UI/IPC implementation**.
It compiles the same mouse engine without SwiftUI, settings windows, shortcut recorder, or zoom-test window.
AppKit remains available for session notifications and event support. The existing GUI is unchanged.

```sh
./scripts/build-headless.sh
./scripts/build-headless.sh --check  # hardware-free isolation/regression checks
.build/headless/MXForwardHeadless --offline
```

`--offline` constructs the engine and runs its monitoring tasks, but never opens HID devices,
reads the config file, or claims controls. It can run alongside the GUI for a baseline.
Measure it in another terminal:

```sh
footprint -p "$(pgrep -x MXForwardHeadless)" --noCategories
ps -p "$(pgrep -x MXForwardHeadless)" -o pid,%cpu,rss
```

An initial optimized-build measurement on this Mac was **7.6 MB physical footprint** and
0.0% CPU in four snapshots, versus about **100 MB** for the existing GUI after closing its
window. This is **not an active-mouse comparison**: receiver discovery, claims, event output,
permissions, and activity can increase the headless footprint. The GUI measurement also
included prior window use. These numbers establish feasibility, not a guaranteed saving.

A subsequent live run, after granting Accessibility and Input Monitoring, connected to
Bolt slot 2 and enabled the normal JSON mappings with Test mode off. Six samples over
25 seconds measured **8.7–8.8 MB physical footprint**, about **37 MB RSS**, and **0.0–0.4% CPU**.
No suspension was reported during this interval. Relative to the earlier closed-window
GUI baseline, this is about **91 MB / 91% less physical footprint**. This is a short
mappings-enabled sample, not a controlled gesture stress test or a long-term soak test.

For the real comparison, **quit MX Forward completely**, leave Logitech's agent stopped,
and then run:

```sh
.build/headless/MXForwardHeadless --enable
```

Without `--enable` it only discovers the mouse. Live modes read and watch the normal JSON
config but never save settings or change the GUI's persisted resume choice. They start
from built-in preferences plus that JSON, not the GUI's UserDefaults. The separate executable
may need its own Accessibility/Input Monitoring permission; check the printed status.
Do not reopen the GUI while a live prototype is running. The prototype refuses to start
while the GUI is running and locks out duplicate live prototype instances.

Stop with **Ctrl-C** or `kill -TERM <pid>`; it waits for the current operation and attempts
native-control restoration before exiting. A failed restoration is printed and returns a
nonzero exit status; power-cycle the mouse if needed. Never use SIGKILL for normal shutdown.
No service is installed, and no login/startup settings are changed.

## Try it

1. In the **Buttons** tab, click a button on the mouse picture. Pick an action for its click, hold, and each drag direction. For **Keyboard shortcut**, click the recorder and press your keys; Escape cancels. **Restore defaults** resets the button. The timing pad previews the hold delay. Settings save automatically.
2. Add **MX Forward** under **System Settings → Privacy & Security → Accessibility** for live keyboard and zoom actions. Add **Input Monitoring** only if discovery is blocked. Restart after changing permissions if needed.
3. The app discovers the mouse automatically. Move it to wake it if needed and allow a few seconds. **Discover mouse** remains available for a manual retry.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then click, hold, and drag each button. The footer shows which action each one would send, such as "Back hold → Mission Control".
6. Turn Test mode off while enabled, or turn it off before you Enable. Point at content in a browser or image viewer. Click the top button for Smart Zoom; hold it and move up to zoom in or down to zoom out. Higher **Zoom speed** needs less mouse movement.
7. For the main wheel, select it on the mouse picture, turn **Control main wheel** on, choose **Scroll speed**, **Natural scrolling**, **Acceleration**, and **Wheel mode**. Acceleration starts at 100%; set it to 0% for constant speed. If mappings are already enabled, changes apply automatically. Ratchet locks the notches; Free-spin removes them. Keep current mode leaves the existing SmartShift mode and threshold untouched. These controls affect only the MX Master 3S main wheel.
8. Select the **Thumb wheel** and choose **Standard** or **Reversed**. This applies automatically while enabled. Keep current direction leaves the native setting alone.
9. **Open zoom verification** (Top button or **Setup** tab) provides a native test canvas. Its buttons send real macOS gesture events; its status confirms whether they reached `magnify` / `smartMagnify` handlers. Test mode suppresses mouse actions, but these explicit verification buttons still send events into this test window.

```sh
./scripts/logitech-session.sh stop
# Pause or quit MX Forward before restoring Logitech.
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
- Closing the window keeps the app in the menu bar, where you can Pause or Quit.
- Sleep, disconnect, permission loss, or a restarted Logitech agent suspends the mapping. It reconnects and resumes once the mouse and permissions are available and Logitech's agent is stopped. Explicit Pause disables automatic resume; Enable turns it back on. Quit restores the hardware while preserving this choice for the next launch.
- Main-wheel control reads high-resolution wheel reports directly from Bolt and sends vertical pixel scrolling. At 100% baseline speed, slow scrolling moves 40 pixels per notch. Acceleration estimates wheel speed from notch distance and elapsed time, then smoothly boosts fast spins. At 100% acceleration the maximum boost is 5×; at 200% it is 9×. Pausing for 250 ms, reversing direction, or editing settings clears the boost. This approximates the fast-spin behavior; Logitech’s exact curve has not been measured. Horizontal direction is controlled separately through the thumb wheel’s native hardware setting. Keyboard modifiers are preserved. This does not add inertial scrolling.
- Pause and Quit restore native main-wheel scrolling and the prior wheel mode/SmartShift threshold, then clear diversion for the selected buttons and preserve their current hardware remap targets. Raw movement reporting is also cleared for every button that used it. Sleep cleanup sends restoration commands without waiting for replies.
- Zoom uses native magnification and smart-zoom events, not Command-plus/minus. An app must support those gestures. The adapter uses undocumented macOS gesture fields, so compatibility is verified against the installed OS. Zoom speed tunes movement distance; exact Logitech sensitivity has not been measured.
- On button-feature version 5 and later, the first raw movement report is discarded to avoid the MX Master 3S stale-movement jump. A small dead zone separates clicks from drags.
- After a crash, forced quit, or failed restoration, **turn the mouse off and on**. The app reconnects automatically; click Enable if you previously paused it.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same side buttons in both apps.

## Validation

The 53 core checks cover two-axis drag scrolling, scroll lifecycle and fractional pixels, click, hold, and drag in all four directions, holds cancelled by drags, continuous zoom, cancellation, jitter, the stale first-report filter, signed movement parsing, button reporting, wheel packet decoding, speed/direction, fractional-pixel accumulation, acceleration strength, packet-rate independence, slow-scroll precision, reversals, idle reset, numeric bounds, and horizontal-direction reporting flags. macOS also decodes the generated events as native magnify / smart-magnify events with the expected phases.

Run the optional hardware checks with MX Forward quit, Logitech's device agent stopped, and an awake MX Master 3S connected through Bolt:

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
