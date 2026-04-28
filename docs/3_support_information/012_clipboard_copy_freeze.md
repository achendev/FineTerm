# Support: App freezes when clicking item in Clipboard History

## 1. Symptom Description
*   **User Report:** "When I click on an item in the clipboard history list, the app freezes/stucks for a second or two before the window closes and copies to the clipboard."
*   **Context:** Occurred after the initial async storage optimization. While saving was made async, loading blobs from disk for copying remained synchronous.

## 2. Root Cause Analysis
*   **Cause:** In `copyToClipboard()`, the app was calling `ClipboardCrypto.loadBlobs(blobsURL:)` synchronously on the Main Thread. This involves reading a large encrypted file, performing AES-GCM decryption, and JSON decoding. For users with large blobs files (> 10-50MB), this blocked the main thread for 100ms - 2 seconds.
*   **Secondary Issue:** Because it blocked the Main Thread, the `onClose()` event that hides the window was also blocked, causing the UI to visibly freeze.

## 3. Resolution
*   **Async Overwrite (The Fix):** `copyToClipboard()` was refactored to populate the clipboard *instantly* with the fast `item.content` (which contains the full string for 99% of regular text). The heavy blob loading is pushed to `processingQueue`. If the text was truncated, or if it's an image, the background queue silently overwrites the pasteboard with the full data a few milliseconds later.
*   **Pasteboard Loop Prevention:** Implemented `lastWrittenChangeCount`. Since `copyToClipboard` now directly writes to the pasteboard asynchronously, it increments `NSPasteboard.changeCount`. Without a check, `ClipboardStore.checkClipboard()` would re-ingest the same image or text and bloat the history file. Setting and checking `lastWrittenChangeCount` explicitly ignores self-induced pasteboard writes.
*   **Move to Top:** Clicking an item now manually moves it to the top of `history` array to simulate natural clipboard progression, bypassing the `checkClipboard` loop without rewriting blob records.