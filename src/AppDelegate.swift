import Cocoa
import SwiftUI
import Darwin

@objc
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: NSWindow!
    var mouseInterceptor: MouseInterceptor?
    var keyboardInterceptor: KeyboardInterceptor?
    
    var clipboardStore: ClipboardStore!
    var clipboardManager: ClipboardWindowManager!
    var settingsManager: SettingsWindowManager!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Setup Logging (First priority to capture initialization)
        setupLogging()
        
        // 2. Setup Configuration
        AppConfig.registerDefaults()
        
        // 3. Setup Menu
        MenuManager.setupMainMenu()
        
        // 4. Setup Window & Policy
        NSApp.setActivationPolicy(.regular)
        setupMainWindow()
        
        // 5. Setup Services
        clipboardStore = ClipboardStore()
        clipboardManager = ClipboardWindowManager(store: clipboardStore)
        settingsManager = SettingsWindowManager() // Init settings manager
        
        // 6. Check Permissions & Launch
        checkPermissionsAndStart()
        
        // 7. Setup Local Shortcut Monitor
        setupLocalShortcutMonitor()
    }
    
    func setupLogging() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let tmpDir = home.appendingPathComponent("tmp")
        
        do {
            // Ensure ~/tmp exists
            try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
            
            let logFile = tmpDir.appendingPathComponent("fineterm_debug.log")
            let path = logFile.path
            
            // Redirect stdout and stderr to the log file
            // "a+" opens for reading and appending (creates if not exists)
            freopen(path, "a+", stdout)
            freopen(path, "a+", stderr)
            
            // Disable buffering so logs appear immediately in the file
            setbuf(stdout, nil)
            setbuf(stderr, nil)
            
            print("\n--------------------------------------------------------------------------------")
            print("FineTerm Log Session Started: \(Date())")
            print("Log File: \(path)")
            print("--------------------------------------------------------------------------------")
            
        } catch {
            NSLog("Error setting up logging: \(error)")
        }
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
        
        // Register delegate to handle closing logic
        window.delegate = self
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
        
        print("FineTerm Started (UI Loaded)")
    }
    
    func startServices() {
        print("Starting Services (Mouse, Keyboard, Clipboard)...")
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
    
    @objc func clearClipboardHistory() {
        clipboardStore.clear()
    }

    // MARK: - NSWindowDelegate
    
    // This logic ensures that when the user closes the main window, 
    // the app relinquishes focus to the previous app (e.g., Terminal).
    // This allows the Global Activation Shortcut to work correctly immediately after.
    func windowWillClose(_ notification: Notification) {
        if let closedWindow = notification.object as? NSWindow, closedWindow === window {
            NSApp.hide(nil)
        }
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
