# Support: Memory Footprint Balloons to 150MB+

## 1. Symptom Description
*   **User Report:** "FineTerm uses 150MB of RAM even after the recent async storage updates. It starts small but slowly grows the more I use the mouse or keyboard."
*   **Context:** Occurred dynamically over time, unlike the massive 500MB static load from history blobs.

## 2. Root Cause Analysis
This was caused by two massive hidden "leaks" (one structural, one lifecycle):

*   **Cause 1 (The Autorelease High Water Mark):** `KeyboardInterceptor` intercepts every single keypress via `CGEventTap`. To process PC Mode rules, it frequently queries macOS via `CGWindowListCopyWindowInfo` to determine the active app. This returns large `CFArray` and `CFDictionary` objects. Because these are generated inside a fast C-callback, Swift waits for the main UI Runloop to go "idle" before destroying them. If a user types at 100WPM, the runloop never idles, causing a huge backup of undeallocated dictionaries.
*   **Cause 2 (Settings View NSImage Multi-Rep Leak):** When a user opens Settings -> PC Mode, the app populates dropdowns with available apps. Previously, it loaded raw icons via `NSWorkspace.shared.icon(forFile:)`. macOS icons contain multiple heavy representations (up to 1024x1024 pixels). Even though SwiftUI scaled them down visually, the memory stayed. To make matters worse, `SettingsWindow` had `isReleasedWhenClosed = false`, meaning those hundreds of raw megabyte-heavy icons stayed in RAM forever once you clicked the gear icon.

## 3. Resolution
*   **Code Fix 1:** Added an explicit `return autoreleasepool { ... }` wrapper around `keyboardEventCallback`, `eventTapCallback`, and `scrollMovementCallback`. This forces Swift to instantly vaporize temporary objects at the end of the keystroke cycle instead of deferring it.
*   **Code Fix 2:** Updated `AppListService` to explicitly rasterize the raw `NSImage` into a flat 16x16 bitmap context, cleanly severing its tie to the original `.icns` payload.
*   **Code Fix 3:** Set `SettingsWindow.isReleasedWhenClosed = true`, and added `AppListService.shared.clearCache()` to `windowWillClose`, completely destroying the heavy data arrays when the settings window is dismissed.