import Cocoa
import SwiftUI
import Darwin
import CoreGraphics

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
    
    func applicationDidBecomeActive(_ notification: Notification) {
        snapToTerminal()
    }
    
    @objc func snapToTerminal() {
        if !UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal) { return }
        
        // 1. Find the Terminal App Process
        guard let termApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) else { return }
        let pid = termApp.processIdentifier
        
        // 2. Get Window List to find Terminal's window bounds
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        
        // 3. Find the main Terminal window (Frontmost, reasonable size)
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  var width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width > 100, height > 100 else { continue }
            
            var x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            
            let fixedWidth: CGFloat = 250
            
            // --- RESIZE LOGIC START ---
            // Determine which screen the window is on to handle multi-monitor setups correctly
            var targetScreen = NSScreen.screens.first
            for screen in NSScreen.screens {
                // Determine if window's left edge is within this screen's X-range
                if x >= screen.frame.minX && x < screen.frame.maxX {
                    targetScreen = screen
                    break
                }
            }
            
            if let screen = targetScreen {
                let minX = screen.frame.minX
                let screenWidth = screen.frame.width - 3
                
                // If Terminal is too far left to accommodate FineTerm (X < FixedWidth + ScreenMinX)
                if x - minX < fixedWidth {
                    let newTermX = minX + fixedWidth
                    var newTermWidth = width
                    
                    // If moving right pushes it off screen, shrink it
                    if newTermX + newTermWidth > minX + screenWidth {
                        newTermWidth = (minX + screenWidth) - newTermX
                    }
                    
                    // Apply changes via AppleScript if the frame differs significantly
                    if abs(newTermX - x) > 1 || abs(newTermWidth - width) > 1 {
                        let script = """
                        tell application "System Events" to tell process "Terminal"
                            set position of window 1 to {\(Int(newTermX)), \(Int(y))}
                            set size of window 1 to {\(Int(newTermWidth)), \(Int(height))}
                        end tell
                        """
                        var error: NSDictionary?
                        if let nsScript = NSAppleScript(source: script) {
                            nsScript.executeAndReturnError(&error)
                        }
                        
                        // Update local vars for FineTerm calculation
                        x = newTermX
                        width = newTermWidth
                    }
                }
            }
            // --- RESIZE LOGIC END ---
            
            // 4. Calculate new frame for FineTerm
            // Note: Cocoa coords (0,0) is Bottom-Left. CG coords (0,0) is Top-Left.
            guard let primaryScreen = NSScreen.screens.first else { return }
            let screenHeight = primaryScreen.frame.height
            
            // In Cocoa, Y is distance from bottom.
            // cgY + cgHeight is the bottom edge in CG coords.
            // screenHeight - (bottom edge) = Cocoa Y
            let cocoaY = screenHeight - (y + height)
            
            let cocoaX = x - fixedWidth
            
            // Create new rect
            let newFrame = NSRect(x: cocoaX, y: cocoaY, width: fixedWidth, height: height)
            
            // 5. Apply Position
            window.setFrame(newFrame, display: true)
            
            // Debug Log
            if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
                print("DEBUG: Snapped to Terminal at X:\(cocoaX), Y:\(cocoaY), H:\(height), W:\(fixedWidth)")
            }
            return
        }
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
            freopen(path, "a+", stdout)
            freopen(path, "a+", stderr)
            
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
        window.minSize = NSSize(width: 320, height: 200) // Ensure resize limits
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

