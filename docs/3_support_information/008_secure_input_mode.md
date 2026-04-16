# Support: All Binds Stop Working in Password Fields

## 1. Symptom Description
*   **User Report:** "When I'm in Chrome on the some Proxmox panel page and cursor is in the password field, all binds stop working."
*   **Context:** Occurs when focusing any standard `<input type="password">` field in browsers (Chrome/Safari), Terminal `sudo` prompts, or password managers like 1Password.

## 2. Root Cause Analysis
*   **Cause:** macOS has a strict security feature called **Secure Input Mode**. When a password field is focused, the Window Server explicitly bypasses all standard `kCGSessionEventTap` listeners to prevent malicious apps from logging keystrokes. FineTerm relies entirely on an Event Tap for its PC Mode rules and Global Shortcuts, so the app essentially goes deaf while Secure Input is active.

## 3. Resolution
*   **Architecture Update:** We migrated the `CGEventTap` from `kCGSessionEventTap` to `kCGHIDEventTap` (Hardware level).
*   **Why HID Level?** `kCGHIDEventTap` intercepts events *before* they are routed to the user session, meaning it can see keystrokes even when Secure Input is enabled. This is officially permitted by macOS as long as the process has Accessibility Privileges (which FineTerm already requires and verifies on launch).
*   **Result:** All PC Mode bindings, Custom App Shortcuts, and Modifier-Only triggers (like `Right Cmd + Right Opt`) now function flawlessly regardless of the Secure Input state, without needing clunky workarounds like Carbon HotKeys.