# FineTerm

<p align="center">
  <a href="https://github.com/achendev/FineTerm/releases">
    <img src="https://img.shields.io/github/downloads/achendev/FineTerm/total.svg" alt="Total Downloads">
  </a>
  <a href="https://github.com/achendev/FineTerm">
    <img src="https://img.shields.io/github/stars/achendev/FineTerm?style=social" alt="Star on GitHub">
  </a>
</p>

**The missing Connection Manager and Input Enhancer for macOS Terminal.**

FineTerm is a lightweight, native Swift application designed to supercharge the stock macOS Terminal.app. It bridges the gap between the native terminal experience and the advanced session management features found in heavy third-party emulators like iTerm2 or SecureCRT.

It does not replace Terminal.app—it **wraps** it with a powerful session manager and injects nostalgic PuTTY-style "Pro" input behaviors that Unix and Windows admins have missed for years.

<p align="center">
<img width="700" alt="FineTerm" src="https://github.com/user-attachments/assets/5aa439ff-e1d0-40d3-a25c-f6bb0ba5b68a" />
</p>

## Why FineTerm?

Most terminal replacements (Hyper, Alacritty, iTerm, Tabby) require you to abandon the highly optimized, battery-friendly native macOS Terminal. 

**FineTerm is different:**
1.  **Native Performance:** You still use the actual Terminal.app. Now it's just automated.
2.  **Unix/Windows Mouse Behavior:** Finally brings **"Copy on Select"** (PuTTY/Linux style) and **"Paste on Right Click"** to the native Mac Terminal.
3.  **Focus Flow:** A seamless Global Hotkey system allows you to toggle between your connection list and your active terminal instantly.
4.  **Zero Bloat:** Written in pure Swift. No Electron, no Python, no heavy dependencies. 5MB memory footprint.

---

## Key Features

### 1. Connection Manager
*   **Organized:** Group your SSH, Telnet, or local script commands into foldable folders.
*   **Smart Search:** Instant "Spotlight-style" search with multi-word matching (e.g., "db prod" finds "Production DB Server").
*   **Drag & Drop:** Reorder connections and organize groups intuitively.
*   **Import/Export:** Share your server lists via JSON.
*   **Terminal Tab Naming:** Automatically sets the Terminal tab title to your connection name.

### 2. "Pro" Input Interceptors
*   **Copy on Select:** Simply dragging your mouse over text in the Terminal automatically copies it to the clipboard. No more `Cmd+C`.
*   **Paste on Right Click:** Right-clicking anywhere in the Terminal window pastes your clipboard.
*   *Note: These features operate by intercepting mouse events specifically when Terminal is focused and injecting keystrokes.*

### 3. The "Focus Loop"
*   **Configurable Global Hotkey (Default: `Cmd+N`):** 
    *   **From Terminal:** Press the hotkey to instantly bring the Connection List to the front.
    *   **System-wide Mode:** Optionally enable global mode to activate FineTerm from any application.
    *   **Second Activation:** When FineTerm is already focused, pressing the hotkey again instantly switches back to Terminal—perfect for quick glances at your connection list.
*   Select your server, hit Enter, and it launches a new tab in your existing Terminal window.

---

## Installation & Build

This project is a raw Swift codebase. You don't need Xcode to build it, just the command line tools.

1.  **Build the App:**
    ```bash
    chmod +x build.sh
    ./build.sh
    ```
    This creates the app bundle at `./FineTerm.app`.

2.  **Run:**
    Double-click `FineTerm.app` or run from terminal:
    ```bash
    open FineTerm.app
    ```

3.  **⚠️ CRITICAL: Accessibility Permissions**
    Because this app intercepts global keystrokes and mouse events (for Copy/Paste), macOS requires **Accessibility Access**.
    
    1.  On first launch, the app will check for permissions.
    2.  Go to **System Settings -> Privacy & Security -> Accessibility**.
    3.  If `FineTerm` is in the list, enable the toggle.
    4.  If not, drag the `FineTerm.app` file into the list manually.
    5.  **Restart the app.**

---

## Usage Guide

### Managing Connections
*   **Add:** Click the "+" button or fill in the form at the bottom.
*   **Edit:** Click a row to load it into the editor.
*   **Connect:** Click the "Play" icon or press `Enter` on a highlighted row.
*   **Search:** Just start typing. The list filters automatically with smart multi-word matching. Use `Up`/`Down` arrows to navigate and `Enter` to connect.

<p align="center">
<img height="500" alt="FineTerm Search" src="https://github.com/user-attachments/assets/b76a072d-3aad-4341-adfe-568a48442f57" />
</p>

### Keyboard Shortcuts
| Context | Shortcut | Action |
| :--- | :--- | :--- |
| **Terminal** | `Cmd + N` | Switch focus to FineTerm (Configurable) |
| **FineTerm (search focused)** | `Cmd + N` | Switch back to Terminal (if enabled) |
| **FineTerm** | `Up / Down` | Navigate connection list |
| **FineTerm** | `Enter` | Connect to selected server |

### Settings
Click the ⚙️ icon to configure:

<p align="center">
<img width="360" alt="NatievTab Settings" src="https://github.com/user-attachments/assets/28ca2698-4116-4405-93a7-7c08412ee8cb" />
</p>

**Global Activation Shortcut:**
*   **Modifier + Key:** Choose Command, Control, or Option plus any key.
*   **System-wide (Global):** Enable to activate FineTerm from any application, not just Terminal.
*   **Second Activation to Terminal:** When enabled, pressing the shortcut again while FineTerm is focused switches back to Terminal.

**Command Execution Wrappers:**
*   **Prefix:** Commands prepended before your connection (e.g., `unset HISTFILE ; clear ;`).
*   **Suffix:** Commands appended after (e.g., `&& exit`).
*   **Set Terminal Tab Name:** Automatically names the Terminal tab after your connection.
*   **Template Variables:** Use these in prefix/suffix for dynamic values:
    *   `$PROFILE_NAME` – Replaced with the connection name (e.g., "Production Server")
    *   `$PROFILE_COMMAND` – Replaced with the connection command (e.g., "ssh user@example.com")

**UI Preferences:**
*   **Hide Command in List:** Show only connection names, hiding the command details.
*   **Smart Search (Multi-word):** Enables AND-logic search where "db prod" matches "prod db".

**Mouse Behavior:**
*   **Copy on Select:** Toggle Linux/PuTTY-style copy behavior.
*   **Paste on Right Click:** Toggle right-click paste behavior.

---

## How It Works (Architecture)

1.  **SwiftUI Interface:** Renders the lightweight list and settings.
2.  **AppleScript Bridge:** When you click "Connect", the app talks to Terminal.app via AppleScript to spawn tabs and type commands.
3.  **CGEventTap (Interceptors):** Low-level CoreGraphics APIs hook into the system event stream.
    *   The app filters for events only when `com.apple.Terminal` is the frontmost application (unless global mode is enabled).
    *   It swallows specific events (like Right Click) and injects simulated keystrokes (`Cmd+V`) in their place.

## License
MIT License.
