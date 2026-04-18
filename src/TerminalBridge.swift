import Foundation

struct TerminalBridge {
    static func launch(command: String) {
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        var scriptSource = ""
        
        if target == "com.googlecode.iterm2" {
            scriptSource = """
            tell application "iTerm"
                activate
                if not (exists window 1) then
                    create window with default profile
                else
                    tell current window
                        create tab with default profile
                    end tell
                end if
                tell current session of current window
                    write text "\(escapedCommand)"
                end tell
            end tell
            """
        } else {
            scriptSource = """
            tell application "Terminal"
                activate
                try
                    tell application "System Events" to keystroke "t" using command down
                on error
                    do script "" -- Fallback if keystroke fails (e.g. no window open)
                end try
                delay 0.2
                do script "\(escapedCommand)" in front window
            end tell
            """
        }
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
            }
        }
    }
}