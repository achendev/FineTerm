# [004] Ghostty Specific Tab Naming Logic

**Status:** Implemented
**Last Updated:** 2026-04-18

## 1. Problem & Context
Ghostty terminal requires special logic to set the tab name dynamically. Unlike Apple Terminal and iTerm2, which support changing the title dynamically by injecting shell escape sequences (`printf '\e]1;%s\a'`), Ghostty handles tab title changes most reliably via its native menu UI interactions rather than interpreting shell characters injected by our execution wrapper.

## 2. The Solution (Current Decision)
We moved the Ghostty launch logic into a dedicated component called `GhosttyBridge.swift`. When a connection is launched and `changeTerminalName` is enabled, the AppleScript triggers the `View > Change Tab Title...` menu item, waits 100ms, injects the connection name, and presses Enter. This bypasses the need for shell command overrides and applies the title cleanly directly at the application (Ghostty) level.

## 3. Why this approach? (Pros/Cons)
*   **Pros:** Isolates terminal-specific AppleScript logic keeping `TerminalBridge` clean. Sets the tab name immediately without relying on shell completion or `sleep` background commands inside the target shell.
*   **Cons:** UI Scripting is inherently more fragile and depends on exact OS menu item names (handles both `Change Tab Title…` and `Change Tab Title...`).

## 4. Alternatives Considered
*   Overriding the console buffer entirely: Rejected because terminal sequences didn't reliably reflect visually within the Ghostty tab boundaries without native UI interaction.