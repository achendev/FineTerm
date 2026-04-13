# Support: Fast Modifier Release Sticking (Language Switcher Popup)

## 1. Symptom Description
*   **User Report:** "When I press `Opt + Shift` fast to switch languages, it shows a micro popup of two languages and gets stuck as if I'm still holding `Ctrl + Opt + Space`."
*   **Context:** Occurs when using PC Mode rules to remap modifier-only shortcuts (like `Opt + Shift` -> `Ctrl + Opt + Spacebar`) and releasing the keys quickly in a specific order.

## 2. Root Cause Analysis
*   **Cause:** When the user releases the non-trigger modifier (e.g., `Opt`) *before* releasing the trigger modifier (e.g., `Shift`), the `flagsChanged` event for the `Opt` release was falling through the `activeRemaps` check. The event then incorrectly matched the rule again, but because it was a release (`isPress = false`), the processor returned `true` (swallowing the event) without sending any corresponding `KeyUp` or `flagsChanged` to the OS.
*   **Effect:** The OS never saw the `Opt` key go up, so it thought `Opt` was permanently held down, causing the macOS language switcher HUD to remain visible on screen until `Opt` was tapped again.

## 3. Resolution
*   **Code Fix:** Updated `PCModeProcessor.swift` to immediately return `false` for ALL unremapped `.keyUp` and `.flagsChanged` (release) events. If a key's press was not remapped (and therefore not placed in `activeRemaps`), its release MUST automatically pass through to the OS to ensure the system modifier state remains synchronized with the physical keyboard state.