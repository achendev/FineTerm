# Support: Remapping Mouse Buttons in PC Mode

## 1. Symptom Description
*   **User Report:** "I created a PC Mode rule mapping `button2` (Right Click) to `button3` (Middle Click), but nothing happens."
*   **Context:** PC Mode rules previously only listened to the `KeyboardInterceptor`, meaning physical mouse button presses weren't captured by the rule engine.

## 2. Root Cause Analysis
*   **Cause:** The `CGEventTap` in `KeyboardInterceptor` explicitly ignores mouse events. To capture `button2` or `button3`, the event needs to come from `MouseInterceptor`. 
*   **Why it wasn't caught:** The system originally only expected users to map keyboard strokes to mouse clicks, not the other way around.

## 3. Resolution
*   **Architecture Update:** `MouseInterceptor` was upgraded to listen to all major mouse events (`leftMouseDown/Up`, `rightMouseDown/Up`, `otherMouseDown/Up`).
*   **Processing Bridge:** `MouseInterceptor` now translates these raw mouse events into virtual `CGEventType.keyDown` and `.keyUp` events (using internal virtual keycodes 2001, 2002, 2003) and feeds them directly into `PCModeProcessor.shared.process`.
*   **Macro Fix:** `PCModeProcessor` was also updated to support mouse events *inside* macros, ensuring sequences like `ctrl + c, button3` execute safely.