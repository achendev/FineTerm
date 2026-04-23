# Support: App locks cursor forever / Must kill via keyboard

## 1. Symptom Description
*   **User Report:** "When I use Scroll Mode (or sometimes just randomly), the mouse cursor gets stuck in place. I have to switch to Terminal using Cmd+Tab and kill the app using the keyboard."
*   **Context:** Occurred immediately after adding a dynamic toggle for the `CGEventTap` listening to mouse movements (to reduce CPU usage).

## 2. Root Cause Analysis
*   **Cause:** macOS fires a generic callback event with `type == .tapDisabledByUserInput` when you explicitly call `CGEvent.tapEnable(..., enable: false)`. 
*   Our original tap callback was checking `if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput` and responding by indiscriminately calling `CGEvent.tapEnable(..., enable: true)`.
*   **The Chain Reaction:**
    1. User releases the Scroll Mode trigger.
    2. `ScrollModeManager` disables the tap via code to save CPU.
    3. macOS immediately fires `.tapDisabledByUserInput` into the callback.
    4. The callback immediately re-enables the tap.
    5. The tap continues to intercept mouse movements.
    6. `ScrollModeManager` (now with `isActive = false`) receives those movements, and calls `CGWarpMouseCursorPosition(anchorPoint)`, permanently trapping the mouse exactly where it was.

## 3. Resolution
*   **Code Fix:** Updated all three interceptor classes (`MouseInterceptor`, `KeyboardInterceptor`, and `ScrollModeManager`) to explicitly separate the two disabled states:
    *   `.tapDisabledByTimeout` -> Safely re-enable the tap.
    *   `.tapDisabledByUserInput` -> Do **NOT** re-enable. Let it pass unretained.
*   Added a secondary safety check in `ScrollModeManager` to explicitly return `Unmanaged.passUnretained(event)` if `!isActive`, guaranteeing that even if a rogue event slips through, it cannot hijack the cursor.