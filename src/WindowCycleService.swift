import Cocoa
import ApplicationServices

struct CycleWindow {
    let app: NSRunningApplication
    let axWindow: AXUIElement
    let appIndex: Int
    let title: String
    let frame: CGRect
    let isFocused: Bool
}

struct WindowCycleService {
    
    static func activateApp(bundleID: String) {
        let workspace = NSWorkspace.shared
        guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        workspace.openApplication(at: url, configuration: config, completionHandler: nil)
    }

    static func activateFineTerm() {
        DispatchQueue.main.async {
            guard let appDelegate = NSApp.delegate as? AppDelegate, let window = appDelegate.window else { return }
            NSApp.unhide(nil)
            if window.isMiniaturized { window.deminiaturize(nil) }
            if UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal) { appDelegate.snapToTerminal() }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                if !NSApp.isActive {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    static func activateTerminal() {
        DispatchQueue.main.async {
            let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
            activateApp(bundleID: target)
        }
    }

    static func executeCustomShortcutCycle(validBundleIDs: [String], frontApp: NSRunningApplication?) {
        let frontID = frontApp?.bundleIdentifier ?? ""
        let skipNonRunning = UserDefaults.standard.bool(forKey: AppConfig.Keys.skipNonRunningApps)
        
        let workspace = NSWorkspace.shared
        var effectiveBundleIDs = validBundleIDs
        
        if skipNonRunning {
            let runningIDs = Set(workspace.runningApplications.compactMap { $0.bundleIdentifier })
            let filtered = validBundleIDs.filter { runningIDs.contains($0) }
            if !filtered.isEmpty {
                effectiveBundleIDs = filtered
            }
        }
        
        if !effectiveBundleIDs.contains(frontID) {
            let targetAppID = AppFocusTracker.shared.getMostRecent(from: effectiveBundleIDs) ?? effectiveBundleIDs[0]
            activateApp(bundleID: targetAppID)
            return
        }
        
        var cycleWindows: [CycleWindow] = []
        
        for (index, bundleID) in effectiveBundleIDs.enumerated() {
            let apps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleID }
            for app in apps {
                let pid = app.processIdentifier
                let axApp = AXUIElementCreateApplication(pid)
                
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let windows = windowsRef as? [AXUIElement] {
                    
                    var focusedWindowRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                    let focusedWindow = focusedWindowRef as! AXUIElement?
                    
                    for window in windows {
                        var roleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &roleRef)
                        if (roleRef as? String) != kAXWindowRole { continue }
                        
                        var subroleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subroleRef)
                        let subrole = subroleRef as? String ?? ""
                        if subrole != kAXStandardWindowSubrole && subrole != "" { continue }
                        
                        var minRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minRef) == .success,
                           let isMin = minRef as? NSNumber, isMin.boolValue { continue }
                           
                        var posRef: CFTypeRef?
                        var sizeRef: CFTypeRef?
                        var frame: CGRect = .zero
                        
                        if AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
                           AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success {
                           if let p = posRef, let s = sizeRef, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() {
                               var pos: CGPoint = .zero
                               var size: CGSize = .zero
                               AXValueGetValue(p as! AXValue, .cgPoint, &pos)
                               AXValueGetValue(s as! AXValue, .cgSize, &size)
                               
                               if size.width < 100 || size.height < 100 { continue }
                               frame = CGRect(origin: pos, size: size)
                           }
                        } else { continue }
                        
                        var titleRef: CFTypeRef?
                        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                        let title = titleRef as? String ?? ""
                        
                        var isMain = false
                        var mainRef: CFTypeRef?
                        if AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef) == .success,
                           let m = mainRef as? NSNumber, m.boolValue { isMain = true }
                        
                        let isFocused = (frontApp?.processIdentifier == pid) && 
                                        ((focusedWindow != nil && CFEqual(window, focusedWindow!)) || isMain)
                        
                        cycleWindows.append(CycleWindow(app: app, axWindow: window, appIndex: index, title: title, frame: frame, isFocused: isFocused))
                    }
                }
            }
        }
        
        cycleWindows.sort { a, b in
            if a.appIndex != b.appIndex { return a.appIndex < b.appIndex }
            if a.title != b.title { return a.title < b.title }
            if abs(a.frame.origin.x - b.frame.origin.x) > 1.0 { return a.frame.origin.x < b.frame.origin.x }
            return a.frame.origin.y < b.frame.origin.y
        }
        
        var targetIndex = -1
        
        if let currentIndex = cycleWindows.firstIndex(where: { $0.isFocused }) {
            let currentWindow = cycleWindows[currentIndex]
            let currentAppBundleID = currentWindow.app.bundleIdentifier ?? ""
            
            if currentIndex + 1 < cycleWindows.count {
                let nextWindow = cycleWindows[currentIndex + 1]
                if nextWindow.app.bundleIdentifier == currentAppBundleID {
                    targetIndex = currentIndex + 1
                } else {
                    if let frontAppIndex = effectiveBundleIDs.firstIndex(of: currentAppBundleID) {
                        let nextAppIndex = (frontAppIndex + 1) % effectiveBundleIDs.count
                        let nextBundleID = effectiveBundleIDs[nextAppIndex]
                        
                        if let firstWindow = cycleWindows.firstIndex(where: { $0.app.bundleIdentifier == nextBundleID }) {
                            targetIndex = firstWindow
                        } else {
                            activateApp(bundleID: nextBundleID)
                            return
                        }
                    } else {
                        targetIndex = (currentIndex + 1) % cycleWindows.count
                    }
                }
            } else {
                if let frontAppIndex = effectiveBundleIDs.firstIndex(of: currentAppBundleID) {
                    let nextAppIndex = (frontAppIndex + 1) % effectiveBundleIDs.count
                    let nextBundleID = effectiveBundleIDs[nextAppIndex]
                    
                    if let firstWindow = cycleWindows.firstIndex(where: { $0.app.bundleIdentifier == nextBundleID }) {
                        targetIndex = firstWindow
                    } else {
                            activateApp(bundleID: nextBundleID)
                            return
                    }
                } else {
                    targetIndex = 0
                }
            }
        } else if let frontAppIndex = effectiveBundleIDs.firstIndex(of: frontID) {
            let nextAppIndex = (frontAppIndex + 1) % effectiveBundleIDs.count
            let nextBundleID = effectiveBundleIDs[nextAppIndex]
            
            if let firstWindow = cycleWindows.firstIndex(where: { $0.app.bundleIdentifier == nextBundleID }) {
                targetIndex = firstWindow
            } else {
                activateApp(bundleID: nextBundleID)
                return
            }
        }
        
        if targetIndex >= 0 && targetIndex < cycleWindows.count {
            let target = cycleWindows[targetIndex]
            
            target.app.activate(options: .activateIgnoringOtherApps)
            let axApp = AXUIElementCreateApplication(target.app.processIdentifier)
            AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(target.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(target.axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(target.axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, target.axWindow)
        } else {
            if !effectiveBundleIDs.isEmpty {
                activateApp(bundleID: effectiveBundleIDs[0])
            }
        }
    }

    static func getRealFrontmostApp() -> NSRunningApplication? {
        let workspace = NSWorkspace.shared
        let workspaceApp = workspace.frontmostApplication
        let myBundleID = Bundle.main.bundleIdentifier ?? "com.local.FineTerm"
        
        if NSRunningApplication.current.isActive { return NSRunningApplication.current }
        
        var trustWorkspace = true
        if let id = workspaceApp?.bundleIdentifier, id == myBundleID { trustWorkspace = false }
        if trustWorkspace { return workspaceApp }
        
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return workspaceApp
        }
        
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let pid = pidNumber.int32Value
            if let app = NSRunningApplication(processIdentifier: pid) {
                if app.bundleIdentifier == myBundleID { continue }
                if app.activationPolicy == .regular { return app }
            }
        }
        return workspaceApp
    }
}