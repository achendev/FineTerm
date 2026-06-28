# [004] Terminal Specific Tab Naming Logic (Ghostty & iTerm2)

**Status:** Implemented
**Last Updated:** 2026-06-03

## 1. Problem & Context
Ghostty and iTerm2 terminals require special logic to set the tab name dynamically. Unlike Apple Terminal, which supports changing the title dynamically by injecting shell escape sequences (`printf '\e]1;%s\a'`), Ghostty and iTerm2 handle tab title changes most reliably via specialized interactions rather than interpreting shell characters injected by our execution wrapper.

## 2. The Solution (Current Decision)
We separated the terminal-specific launch logic into dedicated components: `GhosttyBridge.swift` and `ItermBridge.swift`.
* **Ghostty:** Handled via programmatic System Events GUI menu scripting because it doesn't support the same escape sequence mechanisms natively.
* **iTerm2:** Handled via standard ANSI escape sequences. By allowing iTerm2 to receive the `terminalNamePrefix` containing standard escape sequences, the tab name is updated instantly and silently on all iTerm2 versions, bypassing AppleScript-specific failures.

## 3. Why this approach? (Pros/Cons)
*   **Pros:** Native terminal escape sequences are robust, completely instant, and do not block the UI or trigger popups.
*   **Cons:** Requires shell integration to be enabled in iTerm2 settings (which is the default).

## 4. Revision History
*   **2026-04-18:** Initial implementation of Ghostty tab naming.
*   **2026-06-03:** Switched iTerm2 to use high-performance, silent ANSI escape sequences, ensuring compatibility across all app versions.