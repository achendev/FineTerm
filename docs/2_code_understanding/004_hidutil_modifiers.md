# [004] System Keyboard Modifier Swap (hidutil)

## 1. Summary
FineTerm allows users to remap hardware modifier keys globally (e.g., swapping Command and Option, mapping Caps Lock to Mouse Clicks). This is handled via the `SystemModifierManager`.

## 2. Logic Flow / Mental Model
Unlike macOS System Settings (which permanently writes bindings to a `.plist`), FineTerm uses the macOS `hidutil` command-line utility.

*   `hidutil` applies I/O Kit hardware remaps **in memory**.
*   This means the remapping is instantaneous, but it is invisible to the macOS System Settings UI.
*   **Safety Benefit:** Because it is in memory, if FineTerm crashes or is closed, the system can easily revert back to its normal state by passing an empty JSON array to `hidutil`, ensuring the user isn't permanently stuck with a broken keyboard layout.

## 3. Caps Lock -> Mouse Clicks (Hybrid Routing)
`hidutil` strictly enforces mapping Keyboard HID Pages to Keyboard HID Pages. It cannot natively map a key to a mouse button.
To solve this:
1. When a user maps Caps Lock to `Button 1`, `SystemModifierManager` tells `hidutil` to map the hardware Caps Lock key to a dummy/unused function key (e.g., `F20`).
2. The `KeyboardInterceptor` listens globally for `F20`.
3. When `F20` is detected, the interceptor swallows it and injects a `CGEvent` for Left Mouse Click. 

## 4. Key Classes & Responsibilities
| Class/File | Role |
| :--- | :--- |
| `SystemModifierManager.swift` | Reads UserDefaults, translates string choices into Left/Right HID Hex codes, and executes the `hidutil` process. |
| `KeyboardInterceptor.swift` | Catches the virtual F20-F22 keys to execute mouse clicks. |