# [004] System Keyboard Modifier Swap (hidutil)

## 1. Summary
FineTerm allows users to remap hardware modifier keys globally (e.g., swapping Command and Option for PC keyboards). This is handled via the `SystemModifierManager`.

## 2. Logic Flow / Mental Model
Unlike macOS System Settings (which permanently writes bindings to a `.plist`), FineTerm uses the macOS `hidutil` command-line utility.

*   `hidutil` applies I/O Kit hardware remaps **in memory**.
*   This means the remapping is instantaneous, but it is invisible to the macOS System Settings UI.
*   **Safety Benefit:** Because it is in memory, if FineTerm crashes or is closed, the system can easily revert back to its normal state by passing an empty JSON array to `hidutil`, ensuring the user isn't permanently stuck with a broken keyboard layout.

## 3. Key Classes & Responsibilities
| Class/File | Role |
| :--- | :--- |
| `SystemModifierManager.swift` | Reads UserDefaults, translates string choices into Left/Right HID Hex codes, and executes the `hidutil` process. |