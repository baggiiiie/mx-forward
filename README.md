# MX Forward

A small native macOS app for the MX Master 3S with a **Logi Bolt USB receiver**.

- Click Forward: sends **⌘]** when you release the button.
- Hold Forward: sends your recorded shortcut once, without also going Forward.
- Adjustable hold delay (150–1500 ms, initially 400 ms).
- Test mode shows actions without sending them. Pause restores normal Forward reporting.

This MVP handles Forward only. It does not replace the other Logitech gesture presets or hardware settings.

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
2. Add **MX Forward** under **System Settings → Privacy & Security → Accessibility** for live keyboard actions. Add **Input Monitoring** only if discovery is blocked. Restart after changing permissions.
3. Click **Discover mouse**. If it cannot find the mouse, move it to wake it and try again.
4. Stop Logitech's background agent with the command below. Closing the Options+ window is not enough. Its other custom gestures may stop working while the agent is stopped.
5. Keep **Test mode** on, click **Enable**, then try a short Forward press and a hold. Check the displayed actions.
6. Click **Pause**, turn Test mode off, then **Enable**. Try a click in a browser with forward history and a hold in the app where your shortcut applies.

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
- Pause and Quit clear Forward diversion and preserve its current hardware remap target. Sleep cleanup sends a restoration command without waiting for a reply.
- After a crash, forced quit, or failed restoration, **turn the mouse off and on**, then restart Logitech to restore its saved configuration.
- Bluetooth and other mouse models are not supported. Mac Mouse Fix can keep running, but avoid mapping the same Forward input in both apps.

## Validation

The core checks cover click/hold timing, cancellation, duplicate reports, packet parsing, and Forward reporting settings. The UI recorder, saved shortcut, and timing pad were also checked on this Mac.

Hardware testing found the MX Master 3S in Bolt slot 2 and confirmed claiming and restoring Forward with Test mode on. Logitech was restored afterward. Physical Forward presses and live keyboard output still need manual testing after granting Accessibility.

Protocol references: [MXControl's Special Keys implementation](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Features/SpecialKeysFeature.swift) and [USB transport](https://github.com/wiscaksono/MXControl/blob/main/Sources/MXControlHIDPP/Transport/USBTransport.swift). No MXControl source is included here.
