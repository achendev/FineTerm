# Support: Scroll Mode Inertia & Tmux Compatibility

## 1. Symptom Description
*   **User Report:** "Scroll mode lacks trackpad inertia if I keep holding the modifier keys but lift my finger from the trackpad. Also, scrolling doesn't work inside `tmux`."

## 2. Root Cause Analysis
*   **No Inertia:** macOS `MultitouchSupport` generates inertia natively. Since we are translating standard `mouseMoved` events, the moment the finger lifts, events stop. If the user keeps holding the activation shortcut, the previous script never triggered the momentum phase.
*   **Tmux Compatibility:** Terminals need perfectly structured `CGEvent` scroll wheels containing both integer `wheel1` and continuous `PointDeltaAxis` fields to properly accumulate lines for ANSI escape injection.

## 3. Resolution
*   **Cursor Freeze:** `ScrollModeManager` actively calls `CGWarpMouseCursorPosition` to lock the pointer.
*   **Physics Engine & Lift Detection:** Implemented a real-time velocity tracker and a 50ms "Fling Detector". If events stop abruptly but velocity was high, it automatically starts a 60fps decaying friction timer simulating native trackpad momentum, even if the modifier key is still held.
*   **High-Res Events:** Emits continuous `.pixel` events with `scrollWheelEventPointDeltaAxis1` populated, ensuring both smooth scrolling in browsers and perfect accumulation in `tmux`.