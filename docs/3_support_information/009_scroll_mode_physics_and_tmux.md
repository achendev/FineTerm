# Support: Scroll Mode Inertia & Tmux Compatibility

## 1. Symptom Description
*   **User Report:** "Scroll mode lacks trackpad inertia if I keep holding the modifier keys but lift my finger from the trackpad. Also, scrolling doesn't work inside `tmux` unless I release the shortcut first (only inertia works). Background scrolling works fine, though."

## 2. Root Cause Analysis
*   **No Inertia:** macOS `MultitouchSupport` generates inertia natively. Since we are translating standard `mouseMoved` events, the moment the finger lifts, events stop. If the user keeps holding the activation shortcut, the previous script never triggered the momentum phase.
*   **Tmux Compatibility (Foreground App Internal State):** When a terminal window is actively focused, its internal responder chain receives the initial `flagsChanged` event when the user physically presses a modifier (like `Shift`). Even if we inject modifier-free scroll events via `cgSessionEventTap`, the Terminal application *pollutes* those scroll events with its own internal memory of the modifier state, interpreting it as `Shift + Scroll`, which overrides `tmux` reporting. Background windows bypass this responder chain, which is why it worked perfectly when the terminal was out of focus.
*   **Tmux Compatibility (Accumulation):** Terminals need perfectly structured `CGEvent` scroll wheels containing both integer `wheel1` and continuous `PointDeltaAxis` fields to properly accumulate lines for ANSI escape injection. Also `ScrollPhase` values must perfectly map to Apple's `CGScrollPhase` (ended = 4).

## 3. Resolution
*   **Modifier State Flush (The Fix):** On activation, `ScrollModeManager` now injects fake `flagsChanged` events (with empty flag sets) directly into `.cgSessionEventTap` for all major modifier keys (`Shift`, `Ctrl`, `Opt`, `Cmd`). This explicitly tells the focused application to clear its internal modifier memory, guaranteeing the subsequent scroll events are not artificially modified. On deactivation, the actual physical hardware state is queried and restored.
*   **Cursor Freeze:** `ScrollModeManager` actively calls `CGWarpMouseCursorPosition` to lock the pointer.
*   **Physics Engine & Lift Detection:** Implemented a real-time velocity tracker and a 50ms "Fling Detector". If events stop abruptly but velocity was high, it automatically starts a 60fps decaying friction timer simulating native trackpad momentum, even if the modifier key is still held.