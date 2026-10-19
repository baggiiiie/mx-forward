# MX Forward

A small native macOS app that remaps the MX Master 3S via a **Logi Bolt USB receiver**, with no Logitech runtime dependency.

Each button (Forward, Back, Gesture, Top, wheel press) supports click, hold, and hold-and-drag actions: recorded shortcuts, Mission Control, App Exposé, desktop switch, Smart Zoom, middle click, continuous zoom, or scroll & navigate. Both wheels have speed and direction settings; the main wheel also has acceleration and ratchet settings.

Thumb-wheel speed ranges from 25–600% (`thumbWheel.speedPercent` in JSON). At 100% it keeps native scrolling. Other speeds use a constant multiplier and follow macOS Natural Scrolling.

A lightweight agent owns the mouse and menu bar; the settings UI is a separate process. Everything is also editable as JSON at `~/.config/mx-forward/config.json`.

Choose **Click with modifier** to send a left click with recorded modifier keys. Hold the keys together and release them to save. In JSON, use an action like `"click": {"clickWithModifiers": ["cmd", "shift"]}`.

## Build

Requires macOS 14+ and Swift 6 CLI tools. No third-party dependencies.

```sh
./scripts/build-app.sh
./scripts/install-app.sh
open '/Applications/MX Forward.app'
```

Close the settings UI and stop any running agent before packaging. Builds use a stable code-signing certificate (not ad-hoc, not notarized); set `MX_FORWARD_SIGN_IDENTITY` to choose one.

