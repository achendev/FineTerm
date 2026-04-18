# [005] Library Feature Implementation & Enter Key Quirks

**Status:** Current
**Last Updated:** 2026-04-18

## 1. Problem & Context
Users needed a way to manually save frequently used snippets or images (a "Library") that wouldn't get auto-rotated out by the `ClipboardStore`. It needed a UI to name the snippet, view it, and quickly save it via a global shortcut. The UI also needed to support standard global hotkeys (`Opt+N` to add, `Opt+M` to browse).

## 2. Architecture & Data Flow
*   **Separation of Concerns:** Instead of polluting `ClipboardStore` with manual items, a completely separate `LibraryStore` was created.
*   **Reusability:** The existing `ClipboardCrypto.swift` was made generic (`<T: Codable>`) so both `ClipboardStore` and `LibraryStore` could share the same AES-GCM encryption logic but save to different files (`library_items.enc`).
*   **Window Management:** The UI leverages the existing `ClipboardWindow` (a custom `NSWindow` subclass) to maintain consistent `Esc` key handling, space-switching behaviors, and floating layer levels.
*   **Global Shortcuts:** Added to `KeyboardInterceptor` alongside the other triggers.

## 3. The "Enter Key" Bug in LibraryAddView
**The Symptom:**
In `LibraryAddView`, the user could not save the snippet by pressing `Enter` while the `title` TextField was focused. Furthermore, mapping `Cmd+Enter` to hidden buttons created weird empty blue squares in the UI. Later, the Enter key simply stopped working occasionally, or pressing `Shift+Enter` would accidentally open the snippet in an external editor.

**The Root Cause (SwiftUI Responder + Observer Leak):**
1. SwiftUI's `TextField` Enter handling (via `.onSubmit` or `.defaultAction`) is notoriously flaky on macOS when combined with floating panels.
2. We used a global `NSEvent.addLocalMonitorForEvents` inside a `ClipboardKeyHandler` object.
3. Because we didn't explicitly tear down the SwiftUI view (`window.contentView = nil`) when closing windows (`orderOut`), the `ClipboardHistoryView` stayed alive in the background with an active global key monitor.
4. Since `LibraryAddWindow`, `LibraryWindow`, and `ClipboardWindow` all use the same custom `ClipboardWindow` class, the background `ClipboardHistoryView` monitor saw `Enter` pressed on `LibraryAddWindow`, matched the class check, and wrongfully swallowed the event (or triggered `Shift+Enter` editor launches).

**The Solution:**
1. Added strict `window.title == "..."` validation inside each view's key handler so they never cross-talk.
2. Modified `ClipboardWindowManager`, `LibraryWindowManager`, and `LibraryAddWindowManager` to set `window.contentView = nil` inside their `close()` methods. This completely destroys the SwiftUI view when the window is hidden, guaranteeing `onDisappear` fires and the event monitor is deallocated, reclaiming memory and preventing hidden observers.

## 4. Revision History
*   **2026-04-18:** Initial implementation of Library feature. Fixed macOS Field Editor `.disabled` bug that swallowed Enter keys.
*   **2026-04-18 (Later):** Replaced hidden `EmptyView` and `.onSubmit` with explicit `NSEvent` local monitoring via `ClipboardKeyHandler` to guarantee 100% Enter/Cmd+Enter reliability. Fixed background view observer leaks.