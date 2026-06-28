import Foundation

struct ItermBridge {
    static func launch(command: String, tabName: String?) {
        let escapedCommand = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        
        let scriptSource = """
        tell application id "com.googlecode.iterm2"
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
        
        var error: NSDictionary?
        if let script = NSAppleScript(source: scriptSource) {
            script.executeAndReturnError(&error)
            if let error = error {
                print("iTerm AppleScript Error: \(error)")
            }
        }
    }
}