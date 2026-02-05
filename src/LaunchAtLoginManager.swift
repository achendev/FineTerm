import Foundation
import ServiceManagement
import Cocoa

struct LaunchAtLoginManager {
    // Path to the legacy LaunchAgent plist (to be removed)
    private static var oldLaunchAgentURL: URL {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return library.appendingPathComponent("LaunchAgents/com.local.FineTerm.plist")
    }

    static func isEnabled() -> Bool {
        // 1. Check legacy method (so the toggle reflects 'On' if the old file exists)
        if FileManager.default.fileExists(atPath: oldLaunchAgentURL.path) {
            return true
        }

        // 2. Check modern SMAppService (macOS 13+)
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }

        // 3. Check legacy AppleScript method (Login Items list)
        // We check if "FineTerm" is in the list of login items
        let script = """
        tell application "System Events"
            set loginItems to name of every login item
            if "FineTerm" is in loginItems then return true
            return false
        end tell
        """
        return runAppleScript(script) == "true"
    }

    static func setEnabled(_ enabled: Bool) {
        // ALWAYS delete the old LaunchAgent plist if it exists.
        // This fixes the "Allow in Background" issue and the Developer Name issue.
        if FileManager.default.fileExists(atPath: oldLaunchAgentURL.path) {
            try? FileManager.default.removeItem(at: oldLaunchAgentURL)
        }

        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    // Register as a persistent Login Item (Open at Login)
                    if service.status != .enabled {
                        try service.register()
                    }
                } else {
                    try service.unregister()
                }
            } catch {
                print("Error updating SMAppService: \(error)")
            }
        } else {
            // Fallback for macOS 12 and older: Use AppleScript to modify Login Items list
            let appPath = Bundle.main.bundlePath
            if enabled {
                let script = """
                tell application "System Events"
                    if not (exists login item "FineTerm") then
                        make new login item at end with properties {path:"\(appPath)", hidden:false}
                    end if
                end tell
                """
                _ = runAppleScript(script)
            } else {
                let script = """
                tell application "System Events"
                    delete (every login item whose name is "FineTerm")
                end tell
                """
                _ = runAppleScript(script)
            }
        }
    }
    
    private static func runAppleScript(_ source: String) -> String? {
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            let output = script.executeAndReturnError(&error)
            if let error = error {
                print("AppleScript Error: \(error)")
                return nil
            }
            if output.descriptorType == typeBoolean {
                return output.booleanValue ? "true" : "false"
            }
            return output.stringValue
        }
        return nil
    }
}
