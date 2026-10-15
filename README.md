# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Click Forward: sends **⌘]** when you release the button.
- Hold Forward: sends your recorded shortcut once, without also going Forward.
- Adjustable hold delay (150–1500 ms, initially 400 ms).
- Top button: choose Smart Zoom, a recorded keyboard shortcut, or no action for a click. Hold and move up/down for continuous pinch zoom.
- Horizontal top-button movement does not rotate or trigger smart zoom.
- Separate feature toggles let you test zoom without configuring Forward. Hold zoom speed ranges from 25–600%, initially 200%.
- Test mode shows actions without sending them. Pause restores both buttons.

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

1. Click **Record shortcut**, then press your key combination. Escape cancels. The timing pad lets you try the hold delay without changing the mouse. Settings save automatically.
2. Add **MX Forward** under **System Settings → Privacy & Security → Accessibility** for live keyboard and zoom actions. Add **Input Monitoring** only if discovery is blocked. Restart after changing permissions if needed.
3. Click **Discover mouse**. If it cannot find the mouse, move it to wake it and try again.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then try a short Forward press and a hold. Check the displayed actions.
6. For zoom alone, turn **Forward click / hold** off and keep **Enable top button** on. Choose a **Single click** action. Record its shortcut if you choose **Keyboard shortcut**. No Forward shortcut is required in this mode.
7. Click **Pause**, turn Test mode off, then **Enable**. Point at content in a browser or image viewer. Click the top button for your chosen action; hold it and move up to zoom in or down to zoom out. Pause to adjust **Hold zoom speed**; higher values need less mouse movement. Click and hold actions are independent.
8. **Open zoom verification** provides a native test canvas. Its buttons send real macOS gesture events; its status confirms whether they reached `magnify` / `smartMagnify` handlers. Test mode suppresses mouse actions, but these explicit verification buttons still send events into this test window.

```sh
./scripts/logitech-session.sh stop
# Pause or quit MX Forward before restoring Logitech.
./scripts/logitech-session.sh start
```

The script stops/restores Logitech for the current login session; it does not uninstall it or change automatic startup. It expects the standard Logitech LaunchAgent. Use `./scripts/logitech-session.sh status` to check it.

## Behavior and recovery

- Forward uses **⌘]**, not Logitech's native swipe gesture. This assumes the US right-bracket key; apps or keyboard layouts with another Forward shortcut may behave differently.
- Shortcuts store a keycode and modifiers and target the active app when they fire. Pause before changing the mapping.
- Closing the window keeps the app in the menu bar, where you can Pause or Quit.
- Sleep, disconnect, permission loss, or a restarted Logitech agent pauses the mapping. Discover and Enable again after reconnecting.
- Pause and Quit clear diversion for the selected buttons and preserve their current hardware remap targets. Top-button raw movement reporting is also cleared. Sleep cleanup sends restoration commands without waiting for replies.
- Zoom uses native magnification and smart-zoom events, not Command-plus/minus. An app must support those gestures. The adapter uses undocumented macOS gesture fields, so compatibility is verified against the installed OS. The sensitivity control tunes movement distance; exact Logitech sensitivity has not been measured.
- On button-feature version 5 and later, the first raw movement report is discarded to avoid the MX Master 3S stale-movement jump. A small dead zone separates clicks from gestures.
- After a crash, forced quit, or failed restoration, **turn the mouse off and on**, then Discover and Enable again in MX Forward.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same Forward input in both apps.

## Validation

The core checks cover Forward timing, continuous zoom phases, reversal, horizontal suppression, jitter, cancellation, the stale first-report filter, signed movement parsing, and button reporting. macOS also decodes the generated events as native magnify / smart-magnify events with the expected phases.

Hardware testing found the MX Master 3S in Bolt slot 2 and confirmed claiming and restoring Forward and the top button. The top button supports raw movement reports, with the version-5 first-report quirk. With Logitech stopped and Accessibility granted, the native verification canvas received real posted magnification and smart-zoom events. The user confirmed physical top-button smart zoom and held movement work, and confirmed that 200% hold zoom speed feels better. The configurable keyboard-shortcut click action has not been manually verified.

Protocol references: [MXControl's Special Keys implementation](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Features/SpecialKeysFeature.swift) and [USB transport](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Transport/USBTransport.swift). No MXControl source is included here.

Zoom event reference: [Mac Mouse Fix TouchSimulator](https://github.com/noah-nuebling/mac-mouse-fix/blob/master/Helper/Core/Touch/TouchSimulator.m). First-report quirk: [Solaar issue 1662](https://github.com/pwr-Solaar/Solaar/issues/1662). These references document protocol facts; their source is not included here.
