# [002] Clipboard Manager Subsystem

## 1. Summary
The Clipboard Manager monitors the system pasteboard, maintains a history of items (text and images), handles persistence (encrypted), and provides a UI for retrieval. It is designed to handle large datasets without affecting the app's responsiveness or memory footprint.

## 2. Logic Flow

### A. Ingestion Loop (The "Tick")
1.  **Timer (Main Thread):** Checks `NSPasteboard.changeCount` every 0.5s.
2.  **Detection:** If changed, it reads the raw object.
3.  **Offload:** The raw object is sent to `processingQueue`.
    *   **Images:** Resized to 300x300 thumbnails (JPEG) and full blobs (PNG Base64).
    *   **Text:** Checked against size limits. If > Limit, it is truncated safely.
4.  **Re-Integration:** The processed `ClipboardItem` is sent back to **Main Thread**.
5.  **UI Update:** Item is inserted into `history` array.
6.  **Persistence:** A snapshot of `history` is sent to `saveQueue`. The queue securely loads the separate `blobs` file from disk, appends the new blob, and encrypts/saves both files without blocking the main thread.

### B. Storage Strategy (Split Model)
To keep the list UI fast and the app memory footprint minimal (< 15MB), we split data into two layers:
1.  **History (Fast/Memory):** Contains metadata, thumbnails, and truncated text. This is loaded into memory on launch.
2.  **Blobs (Slow/Disk):** Contains full-resolution images and full-text content. Stored in a separate file `clipboard_blobs.enc` and loaded strictly **on-demand** (e.g., when pasting, deduplicating, or deep searching).

## 3. Key Classes & Responsibilities

| Class | Role |
| :--- | :--- |
| `ClipboardStore.swift` | The "Brain". Handles logic, storage, async queues, and memory offloading. |
| `ClipboardWindowManager` | Manages the floating window lifecycle (show/hide/focus). |
| `ClipboardHistoryView` | SwiftUI view. Handles search, filtering, and rendering. |
| `ClipboardCrypto.swift` | Securely manages independent loading/saving of History and Blobs. |

## 4. Gotchas & Edge Cases
*   **UTF-8 Slicing:** Never simply cut a string by bytes. Always check for validity.
*   **Image Bloat:** Storing raw `NSImage` TIFF data is huge. We convert thumbnails to JPEG and blobs to PNG Base64 to save space.
*   **Space Switching:** `ClipboardWindowManager` must handle `canJoinAllSpaces` correctly, or the window will force the user back to the Desktop where the app was launched.