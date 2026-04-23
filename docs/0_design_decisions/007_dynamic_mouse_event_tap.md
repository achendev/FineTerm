#[007] Dynamic Mouse Event Tap (CPU Optimization)

**Status:** Implemented
**Last Updated:** 2026-04-24

## 1. Problem & Context
FineTerm relies on `CGEventTap` to intercept system-wide input events. Previously, `MouseInterceptor` monitored `[.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]` constantly to power the "Scroll Mode" feature. 
However, macOS triggers `.mouseMoved` hundreds of times per second. Routing these events through a Swift closure, even if immediately returning `.passUnretained`, caused FineTerm to consume ~2% CPU continuously while the user simply moved the cursor across their desktop.

## 2. The Solution
We split the event taps into two isolated streams:
1.  **Button Tap (`MouseInterceptor.swift`):** Runs permanently but only listens for clicks (`.leftMouseDown`, etc.). Clicks are extremely low-frequency, meaning the ambient CPU usage sits at exactly 0.0%.
2.  **Movement Tap (`ScrollModeManager.swift`):** A dedicated `CGEventTap` created exclusively for `.mouseMoved` and drag events. 
    *   It is instantiated on launch but explicitly **disabled** via `CGEvent.tapEnable(..., enable: false)`.
    *   When `ScrollModeManager.isActive` is toggled ON (e.g. when you physically hold down `F20`), the tap is instantly enabled.
    *   When the modifier is released, it is instantly disabled again.

## 3. Why this approach?
*   **Pros:** CPU usage during normal mouse movement drops to absolutely zero. Enabling/disabling an existing event tap is an instant `O(1)` C-level call that drops no frames and introduces zero latency when triggering the scroll modifier.
*   **Cons:** Slightly splits mouse logic across two files, but semantically makes perfect sense since `ScrollModeManager` is the sole consumer of continuous cursor movement data.