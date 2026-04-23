# [002] Clipboard Async Architecture & Snapshotting

**Status:** Implemented
**Last Updated:** 2026-04-24

## 1. Problem & Context
The Clipboard Manager was originally designed with a synchronous flow: `Detect Change -> Process Data -> Update UI -> Save to Disk`.
As the history grew (especially with images and large text blobs), the `Save to Disk` step—which involves JSON encoding and AES-GCM encryption—began blocking the Main Thread.
Furthermore, all heavy "Blobs" (full-resolution images and large text) were originally kept permanently in memory within a `[UUID: String]` dictionary, ballooning the app footprint to ~500MB on startup for active users.

## 2. The Solution
We moved to a **Dual-Queue Async Architecture**, **State Snapshotting**, and **On-Demand Disk Loading**.

### A. Threading Model
1.  **Main Thread:** Handles lightweight polling (`NSPasteboard.changeCount`) and UI updates.
2.  **Processing Queue (`userInitiated`):** Handles heavy input processing (Image resizing/compression, Text truncation) *before* the item enters the history.
3.  **Save Queue (`utility`):** Handles serialization, encryption, and file I/O *after* the item is added.

### B. State Snapshotting & Memory Optimization
*   `ClipboardStore` only keeps `history` (metadata, thumbnails, and truncated text) in RAM.
*   The full `blobs` dictionary is **completely removed from memory**.
*   When adding an item, we snapshot `history` on the main thread and pass it to the background queue.
*   The background queue exclusively loads `clipboard_blobs.enc` from disk, appends the new item, and encrypts/saves both files.
*   **Result:** The UI remains immediately responsive, and the steady-state memory footprint drops from ~500MB to ~15MB. Full blobs are only loaded temporarily during deep search, deduplication, or paste operations.

## 3. Data Integrity: UTF-8 Truncation
We implemented a strict "Backtracking" logic for text truncation.
*   **Naive Approach:** `string.prefix(1000)` counts characters, not bytes. This allows 1000 emojis (4KB) to pass a 1KB limit.
*   **Byte Approach:** Cutting `data.prefix(1000)` might slice a multi-byte character in half, resulting in invalid UTF-8.
*   **Our Logic:** We cut at the byte limit, then backtrack up to 3 bytes to find a valid character boundary. This ensures the stored data is *always* valid UTF-8 and strictly adheres to the storage quota.

## 4. Why this approach?
*   **Pros:** Zero UI blocking, incredibly low baseline memory footprint, safe data integrity.
*   **Cons:** Deep search and deduplication are slightly slower because they must decrypt the blob file on-demand, but this is an acceptable tradeoff since they run asynchronously.