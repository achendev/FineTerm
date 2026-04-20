#[005] Karabiner-Elements Engine Integration & LocalActionServer

## 1. Summary
FineTerm allows users to offload "PC Mode" execution to **Karabiner-Elements**. To make this work flawlessly (and fix latency on App Switching), FineTerm establishes a native, lightning-fast UDP communication bridge with Karabiner instead of using sluggish URL schemes.

## 2. LocalActionServer (UDP)
Previously, if you pressed `Right Cmd` to trigger a Custom App Shortcut in Karabiner Mode, Karabiner executed `open -g fineterm://action/...`. This required spinning up a LaunchServices process, validating the URL, sending an AppleEvent, and then triggering FineTerm. This process took ~200ms.
*   **The Bleeding Bug:** Because the switch took 200ms, if you typed `L` `S` `Enter` immediately after pressing the shortcut, the letters would "bleed" into your secure password field instead of hitting the new app.
*   **The Fix:** FineTerm now runs a native `NWListener` (UDP Server) on `127.0.0.1:61234`. Karabiner is instructed to run a native Bash command: `/bin/bash -c "echo -n 'fineterm/...' > /dev/udp/127.0.0.1/61234"`.
*   **The Result:** The action is transmitted, parsed, and executed in **< 1 millisecond**, making app switching feel entirely native and instantly severing the event stream to the password field.

## 3. The Double-Swap Bug
When `pcModeEngine` is set to `1` (Full Karabiner), `SystemModifierManager.swift` forcefully unloads its `hidutil` bindings. Karabiner natively exports System Modifiers globally via `karabiner.json`. If `hidutil` was left running alongside it, the OS would apply the physical swap via Karabiner (e.g. `Cmd` -> `Opt`), and then `hidutil` would see the new state and swap it again. This caused the "Ctrl+Backspace deletes a letter instead of a word" and broken app switching issues.

## 4. The Caps Lock Chaining Bug
Karabiner evaluates Complex Modifications sequentially but does NOT inherently chain them. If the user mapped Caps Lock to `F20` via System Modifiers, and mapped `F20 -> func:paste` in PC Mode Rules, pressing Caps Lock would just output `F20` and stop. `KarabinerExporter` now automatically injects a duplicate underlying rule targeting `caps_lock` explicitly whenever `F20` is referenced and Caps Lock is physically mapped to it.

## 5. Elimination of Hybrid Mode
Previous iterations attempted to poll the WindowServer 10 times a second to toggle a `fineterm_secure_input` variable dynamically. This caused high WindowServer CPU usage and unacceptable delays. Hybrid mode was removed. Users now simply choose between "Internal (Fastest)" for standard usage or "Karabiner (Full)" for uncompromising Secure Input compatibility.