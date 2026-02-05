import Cocoa
import SwiftUI

@objc
class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var mouseInterceptor: MouseInterceptor?
    var keyboardInterceptor: KeyboardInterceptor?
    
    var clipboardStore: ClipboardStore!
    var clipboardManager: ClipboardWindowManager!
    var settingsManager: SettingsWindowManager!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Setup Configuration
        AppConfig.registerDefaults()
        
        // 2. Setup Menu
        MenuManager.setupMainMenu()
        
        // 3. Setup Window & Policy
        NSApp.setActivationPolicy(.regular)
        setupMainWindow()
        
        // 4. Setup Services
        clipboardStore = ClipboardStore()
        clipboardManager = ClipboardWindowManager(store: clipboardStore)
        settingsManager = SettingsWindowManager() // Init settings manager
        
        // 5. Check Permissions & Launch
        checkPermissionsAndStart()
        
        // 6. Setup Local Shortcut Monitor
        setupLocalShortcutMonitor()
    }
    
    func setupMainWindow() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "FineTerm"
    }

    func checkPermissionsAndStart() {
        if PermissionManager.checkAccessibility() {
            startMainApp()
        } else {
            showPermissionOverlay()
        }
    }

    func showPermissionOverlay() {
        let permissionView = PermissionView { [weak self] in
            self?.startMainApp()
        }
        window.contentView = NSHostingView(rootView: permissionView)
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 380, height: 320))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func startMainApp() {
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 320, height: 500))
        window.center()
        
        let contentView = ConnectionListView()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        startServices()
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        print("FineTerm Started")
    }
    
    func startServices() {
        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.start()
        
        keyboardInterceptor = KeyboardInterceptor()
        keyboardInterceptor?.start()
        
        clipboardStore.startMonitoring()
    }
    
    func setupLocalShortcutMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check for Global Shortcut
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
                    // Check if current key window is NOT main window (e.g. Settings or Clipboard)
                    if let mainWin = self.window, 
                       let keyWindow = NSApp.keyWindow, 
                       keyWindow !== mainWin {
                        
                        // Close others
                        self.settingsManager.close()
                        self.clipboardManager.close()
                        
                        // Activate Main
                        if mainWin.isMiniaturized { mainWin.deminiaturize(nil) }
                        mainWin.makeKeyAndOrderFront(nil)
                        return nil // Swallow event
                    }
                }
            }
            return event
        }
    }
    
    func toggleClipboardWindow() {
        clipboardManager.toggle()
    }
    
    // Called via Menu Item selector or UI Button
    @objc func openSettings() {
        settingsManager.open() // Open standalone window
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mouseInterceptor?.stop()
        keyboardInterceptor?.stop()
        clipboardStore.stopMonitoring()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}
