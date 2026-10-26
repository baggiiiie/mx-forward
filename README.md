# MX Forward

A small native macOS app that remaps the MX Master 3S via **Bluetooth or a Logi Bolt USB receiver**, with no Logitech runtime dependency.

Pair the mouse in macOS Bluetooth settings, or plug in its paired Bolt receiver. MX Forward discovers the connection automatically and uses the same mappings for both.

A lightweight agent owns the mouse and menu bar; the settings UI is a separate process. Everything is also editable as JSON at `~/.config/mx-forward/config.json`.

Completely LLM generated, no code is read.

## Build

Requires macOS 14+ and Swift 6 CLI tools. No third-party dependencies.

```sh
./scripts/build-app.sh
./scripts/install-app.sh
open '/Applications/MX Forward.app'
```

Close the settings UI and stop any running agent before packaging. Builds use a stable code-signing certificate (not ad-hoc, not notarized); set `MX_FORWARD_SIGN_IDENTITY` to choose one.

## Button actions

Each extra button supports click, double click, hold, and drag actions. Double click follows macOS’s double-click speed. Assigning it delays the single-click action while waiting for a second press. Left and right clicks retain their native behavior.

## Button scripts

Choose **Run script** for any button action, then choose a script or enter its absolute path (`~` is supported). Scripts must be executable (`chmod +x /path/to/script`) and start with an interpreter line such as `#!/bin/zsh` or `#!/usr/bin/env python3`.

Scripts run without opening Terminal, with their own folder as the working directory. They inherit the agent’s environment, so use absolute paths for tools outside the system PATH. Input and output go to `/dev/null`. Repeated triggers for the same script are ignored until it exits. Test mode logs the action without running it.

The equivalent JSON action is `{"script": "~/Scripts/action.sh"}`.

