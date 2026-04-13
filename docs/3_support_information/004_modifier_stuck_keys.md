# Support: Stuck Keys on Modifier-Only Shortcuts

## 1. Symptom Description
*   **User Report:** "When I map `opt + shift` to `ctrl + opt + space` (e.g. for a language switch), it works once, but then gets stuck. I have to press the keys physically to unstick it."
*   **Context:** Occurs specifically when a trigger definition relies purely on modifier keys (like `opt + shift`) instead of standard keys (like `ctrl + c`), combined with a mapping output to a standard key.

## 2. Root Cause Analysis
*   **Cause:** When pressing purely modifier-based triggers, macOS posts `.flagsChanged` events rather than `.keyDown` events. Previously, the `KeyboardInterceptor` correctly identified the modifier press and dispatched a mapped `.keyDown` for the target standard key (e.g., `space`), but it lacked logic to detect the modifier *release* and dispatch the corresponding `.keyUp`. This left the `space` key physically "pressed" globally in the macOS Window Server's eyes.
*   **Why it wasn't caught:** Standard bindings (like `ctrl + c`) utilize standard `.keyUp` events for their releases, which had functioning tracker logic (`activeRemaps`) to intercept and unstick correctly.

## 3. Resolution
*   **Code Fix:** Implemented robust "Un-stick" logic for modifier releases inside `processPCModeRules`. The code now tracks mappings initiated by `.flagsChanged` and actively monitors when those specific modifier flags are lifted. Once the flag goes down (e.g., the user lifts their finger off the `Shift` key), it dynamically retrieves the mapped key from `activeRemaps` and instantly fires the exact required `.keyUp` event to release it properly into the system event stream.