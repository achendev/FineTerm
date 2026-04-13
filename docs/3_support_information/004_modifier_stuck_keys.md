# Support: Stuck Keys & Strict Apps (Modifiers on KeyUp)

## 1. Symptom Description
*   **User Report:** "When I map `Caps Lock` to `F20`, and then map `F20` to `Cmd + V`, it works in some apps but not in Terminal or Chrome."
*   **Context:** Occurs specifically when a trigger relies on an overridden modifier key that executes a shortcut (like `Cmd + C` or `Cmd + V`), and the target application is very strict about input event sequences.

## 2. Root Cause Analysis
*   **Cause:** Strict apps (like Chrome, Terminal) validate the modifier state of both the `keyDown` and `keyUp` events. Previously, `PCModeProcessor` successfully attached the `Command` modifier to the `keyDown` event for `v`, but when the user released the key, it sent a `keyUp` for `v` *without* the `Command` modifier. The app sees "Cmd + V down, V up without Cmd" and cancels the paste operation.
*   **Why it wasn't caught:** Native macOS apps (like TextEdit) only care about the `keyDown` event for triggering shortcuts and ignore the malformed `keyUp`.

## 3. Resolution
*   **Code Fix:** Implemented exact `CGEventFlags` retention inside `PCModeProcessor.activeRemaps`. 
*   When a rule fires, the processor stores a tuple of both the mapped `keyCode` and the exact `flags` used.
*   When the trigger key is released, it retrieves this tuple and forcefully applies the exact same modifier flags to the injected `.keyUp` event, ensuring the Window Server receives a perfectly symmetrical press/release sequence.