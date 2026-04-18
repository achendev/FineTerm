import Foundation

struct GhosttyBridge {
    static func launch(command: String, tabName: String?) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        var tabNameScript = ""
        if let name = tabName {
            let escapedName = name
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            tabNameScript = """
            try
                set viewMenu to menu 1 of menu bar item "View" of menu bar 1
                try
                    click menu item "Change Tab Title…" of viewMenu
                on error
                    click menu item "Change Tab Title..." of viewMenu
                end try
                delay 0.1
                keystroke "\(escapedName)"
                key code 36
                delay 0.1
            on error
                -- Silently ignore if menu item is not found
            end try
            """
        }
        
        let scriptSource = """
        tell application "Ghostty"
            activate
        end tell
        delay 0.2
        tell application "System Events"
            tell process "Ghostty"
                keystroke "t" using command down
                delay 0.2
                
                \(tabNameScript)
                
                keystroke "\(escapedCommand)"
                key code 36
            end tell
        end tell
        """
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("Ghostty AppleScript Error: \(error)")
            }
        }
    }
}