import Foundation

struct TerminalBridge {
    static func launch(command: String) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = """
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
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
            }
        }
    }
}