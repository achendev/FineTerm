import Cocoa
import SwiftUI

// Keyboard Handling Extension
extension ConnectionListView {
    
    func setupOnAppear() {
        highlightedConnectionID = nil
        
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isSearchFocused = true
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 1. GLOBAL SHORTCUT HANDLING WITHIN APP (Priority High)
            let defaults = UserDefaults.standard
            let targetKeyChar = defaults.string(forKey: "globalShortcutKey") ?? "n"
            let targetModifierStr = defaults.string(forKey: "globalShortcutModifier") ?? "command"
            
            if let targetCode = KeyboardInterceptor.getKeyCode(for: targetKeyChar),
               event.keyCode == targetCode {
                
                let flags = event.modifierFlags
                var modifierMatch = false
                
                switch targetModifierStr {
                    case "command": 
                        modifierMatch = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
                    case "control": 
                        modifierMatch = flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option)
                    case "option":  
                        modifierMatch = flags.contains(.option) && !flags.contains(.command) && !flags.contains(.control)
                    default: 
                        modifierMatch = false
                }
                
                if modifierMatch {
                    // Check if second activation should switch to Terminal
                    let secondActivationToTerminal = UserDefaults.standard.bool(forKey: "secondActivationToTerminal")
                    
                    if secondActivationToTerminal && self.isSearchFocused && !self.showSettings && self.selectedConnectionID == nil {
                        DispatchQueue.main.async {
                            if let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) {
                                terminalApp.activate(options: [.activateIgnoringOtherApps])
                            } else {
                                if let terminalURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                                    NSWorkspace.shared.openApplication(at: terminalURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
                                }
                            }
                        }
                        return nil
                    }
                    
                    // Reset and focus search
                    NSApp.keyWindow?.makeFirstResponder(nil)
                    
                    DispatchQueue.main.async {
                        self.showSettings = false
                        self.selectedConnectionID = nil
                        self.resetForm()
                        
                        self.isSearchFocused = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            self.isSearchFocused = true
                        }
                    }
                    return nil
                }
            }
            
            // 2. Navigation Handling (Only if not in Settings)
            guard !showSettings else { return event }

            let currentList = visibleConnectionsForNav
            
            switch event.keyCode {
            case 125: // Arrow Down
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let nextIdx = min(idx + 1, currentList.count - 1)
                    highlightedConnectionID = currentList[nextIdx].id
                    return nil
                } else if !currentList.isEmpty {
                    highlightedConnectionID = currentList[0].id
                    return nil
                }
            case 126: // Arrow Up
                if let current = highlightedConnectionID,
                   let idx = currentList.firstIndex(where: { $0.id == current }) {
                    let prevIdx = max(idx - 1, 0)
                    highlightedConnectionID = currentList[prevIdx].id
                    return nil
                } else if !currentList.isEmpty {
                    highlightedConnectionID = currentList[0].id
                    return nil
                }
            case 36: // Enter
                if let current = highlightedConnectionID,
                   let conn = currentList.first(where: { $0.id == current }) {
                    
                    if self.selectedConnectionID != nil {
                        self.saveSelected()
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.launchConnection(conn)
                    }
                    return nil
                }
            default: break
            }
            return event
        }
    }
}
