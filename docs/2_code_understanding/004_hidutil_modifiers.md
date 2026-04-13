# [004] System Keyboard Modifier Swap (hidutil)

## 1. Summary
FineTerm allows users to remap hardware modifier keys globally (e.g., swapping Command and Option, mapping Caps Lock to F1-F24). This is handled via the `SystemModifierManager`.

## 2. Logic Flow / Mental Model
Unlike macOS System Settings (which permanently writes bindings to a `.plist`), FineTerm uses the macOS `hidutil` command-line utility.

*   `hidutil` applies I/O Kit hardware remaps **in memory**.
*   This means the remapping is instantaneous, but it is invisible to the macOS System Settings UI.
*   **Safety Benefit:** Because it is in memory, if FineTerm crashes or is closed, the system can easily revert back to its normal state by passing an empty JSON array to `hidutil`, ensuring the user isn't permanently stuck with a broken keyboard layout.

## 3. The F21-F24 Kernel Drop Limitation & Aliasing
Apple's native keyboard layout (`Events.h`) only defines virtual keys up to `kVK_F20`. If we instruct `hidutil` to map a key (like Caps Lock) to `0x70000006C` (F21), the macOS WindowServer sees the hardware event but doesn't know how to translate it to a UI Event (`CGEvent`), so it simply **drops it**. The `KeyboardInterceptor` would never receive the keystroke.

**The Hack:**
When a user selects `F21`, `F22`, `F23`, or `F24` as a target, `SystemModifierManager` secretly aliases them to `F17`, `F18`, `F19`, and `F20` at the hardware level. The `KeyboardParser` also aliases `f21-f24` string definitions to the corresponding `F17-F20` virtual key codes. This allows the user to logically use F21-F24 in their rules, while the system passes the events reliably. (Note: This means F20 and F24 are technically the same key to the system).

## 4. Key Classes & Responsibilities
| Class/File | Role |
| :--- | :--- |
| `SystemModifierManager.swift` | Reads UserDefaults, translates string choices into Left/Right HID Hex codes, handles F21-F24 aliasing, and executes the `hidutil` process. |
| `KeyboardInterceptor.swift` | Catches the virtual keys to execute remapped shortcuts or mouse clicks. |