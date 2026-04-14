# Support: PC Mode "Shift+M" overriding issues

## 1. Symptom Description
*   **User Report:** "When I try to type a capital M (Shift+M) and I have a shortcut mapping `ctrl + shift + m` to `cmd + shift + m` enabled, it triggers `cmd + shift + m` on just `Shift+M` (without holding Control)."
*   **Context:** Occurs when using PC Mode Rules with poorly typed modifiers (e.g., typing `crtl + shift + m` instead of `ctrl + shift + m`).

## 2. Root Cause Analysis
*   **Cause 1 (Parser Forgiveness):** The user accidentally made a typo in the UI (e.g., `crtl`). Previously, `KeyboardParser` silently ignored unrecognized modifiers. This stripped the intended 3-key rule down to simply `shift + m` instead of invalidating it.
*   **Cause 2 (Modifier Inheritance):** PC Mode deliberately uses `.isSuperset()` matching logic to support implicit modifier inheritance.
*   **The Clash:** Because the rule was corrupted into `shift + m` by the parser, typing a basic `Shift+M` evaluated as a perfect match for the corrupted rule, unintentionally hijacking the normal keypress and injecting the `cmd + shift + m` action.

## 3. Resolution
*   **Parser Strictness:** `KeyboardParser` was updated to fail immediately and return an empty key tuple if an invalid modifier is parsed. If a user makes a typo, the entire rule is safely ignored (disabled) instead of resolving to a dangerous, lower-specificity fallback.
*   **Engine Integrity:** The `.isSuperset()` matching engine in `PCModeProcessor` was retained. This guarantees intended modifier inheritance continues working dynamically (e.g., dragging Shift over a Ctrl shortcut), whilst resolving the Capital Letter override issue safely at the parser level.