# [005] Karabiner-Elements Engine Integration

## 1. Summary
FineTerm allows users to offload the execution of "PC Mode" rules from the internal `CGEventTap` engine directly into the popular third-party driver, **Karabiner-Elements**. This is crucial for users who want their PC Mode mappings (like `Ctrl+C` -> `Cmd+C`) to function reliably inside macOS Secure Input fields (e.g., password boxes in Chrome or Proxmox web consoles), where normal user-space event taps are blocked by the OS.

## 2. Logic Flow / Mental Model (Hybrid Engine)
To give users the zero-latency feel of `CGEventTap` with the Secure Input fallback of Karabiner, FineTerm uses a **Hybrid Engine (Mode 2)**.
1.  **Internal Handling:** `PCModeProcessor.swift` natively processes all keys as usual via `CGEventTap` for maximum performance in normal environments.
2.  **Karabiner Fallback:** FineTerm exports the rules to `karabiner.json`, but prepends a specific condition: `"variable_if": "fineterm_secure_input", "value": 1`. This puts Karabiner's rules to sleep, completely bypassing its latency.
3.  **Active Monitoring:** `SecureInputMonitor.swift` runs a lightweight 100ms background loop polling the Carbon function `IsSecureEventInputEnabled()`.
4.  **The Hand-off:** When you click into a password field, the monitor detects the change and fires a CLI command: `karabiner_cli --set-variables '{"fineterm_secure_input": 1}'`. 
5.  **The Result:** `CGEventTap` naturally goes deaf, and Karabiner instantly activates to handle your macros safely. When you click away, the variable goes back to 0, handing control back to FineTerm seamlessly.

## 3. Key Classes & Responsibilities
| Class/File | Role |
| :--- | :--- |
| `SettingsTabPCMode.swift` | Provides the Engine toggle UI and triggers `syncEngine()` during throttling saves. |
| `PCModeProcessor.swift` | Bypasses its own logic if the Karabiner (Full) engine is preferred, or operates normally in Hybrid mode. |
| `KarabinerExporter.swift` | Safely handles the JSON parsing, injection, modifier mapping, global URL schemes, and file I/O for `~/.config/karabiner/karabiner.json`. Applies `isHybrid` condition tracking. |
| `SecureInputMonitor.swift` | Constantly monitors `IsSecureEventInputEnabled()` and dynamically manages the `fineterm_secure_input` variable in Karabiner via CLI. |
| `WindowCycleService.swift` | Holds application focus cycle logic that can be invoked internally or via URL schemes triggered by Karabiner in Secure Fields. |

## 4. Gotchas & Edge Cases
*   **Modifiers Mapping:** By default, FineTerm is forgiving with extra modifiers. To mimic this behavior, `KarabinerExporter` injects `"optional": ["any"]` into the `from` block of all generated manipulators. Furthermore, all modifiers in the `to` field are explicitly mapped to `left_` variants (e.g., `left_option`) to ensure correct inheritance properties inside Karabiner.
*   **Secure Input Coverage:** Because Karabiner translates global shortcuts into shell commands that trigger URL schemes, ALL FineTerm global functionality (App swapping, Clipboard Manager, Library) works flawlessly even when typing a password.
*   **System Modifiers:** Karabiner operates at the raw HID level, which means it completely ignores standard `hidutil` swaps. To compensate, `KarabinerExporter` reads the `systemModifierSwapEnabled` settings and injects them directly into Karabiner as `complex_modifications`, overriding `hidutil` without conditions (even in Hybrid Mode).