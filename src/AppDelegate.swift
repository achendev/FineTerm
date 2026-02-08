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
    
    // Live Snapping Observer
    var terminalObserver: TerminalWindowObserver?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Setup Logging
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
        settingsManager = SettingsWindowManager()
        
        // 6. Check Permissions & Launch
        checkPermissionsAndStart()
        
        // 7. Setup Local Shortcut Monitor
        setupLocalShortcutMonitor()

        // 8. Warmup Text Editor Detector
        TextEditorBridge.shared.warmUp()
        
        // 9. Setup Live Snapping Observer
        setupTerminalObserver()
    }
    
    func setupTerminalObserver() {
        terminalObserver = TerminalWindowObserver { [weak self] in
            self?.snapToTerminal()
        }
        
        // Monitor Space Changes to trigger snap/hide logic
        NSWorkspace.shared.notificationCenter.addObserver(
            self, 
            selector: #selector(snapToTerminal), 
            name: NSWorkspace.activeSpaceDidChangeNotification, 
            object: nil
        )
        
        // Update state initially
        refreshTerminalObserverState()
        
        // Monitor Application Lifecycle to enable/disable snapping based on Terminal's presence
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Terminal" else { return }
            self?.refreshTerminalObserverState()
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] notif in
            guard let app = notif.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.Terminal" else { return }
            
            // CRITICAL FIX: Revert window behavior immediately when Terminal quits
            self?.refreshTerminalObserverState()
        }
    }
    
    @objc func refreshTerminalObserverState() {
        let shouldSnap = UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal)
        
        // Check if Terminal is actually running
        let terminalApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.Terminal" }
        let isTerminalRunning = terminalApp != nil && !terminalApp!.isTerminated
        
        if shouldSnap && isTerminalRunning {
            terminalObserver?.start()
            snapToTerminal()
        } else {
            terminalObserver?.stop()
        }
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        snapToTerminal()
    }
    
    @objc func snapToTerminal() {
        if !UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal) { return }
        
        // 1. Find the Terminal App Process
        guard let termApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.Terminal" }) else { return }
        let pid = termApp.processIdentifier
        
        // 2. Get Window List to find Terminal's window bounds ON CURRENT SCREEN
        // .optionOnScreenOnly filters out windows on other Spaces
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        
        // 3. Find the main Terminal window
        var foundTerminal = false
        var termRect: CGRect = .zero
        
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = boundsDict["Width"],
                  let height = boundsDict["Height"],
                  width > 100, height > 100 else { continue }
            
            // Only consider the first valid terminal window found
            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            termRect = CGRect(x: x, y: y, width: width, height: height)
            foundTerminal = true
            break
        }
        
        // 4. Handle Visibility & Snapping
        if foundTerminal {
            // Terminal IS on this space -> Show and Snap
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            
            var x = termRect.origin.x
            let y = termRect.origin.y
            var width = termRect.width
            let height = termRect.height
            
            let fixedWidth: CGFloat = 250
            let gap: CGFloat = 1
            
            // --- RESIZE LOGIC ---
            // Determine screen of Terminal window
            var targetScreen = NSScreen.screens.first
            for screen in NSScreen.screens {
                if x >= screen.frame.minX && x < screen.frame.maxX {
                    targetScreen = screen
                    break
                }
            }
            
            if let screen = targetScreen {
                let minX = screen.frame.minX
                let screenWidth = screen.frame.width - 3
                
                // If Terminal is too far left
                if x - minX < fixedWidth + gap {
                    let newTermX = minX + fixedWidth + gap
                    var newTermWidth = width
                    
                    if newTermX + newTermWidth > minX + screenWidth {
                        newTermWidth = (minX + screenWidth) - newTermX
                    }
                    
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
                        x = newTermX
                        width = newTermWidth
                    }
                }
            }
            
            // Calculate FineTerm Frame
            guard let primaryScreen = NSScreen.screens.first else { return }
            let screenHeight = primaryScreen.frame.height
            let cocoaY = screenHeight - (y + height)
            let cocoaX = x - fixedWidth - gap
            let newFrame = NSRect(x: cocoaX, y: cocoaY, width: fixedWidth, height: height)
            
            if window.frame != newFrame {
                window.setFrame(newFrame, display: true)
            }
            
        } else {
            // Terminal is NOT on this space (or minimized/hidden)
            // Fix Blink: Do not blindly orderOut if we just switched spaces.
            // Only hide if the app itself is hidden.
            if termApp.isHidden {
                if window.isVisible {
                    window.orderOut(nil)
                }
            }
        }
    }
    
    // ... (rest of methods)
    
    func setupLogging() {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let tmpDir = home.appendingPathComponent("tmp")
        
        do {
            try fileManager.createDirectory(at: tmpDir, withIntermediateDirectories: true, attributes: nil)
            let logFile = tmpDir.appendingPathComponent("fineterm_debug.log")
            let path = logFile.path
            freopen(path, "a+", stdout)
            freopen(path, "a+", stderr)
            setbuf(stdout, nil)
            setbuf(stderr, nil)
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
        window.minSize = NSSize(width: 320, height: 200)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "FineTerm"
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
    }
    
    func startServices() {
        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.start()
        keyboardInterceptor = KeyboardInterceptor()
        keyboardInterceptor?.start()
        clipboardStore.startMonitoring()
        refreshTerminalObserverState()
    }
    
    func setupLocalShortcutMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let defaults = UserDefaults.standard
            let targetKeyChar = defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n"
            let targetModifierStr = defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"
            
            if let targetCode = KeyboardInterceptor.getKeyCode(for: targetKeyChar),
               event.keyCode == targetCode {
                let flags = event.modifierFlags
                var modifierMatch = false
                switch targetModifierStr {
                    case "command": modifierMatch = flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
                    case "control": modifierMatch = flags.contains(.control) && !flags.contains(.command) && !flags.contains(.option)
                    case "option": modifierMatch = flags.contains(.option) && !flags.contains(.command) && !flags.contains(.control)
                    default: modifierMatch = false
                }
                
                if modifierMatch {
                    if let mainWin = self.window, let keyWindow = NSApp.keyWindow, keyWindow !== mainWin {
                        self.settingsManager.close()
                        self.clipboardManager.close()
                        if mainWin.isMiniaturized { mainWin.deminiaturize(nil) }
                        mainWin.makeKeyAndOrderFront(nil)
                        return nil
                    }
                }
            }
            return event
        }
    }
    
    func toggleClipboardWindow() { clipboardManager.toggle() }
    @objc func openSettings() { settingsManager.open() }
    @objc func clearClipboardHistory() { clipboardStore.clear() }

    func windowWillClose(_ notification: Notification) {
        if let closedWindow = notification.object as? NSWindow, closedWindow === window {
            NSApp.hide(nil)
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mouseInterceptor?.stop()
        keyboardInterceptor?.stop()
        clipboardStore.stopMonitoring()
        terminalObserver?.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}