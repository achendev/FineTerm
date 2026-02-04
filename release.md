# Release Notes

## 🚀 New Features

### 🔍 Smart Search with Exclusion
The search bar has been upgraded with boolean-style logic for faster filtering:
*   **Exclusion Support:** You can now hide specific results by prepending a minus sign (`-`). For example, searching `db -prod` will show all connections matching "db" *except* those containing "prod".
*   **Multi-term Matching:** Search terms are now treated as "AND" queries, allowing you to type `aws database` to find connections containing both words, regardless of order.

### 🗑️ Recursive Group Deletion
Managing large lists is easier:
*   **Standard Delete:** Clicking the trash icon on a group moves its connections to "Ungrouped".
*   **Recursive Delete:** Holding **Shift** while clicking the trash icon will now delete the group **and** all connections inside it permanently.

### 📋 Clipboard Sharing
You can now import and export connections without creating files:
*   **Export:** Use the menu to copy your entire connection list (or just the expanded groups) as JSON text to your clipboard.
*   **Import:** "Import from Clipboard" allows you to paste a JSON configuration directly.

## 🛠 Improvements

*   **Legacy Migration:** Added `migrate_nativetab.sh` to assist users migrating from the NativeTab application.
