import Cocoa
import SwiftUI

// Keyboard Handling Extension
extension ConnectionListView {
    
    func setupOnAppear() {
        highlightedConnectionID = nil
        
        // Ensure Focus is in Search Input immediately on open (Only if main window is relevant)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if self.shouldGrabFocus() {
                self.isSearchFocused = true
            }
        }
        
        // Handle App Activation (CMD+Tab or Dock Click)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.shouldGrabFocus() {
                    self.isSearchFocused = true
                }
            }
        }
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // REQ: Ensure we only process these shortcuts if the MAIN window is the target.
            guard let eventWindow = event.window, 
                  let appDelegate = NSApp.delegate as? AppDelegate,
                  eventWindow === appDelegate.window else {
                return event
            }
            
            // 1. GLOBAL SHORTCUT HANDLING WITHIN APP
            let defaults = UserDefaults.standard
            let targetKeyChar = defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n"
            let targetModifierStr = defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"
            
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
                    let secondActivationToTerminal = defaults.bool(forKey: AppConfig.Keys.secondActivationToTerminal)
                    
                    if secondActivationToTerminal && self.isSearchFocused && self.selectedConnectionID == nil {
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
            
            // 2. Navigation Handling
            // Esc Handler
            if event.keyCode == 53 {
                if UserDefaults.standard.bool(forKey: AppConfig.Keys.escToTerminal) {
                    DispatchQueue.main.async {
                        if let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) {
                            terminalApp.activate(options: [.activateIgnoringOtherApps])
                        }
                    }
                } else {
                    self.resetForm()
                    self.isCreatingGroup = false
                    self.newGroupName = ""
                    self.searchText = ""
                    self.isSearchFocused = true
                }
                return nil
            }

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
                    if self.selectedConnectionID != nil { self.saveSelected() }
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
    
    // Helper: Determine if we should grab focus
    private func shouldGrabFocus() -> Bool {
        // 1. If Clipboard Window is visible, DO NOT grab focus.
        // We check if any visible window is of type ClipboardWindow
        let clipboardWindowVisible = NSApp.windows.contains { $0 is ClipboardWindow && $0.isVisible }
        if clipboardWindowVisible { return false }
        
        // 2. If Settings Window is key, DO NOT grab focus.
        if let keyWin = NSApp.keyWindow, keyWin is SettingsWindow { return false }
        
        // 3. Only grab if the Main Window (where this view lives) is supposed to be active
        // Simplest proxy: if we are here, we probably want focus UNLESS intercepted above.
        return true
    }
}

