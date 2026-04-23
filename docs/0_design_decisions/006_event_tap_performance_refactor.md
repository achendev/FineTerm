# [006] Event Tap Performance & Pre-Parsing Architecture

**Status:** Implemented
**Last Updated:** 2026-04-23

## 1. Problem & Context
FineTerm relies heavily on `CGEventTap` (in `KeyboardInterceptor` and `MouseInterceptor`) to monitor the global system input stream. macOS imposes strict real-time constraints on event taps (typically < 14ms execution time). If a tap takes too long, macOS disables it automatically (`.tapDisabledByTimeout`), leading to missed keystrokes and app unresponsiveness.

**The Bottlenecks (Pre-Refactor):**
1.  **String-Based Modifier Matching:** On every keystroke, the app parsed string-based rules (e.g., `"cmd"`, `"left_shift"`) and evaluated them against the current `NSEvent.modifierFlags` or `CGEventFlags`. String allocation and comparison inside a high-frequency loop is exceptionally slow and generates high CPU overhead.
2.  **Synchronous Workspace Queries:** Determining the frontmost app to apply app-specific exclusions (like PC Mode browser rules) used `WindowCycleService.getRealFrontmostApp()`. This method sometimes relies on `CGWindowListCopyWindowInfo`, an expensive IPC call that could block the event tap for 10-50ms.
3.  **UserDefaults I/O:** Checking `UserDefaults.standard.integer(forKey: "pcModeEngine")` on every key press creates unnecessary disk/memory overhead.
4.  **Clipboard Deduplication Spikes:** `ClipboardStore.removeDuplicates()` converted full images into Base64 strings to check for equality, causing massive memory spikes and UI freezes when history contained many images.
5.  **Search Overhead:** `SearchService` used `.localizedCaseInsensitiveContains()` which implicitly creates new, locale-aware string allocations on every comparison.

## 2. The Solutions & "Why"

### A. Pre-Parsed Shortcut Triggers (O(1) Bitmask Matching)
**What:** Created `ParsedShortcutTrigger`, `ParsedCustomAppShortcut`, and `ParsedPCModeRule`. Removed `KeyboardMatcher.swift`.
**Why:** Instead of parsing strings dynamically, `KeyboardCache.refresh()` runs *once* when settings change. It translates strings into raw `CGEventFlags` bitmasks and an array of `strictFlags` (to handle specific left/right modifiers). 
When a key is pressed, `ParsedShortcutTrigger.matches(...)` simply performs bitwise `&` (intersection) and `==` comparisons. This reduces evaluation from O(N) string operations to O(1) integer arithmetic, processing keystrokes in microseconds.

### B. Lazy Evaluation of Frontmost Application
**What:** Passed a closure `getFrontAppID: () -> String` from `KeyboardInterceptor` into `PCModeProcessor`.
**Why:** We only need to know the frontmost app if the user pressed a shortcut that actually *has* an app inclusion/exclusion filter. By using a closure backed by a local `lazyFrontAppID` variable, we completely bypass the expensive `CGWindowList` IPC call for 99% of regular typing, only paying the 10ms penalty when absolutely required by a specific shortcut.

### C. Engine Caching & The "Hybrid Mode" Bug Fix
**What:** Cached `pcModeEngine` directly inside `KeyboardCache`. Removed the `if engine == 0` wrapper from `KeyboardInterceptor`.
**Why:** Hitting `UserDefaults` inside the event tap was wasteful. 
*The Bug:* During initial refactoring, an `if engine == 0` wrapper was placed around `PCModeProcessor.shared.process`. This accidentally broke "Hybrid Auto" (`engine == 2`), because Hybrid mode requires the event tap to evaluate rules natively when Secure Input is inactive. The engine check was pushed *inside* `PCModeProcessor` to restore correct fallback behavior while maintaining performance.

### D. Zero-Copy Clipboard Deduplication (Hashing)
**What:** Replaced Base64 equality checks in `ClipboardStore.removeDuplicates` with a `HashKey` struct containing `hashValue` and `length`.
**Why:** Converting a 5MB image to a Base64 string just to check if it's a duplicate blocks the CPU and spikes RAM. Using Swift's native `.hashValue` combined with the data's byte `.count` creates an effectively collision-proof signature that computes in milliseconds with near-zero memory footprint.

### E. Search Service Optimization
**What:** Replaced `.localizedCaseInsensitiveContains` with `.lowercased()` and `.contains()` in `SearchService`.
**Why:** When typing fast in the search bar across hundreds of connections or library items, the search was lagging. `.lowercased()` is called *once* per item, and `.contains()` does a much faster underlying byte-sequence check, drastically reducing memory thrashing during real-time UI filtering.

## 3. Summary
These architectural shifts move the computational burden from the "Hot Path" (the event loop) to the "Cold Path" (settings changes and UI updates), guaranteeing that FineTerm operates completely invisibly to the user without degrading native system typing latency.