# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Click Forward: sends **⌘]** when you release the button.
- Click Back: sends **⌘[** when you release the button.
- Optional Forward hold: sends your recorded shortcut once, without also going Forward. With hold off, even a long press navigates once on release.
- Adjustable hold delay (150–1500 ms, initially 400 ms).
- Top button: choose Smart Zoom, a recorded keyboard shortcut, or no action for a click. Hold and move up/down for continuous pinch zoom.
- Horizontal top-button movement does not rotate or trigger smart zoom.
- Separate feature toggles let you test zoom without configuring Forward. Hold zoom speed ranges from 25–600%, initially 200%.
- Test mode shows actions without sending them. Pause restores the selected buttons.
- Automatic discovery on launch, wake, and reconnect. After you Enable once, mappings resume automatically; an explicit Pause keeps them off.

The app talks directly to the Bolt receiver. Logitech's device agent must stay stopped; there is no Logitech runtime dependency. Thumb-button window gestures, rotation, and hardware-settings controls are not implemented yet.

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

1. Turn **Forward** and **Back** on under **Side buttons**. No hold shortcut is required. To add one, turn **Hold Forward for a shortcut** on, click **Record shortcut**, and press your key combination. Escape cancels. The timing pad previews the hold delay. Settings save automatically.
2. Add **MX Forward** under **System Settings → Privacy & Security → Accessibility** for live keyboard and zoom actions. Add **Input Monitoring** only if discovery is blocked. Restart after changing permissions if needed.
3. The app discovers the mouse automatically. Move it to wake it if needed and allow a few seconds. **Discover mouse** remains available for a manual retry.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then click both side buttons. Check the displayed Forward and Back actions. If Forward hold is enabled, check that a long press sends only its shortcut.
6. For zoom alone, turn **Forward** and **Back** off and keep **Enable top button** on. Choose a **Single click** action. Record its shortcut if you choose **Keyboard shortcut**.
7. Click **Pause**, turn Test mode off, then **Enable**. Point at content in a browser or image viewer. Click the top button for your chosen action; hold it and move up to zoom in or down to zoom out. Pause to adjust **Hold zoom speed**; higher values need less mouse movement. Click and hold actions are independent.
8. **Open zoom verification** provides a native test canvas. Its buttons send real macOS gesture events; its status confirms whether they reached `magnify` / `smartMagnify` handlers. Test mode suppresses mouse actions, but these explicit verification buttons still send events into this test window.

```sh
./scripts/logitech-session.sh stop
# Pause or quit MX Forward before restoring Logitech.
./scripts/logitech-session.sh start
```

The script stops/restores Logitech for the current login session; it does not uninstall it or change automatic startup. It expects the standard Logitech LaunchAgent. Use `./scripts/logitech-session.sh status` to check it.

## Behavior and recovery

- Side-button navigation sends **⌘[** for Back and **⌘]** for Forward. These use US bracket keycodes; apps or keyboard layouts with different navigation shortcuts may behave differently.
- Shortcuts store a keycode and modifiers and target the active app when they fire. Pause before changing the mapping.
- Closing the window keeps the app in the menu bar, where you can Pause or Quit.
- Sleep, disconnect, permission loss, or a restarted Logitech agent suspends the mapping. It reconnects and resumes once the mouse and permissions are available and Logitech's agent is stopped. Explicit Pause disables automatic resume; Enable turns it back on. Quit restores the hardware while preserving this choice for the next launch.
- Pause and Quit clear diversion for the selected buttons and preserve their current hardware remap targets. Top-button raw movement reporting is also cleared. Sleep cleanup sends restoration commands without waiting for replies.
- Zoom uses native magnification and smart-zoom events, not Command-plus/minus. An app must support those gestures. The adapter uses undocumented macOS gesture fields, so compatibility is verified against the installed OS. The sensitivity control tunes movement distance; exact Logitech sensitivity has not been measured.
- On button-feature version 5 and later, the first raw movement report is discarded to avoid the MX Master 3S stale-movement jump. A small dead zone separates clicks from gestures.
- After a crash, forced quit, or failed restoration, **turn the mouse off and on**. The app reconnects automatically; click Enable if you previously paused it.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same side buttons in both apps.

## Validation

The 38 core checks cover independent Forward/Back clicks, simultaneous Back presses during a Forward hold, duplicate reports, cancellation, Forward timing, continuous zoom phases, reversal, horizontal suppression, jitter, the stale first-report filter, signed movement parsing, and button reporting. macOS also decodes the generated events as native magnify / smart-magnify events with the expected phases.

Run the optional hardware checks with MX Forward quit, Logitech's device agent stopped, and an awake MX Master 3S connected through Bolt:

```sh
./scripts/check-hardware.sh
```

These use separate test preferences and send no keyboard or zoom actions. They claim and restore the three buttons, simulate sleep/wake notifications, check that Enable is ignored during sleep, and verify Pause and quit behavior. They do not put the Mac to sleep.

Verified on the MX Master 3S in Bolt slot 2 with button-feature version 5. Hardware checks passed, and receiver readback confirmed automatic startup claims with movement enabled only for the top button. Manual checks confirmed Back, Forward, the Forward hold shortcut, smart zoom, and held zoom at 200%. The top-button keyboard-shortcut click action has not been manually verified.

Protocol references: [MXControl's Special Keys implementation](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Features/SpecialKeysFeature.swift) and [USB transport](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Transport/USBTransport.swift). No MXControl source is included here.

Button control IDs are documented in [Solaar's control table](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/special_keys.py).

Zoom event reference: [Mac Mouse Fix TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m). First-report quirk: [Solaar issue 1662](https://github.com/pwr-Solaar/Solaar/issues/1662). These references document protocol facts; their source is not included here.
