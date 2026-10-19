# MX Forward

A small native macOS app that remaps the MX Master 3S via a **Logi Bolt USB receiver**, with no Logitech runtime dependency.

Each button (Forward, Back, Gesture, Top, wheel press) supports click, hold, and hold-and-drag actions: recorded shortcuts, Mission Control, App Exposé, desktop switch, Smart Zoom, middle click, continuous zoom, or scroll & navigate. Main-wheel speed/direction/ratchet and thumb-wheel direction are also configurable.

A lightweight agent owns the mouse and menu bar; the settings UI is a separate process. Everything is also editable as JSON at `~/.config/mx-forward/config.json`.

## Build

Requires macOS 14+ and Swift 6 CLI tools. No third-party dependencies.

```sh
./scripts/build-app.sh
./scripts/install-app.sh
open '/Applications/MX Forward.app'
```

Close the settings UI and stop any running agent before packaging. Builds use a stable code-signing certificate (not ad-hoc, not notarized); set `MX_FORWARD_SIGN_IDENTITY` to choose one.

