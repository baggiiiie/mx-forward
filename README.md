# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Click Forward: defaults to **⌘]** on release; click its shortcut to record different keys.
- Click Back: defaults to **⌘[** on release; its shortcut is configurable.
- Optional Forward hold: sends your recorded shortcut once, without also going Forward. With hold off, even a long press navigates once on release.
- Adjustable hold delay (150–1500 ms, initially 400 ms).
- Thumb-button gestures: separate recorders for click, up, down, left, and right. Defaults are Mission Control for click/up, App Exposé for down, and desktop switching for left/right. Gesture sensitivity is adjustable.
- Top button: choose Smart Zoom, a recorded keyboard shortcut, or no action for a click. Hold and move up/down for continuous pinch zoom.
- Horizontal top-button movement does not rotate or trigger smart zoom.
- Separate feature toggles let you test zoom without configuring Forward. Hold zoom speed ranges from 25–600%, initially 200%.
- Main-wheel control: scroll speed (25–600%), natural or standard direction, adjustable acceleration, and ratchet/free-spin modes. Keep current mode preserves existing SmartShift behavior. Initially off.
- Horizontal thumb-wheel direction: Keep current, Standard, or Reversed. Applies independently of the main wheel and restores the previous direction on Pause or Quit.
- Test mode shows actions without sending them. Pause restores the selected buttons.
- Settings stay editable while mappings are active. Shortcuts and speeds apply immediately; changing selected controls or wheel mode briefly reconnects automatically.
- Automatic discovery on launch, wake, and reconnect. After you Enable once, mappings resume automatically; an explicit Pause keeps them off.

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

## Try it

1. Turn **Forward** and **Back** on under **Side buttons**. Click either displayed shortcut, then press a key or combination to record it. Escape cancels; Clear disables that action, and the reset arrow restores its default. No hold shortcut is required. To add one, turn **Hold Forward for a shortcut** on, click **Record shortcut**, and press your key combination. Escape cancels. The timing pad previews the hold delay. Settings save automatically.
2. Add **MX Forward** under **System Settings → Privacy & Security → Accessibility** for live keyboard and zoom actions. Add **Input Monitoring** only if discovery is blocked. Restart after changing permissions if needed.
3. The app discovers the mouse automatically. Move it to wake it if needed and allow a few seconds. **Discover mouse** remains available for a manual retry.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then click both side buttons. Check the displayed Forward and Back actions. If Forward hold is enabled, check that a long press sends only its shortcut.
6. For zoom alone, turn **Forward** and **Back** off and keep **Enable top button** on. Choose a **Single click** action. Record its shortcut if you choose **Keyboard shortcut**.
7. Turn Test mode off while enabled, or turn it off before you Enable. Point at content in a browser or image viewer. Click the top button for your chosen action; hold it and move up to zoom in or down to zoom out. Adjust **Hold zoom speed** while enabled; higher values need less mouse movement. Click and hold actions are independent.
8. For the main wheel, turn **Control main wheel** on, choose **Scroll speed**, **Natural scrolling**, **Acceleration**, and **Wheel mode**. Acceleration starts at 100%; set it to 0% for constant speed. If mappings are already enabled, changes apply automatically. Ratchet locks the notches; Free-spin removes them. Keep current mode leaves the existing SmartShift mode and threshold untouched. These controls affect only the MX Master 3S main wheel.
9. Under **Horizontal scrolling**, choose **Thumb-wheel direction → Standard** or **Reversed**. This applies automatically while enabled. Keep current direction leaves the native setting alone.
10. **Open zoom verification** provides a native test canvas. Its buttons send real macOS gesture events; its status confirms whether they reached `magnify` / `smartMagnify` handlers. Test mode suppresses mouse actions, but these explicit verification buttons still send events into this test window.

```sh
./scripts/logitech-session.sh stop
# Pause or quit MX Forward before restoring Logitech.
./scripts/logitech-session.sh start
```

The stop command disables Logitech's automatic launch and stops its device agent. This persists across logins until the start command restores automatic launch and the agent. It expects the standard Logitech LaunchAgent. Use `./scripts/logitech-session.sh status` to check it.

## Behavior and recovery

- Side-button clicks default to **⌘[** for Back and **⌘]** for Forward. Record the shortcuts your apps or keyboard layout use instead when needed.
- Thumb gestures follow your macOS Mission Control and desktop-switching shortcuts until you record an override for that gesture. Click and hold-up are independent. Clear disables just that action; reset resumes following macOS, including disabled system shortcuts. Each press triggers one action when movement crosses the gesture threshold; release before the next gesture. Holding both gesture buttons cancels their gestures until both are released.
- Shortcuts store a keycode and modifiers and target the active app when they fire. Click a shortcut field and press your keys to replace it. Recording temporarily suppresses mouse shortcut and gesture actions; Escape, leaving the window, or disabling the recorder cancels it. System shortcuts are captured before macOS handles them when Accessibility is granted.
- Editing settings cancels any unfinished mouse gesture or hold, including its release action. Shortcut and speed changes do not release mouse ownership. Selected controls, wheel mode, and horizontal direction reconnect automatically, retaining the enabled state. Editing while explicitly paused leaves mappings paused.
- Closing the window keeps the app in the menu bar, where you can Pause or Quit.
- Sleep, disconnect, permission loss, or a restarted Logitech agent suspends the mapping. It reconnects and resumes once the mouse and permissions are available and Logitech's agent is stopped. Explicit Pause disables automatic resume; Enable turns it back on. Quit restores the hardware while preserving this choice for the next launch.
- Main-wheel control reads high-resolution wheel reports directly from Bolt and sends vertical pixel scrolling. At 100% baseline speed, slow scrolling moves 40 pixels per notch. Acceleration estimates wheel speed from notch distance and elapsed time, then smoothly boosts fast spins. At 100% acceleration the maximum boost is 5×; at 200% it is 9×. Pausing for 250 ms, reversing direction, or editing settings clears the boost. This approximates the fast-spin behavior; Logitech’s exact curve has not been measured. Horizontal direction is controlled separately through the thumb wheel’s native hardware setting. Keyboard modifiers are preserved. This does not add inertial scrolling.
- Pause and Quit restore native main-wheel scrolling and the prior wheel mode/SmartShift threshold, then clear diversion for the selected buttons and preserve their current hardware remap targets. Raw movement reporting is also cleared for both gesture buttons. Sleep cleanup sends restoration commands without waiting for replies.
- Zoom uses native magnification and smart-zoom events, not Command-plus/minus. An app must support those gestures. The adapter uses undocumented macOS gesture fields, so compatibility is verified against the installed OS. The sensitivity control tunes movement distance; exact Logitech sensitivity has not been measured.
- On button-feature version 5 and later, the first raw movement report is discarded to avoid the MX Master 3S stale-movement jump. A small dead zone separates clicks from gestures.
- After a crash, forced quit, or failed restoration, **turn the mouse off and on**. The app reconnects automatically; click Enable if you previously paused it.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same side buttons in both apps.

## Validation

The 68 core checks cover independent Forward/Back clicks, Forward holds, thumb gestures in all directions, overlapping gesture buttons, cancellation, continuous zoom, jitter, the stale first-report filter, signed movement parsing, button reporting, wheel packet decoding, speed/direction, fractional-pixel accumulation, acceleration strength, packet-rate independence, slow-scroll precision, reversals, idle reset, numeric bounds, and horizontal-direction reporting flags. macOS also decodes the generated events as native magnify / smart-magnify events with the expected phases.

Run the optional hardware checks with MX Forward quit, Logitech's device agent stopped, and an awake MX Master 3S connected through Bolt:

```sh
./scripts/check-hardware.sh
```

These use separate test preferences and send no keyboard, zoom, or scroll actions. They check preference migration, custom/cleared mapping persistence, recorder capture/cancellation, system-shortcut parsing and arrow-key event flags, claim and restore the selected buttons, simulate sleep/wake notifications, check that Enable is ignored during sleep, and verify Pause and quit behavior. Live shortcut/speed/acceleration changes, automatic hardware updates, and disabling/re-enabling all controls are also tested. They also verify all three wheel-mode choices, both horizontal directions, and restoration on the real mouse, and decode generated pixel-scroll events with macOS. They do not put the Mac to sleep.

Verified on the MX Master 3S in Bolt slot 2 with button-feature version 5. Manual checks confirmed Back, Forward, the Forward hold shortcut, smart zoom, and held zoom at 200%. Manual checks also confirmed thumb click/up for Mission Control, down for App Exposé, and left/right for desktop switching. Live main-wheel scrolling also works in the installed build; the speed, direction, and wheel-mode controls were tried without a reported failure. Live shortcut recording and playback while enabled are confirmed. Manual comparison also confirmed that fast-spin acceleration feels right while slow scrolling stays precise. Manual checks confirmed that Standard/Reversed flips horizontal scrolling while enabled. The top-button keyboard-shortcut click action still needs a manual check.

Protocol references: [MXControl's Special Keys implementation](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Features/SpecialKeysFeature.swift) and [USB transport](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Transport/USBTransport.swift). No MXControl source is included here.

Button control IDs are documented in [Solaar's control table](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/special_keys.py).

Zoom event reference: [Mac Mouse Fix TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m). First-report quirk: [Solaar issue 1662](https://github.com/pwr-Solaar/Solaar/issues/1662). These references document protocol facts; their source is not included here.

Main-wheel protocol reference: [Solaar high-resolution wheel and SmartShift settings](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py). No Solaar source is included here.

Thumb-wheel direction reference: [Solaar thumb-wheel mode and inversion settings](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/settings_templates.py). Only the inversion bit changes; native reporting and other flags are preserved.
