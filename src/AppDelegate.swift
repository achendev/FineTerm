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
    
    var libraryStore: LibraryStore!
    var libraryManager: LibraryWindowManager!
    var libraryAddManager: LibraryAddWindowManager!
    
    var settingsManager: SettingsWindowManager!
    
    var terminalObserver: TerminalWindowObserver?
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:withReplyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupLogging()
        AppConfig.registerDefaults()
        MenuManager.setupMainMenu()
        NSApp.setActivationPolicy(.regular)
        setupMainWindow()
        
        clipboardStore = ClipboardStore()
        clipboardManager = ClipboardWindowManager(store: clipboardStore)
        libraryStore = LibraryStore()
        libraryManager = LibraryWindowManager(store: libraryStore)
        libraryAddManager = LibraryAddWindowManager(store: libraryStore)
        settingsManager = SettingsWindowManager(store: clipboardStore, libraryStore: libraryStore)
        
        checkPermissionsAndStart()
        setupLocalShortcutMonitor()
        TextEditorBridge.shared.warmUp()
        setupTerminalObserver()
        AppFocusTracker.shared.start()
        
        SystemModifierManager.applyCurrentSettings()
        SecureInputMonitor.shared.start()
        
        // Start Lightning-fast UDP action server (for Karabiner mode latency fix)
        LocalActionServer.shared.start()
    }
    
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "fineterm",
              url.host == "action" else { return }

        let path = url.path
        let query = url.query

        DispatchQueue.main.async {
            switch path {
            case "/next-group": WindowCycleService.executeCycle(isNext: true, isPrev: false, isToggle: false)
            case "/prev-group": WindowCycleService.executeCycle(isNext: false, isPrev: true, isToggle: false)
            case "/toggle-group": WindowCycleService.executeCycle(isNext: false, isPrev: false, isToggle: true)
            case "/custom-shortcut":
                if let q = query, let idString = q.components(separatedBy: "=").last, let id = UUID(uuidString: idString) {
                    WindowCycleService.executeCustomShortcut(by: id)
                }
            case "/clipboard": self.toggleClipboardWindow()
            case "/library-add": self.showLibraryAddWindow()
            case "/library-open": self.toggleLibraryWindow()
            case "/terminal-toggle": WindowCycleService.handleTerminalToggle()
            case "/main-toggle": WindowCycleService.handleMainToggle()
            default: break
            }
        }
    }
    
    func setupTerminalObserver() {
        terminalObserver = TerminalWindowObserver {[weak self] in
            self?.snapToTerminal()
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(snapToTerminal), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        refreshTerminalObserverState()
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) {[weak self] notif in
            guard let app = notif.userInfo? [NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
            if app.bundleIdentifier == target { self?.refreshTerminalObserverState() }
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) {[weak self] notif in
            guard let app = notif.userInfo? [NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
            if app.bundleIdentifier == target { self?.refreshTerminalObserverState() }
        }
    }
    
    @objc func refreshTerminalObserverState() {
        let shouldSnap = UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal)
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        let terminalApp = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == target }
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
        
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        guard let termApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == target }) else { return }
        let pid = termApp.processIdentifier
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        
        var foundTerminal = false
        var termRect: CGRect = .zero
        
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pid,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = boundsDict["Width"], let height = boundsDict["Height"],
                  width > 100, height > 100 else { continue }
            
            let x = boundsDict["X"] ?? 0
            let y = boundsDict["Y"] ?? 0
            termRect = CGRect(x: x, y: y, width: width, height: height)
            foundTerminal = true
            break
        }
        
        if foundTerminal {
            if !window.isVisible { window.makeKeyAndOrderFront(nil) }
            
            var x = termRect.origin.x
            let y = termRect.origin.y
            var width = termRect.width
            let height = termRect.height
            
            let fixedWidth: CGFloat = 220
            let gap: CGFloat = 1
            
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
                
                if x - minX < fixedWidth + gap {
                    let newTermX = minX + fixedWidth + gap
                    var newTermWidth = width
                    
                    if newTermX + newTermWidth > minX + screenWidth {
                        newTermWidth = (minX + screenWidth) - newTermX
                    }
                    
                    if abs(newTermX - x) > 1 || abs(newTermWidth - width) > 1 {
                        var processName = "Terminal"
                        if target == "com.googlecode.iterm2" { processName = "iTerm2" }
                        else if target == "com.mitchellh.ghostty" { processName = "Ghostty" }
                        
                        let script = """
                        tell application "System Events" to tell process "\(processName)"
                            set position of window 1 to {\(Int(newTermX)), \(Int(y))}
                            set size of window 1 to {\(Int(newTermWidth)), \(Int(height))}
                        end tell
                        """
                        var error: NSDictionary?
                        if let nsScript = NSAppleScript(source: script) { nsScript.executeAndReturnError(&error) }
                        x = newTermX
                        width = newTermWidth
                    }
                }
            }
            
            guard let primaryScreen = NSScreen.screens.first else { return }
            let screenHeight = primaryScreen.frame.height
            let cocoaY = screenHeight - (y + height)
            let cocoaX = x - fixedWidth - gap
            let newFrame = NSRect(x: cocoaX, y: cocoaY, width: fixedWidth, height: height)
            
            if window.frame != newFrame { window.setFrame(newFrame, display: true) }
        } else {
            if termApp.isHidden {
                if window.isVisible { window.orderOut(nil) }
            }
        }
    }
    
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
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 500), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 200)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "FineTerm"
        window.delegate = self
    }

    func checkPermissionsAndStart() {
        if PermissionManager.checkAccessibility() { startMainApp() } else { showPermissionOverlay() }
    }

    func showPermissionOverlay() {
        let permissionView = PermissionView {[weak self] in self?.startMainApp() }
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
        window.contentView = NSHostingView(rootView: ConnectionListView())
        startServices()
        showMainWindowWithTerminalFocus()
    }
    
    func showMainWindowWithTerminalFocus() {
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        if let terminalApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == target }) {
            var terminalOnCurrentSpace = false
            let pid = terminalApp.processIdentifier
            let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
            if let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
                for info in windowList {
                    if let ownerPID = info[kCGWindowOwnerPID as String] as? Int, ownerPID == pid {
                        terminalOnCurrentSpace = true
                        break
                    }
                }
            }
            if terminalOnCurrentSpace {
                self.window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                terminalApp.activate(options: [.activateIgnoringOtherApps])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        } else {
            self.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
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
            
            if let targetCode = KeyboardParser.getKeyCode(for: targetKeyChar), event.keyCode == targetCode {
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
                        self.libraryManager.close()
                        self.libraryAddManager.close()
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
    func toggleLibraryWindow() { libraryManager.toggle() }
    func showLibraryAddWindow() { libraryAddManager.show() }
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
        SystemModifierManager.reset()
        SecureInputMonitor.shared.stop()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if window.isMiniaturized { window.deminiaturize(nil) }
        showMainWindowWithTerminalFocus()
        return true
    }
}