import Cocoa
import ApplicationServices

private var globalKeyboardEventTap: CFMachPort?

// State for the Origin Loop (Origin -> FineTerm -> Terminal -> Origin)
private var savedOriginBundleID: String?

// Cache for Custom Shortcuts to prevent JSON decoding on every keystroke
private var cachedCustomShortcuts: [CustomAppShortcut] = []
private var userDefaultsObserver: NSObjectProtocol?

fileprivate func refreshCustomShortcutsCache() {
    if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.customAppShortcuts),
       let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
        cachedCustomShortcuts = shortcuts
    } else {
        cachedCustomShortcuts = []
    }
}

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased()
        switch lower {
            case "a": return 0; case "s": return 1; case "d": return 2; case "f": return 3; case "h": return 4
            case "g": return 5; case "z": return 6; case "x": return 7; case "c": return 8; case "v": return 9
            case "b": return 11; case "q": return 12; case "w": return 13; case "e": return 14; case "r": return 15
            case "y": return 16; case "t": return 17; case "1": return 18; case "2": return 19; case "3": return 20
            case "4": return 21; case "6": return 22; case "5": return 23; case "=": return 24; case "9": return 25
            case "7": return 26; case "-": return 27; case "8": return 28; case "0": return 29; case "]": return 30
            case "o": return 31; case "u": return 32; case "[": return 33; case "i": return 34; case "p": return 35
            case "l": return 37; case "j": return 38; case "'": return 39; case "k": return 40; case ";": return 41
            case "\\": return 42; case ",": return 43; case "/": return 44; case "n": return 45; case "m": return 46
            case ".": return 47; default: return nil
        }
    }

    func start() {
        refreshCustomShortcutsCache()
        userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            refreshCustomShortcutsCache()
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: keyboardEventCallback,
            userInfo: nil
        ) else { return }

        self.eventTap = tap
        globalKeyboardEventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        
        if let rls = self.runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), rls, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let rls = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rls, .commonModes)
            }
        }
        if let obs = userDefaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        globalKeyboardEventTap = nil
        eventTap = nil
        runLoopSource = nil
        savedOriginBundleID = nil
    }
}

func isModifierMatch(flags: CGEventFlags, targetStr: String) -> Bool {
    switch targetStr {
        case "command": return flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        case "control": return flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
        case "option":  return flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
        default: return false
    }
}

// Helpers for Activation
func activateApp(bundleID: String) {
    let workspace = NSWorkspace.shared
    guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else { return }
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    workspace.openApplication(at: url, configuration: config, completionHandler: nil)
}

func activateFineTerm() {
    DispatchQueue.main.async {
        guard let appDelegate = NSApp.delegate as? AppDelegate, let window = appDelegate.window else { return }
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        if UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal) { appDelegate.snapToTerminal() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !NSApp.isActive {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}

func activateTerminal() {
    DispatchQueue.main.async {
        let target = UserDefaults.standard.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
        activateApp(bundleID: target)
    }
}

// Struct to hold stable window properties for sorting
struct CycleWindow {
    let app: NSRunningApplication
    let axWindow: AXUIElement
    let appIndex: Int
    let title: String
    let frame: CGRect
    let isFocused: Bool
}

// Stable Round-Robin Cycling Engine
func executeCustomShortcutCycle(validBundleIDs: [String], frontApp: NSRunningApplication?) {
    var cycleWindows: [CycleWindow] = []
    let workspace = NSWorkspace.shared
    
    // 1. Gather all standard windows for all target apps
    for (index, bundleID) in validBundleIDs.enumerated() {
        let apps = workspace.runningApplications.filter { $0.bundleIdentifier == bundleID }
        for app in apps {
            let pid = app.processIdentifier
            let axApp = AXUIElementCreateApplication(pid)
            
            var windowsRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsRef) == .success,
               let windows = windowsRef as? [AXUIElement] {
                
                var focusedWindowRef: CFTypeRef?
                AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindowRef)
                let focusedWindow = focusedWindowRef as! AXUIElement? // Can be nil
                
                for window in windows {
                    // Filter Standard Windows
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
                       
                    // Get Position and Size to filter out 0x0 ghosts
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
                    } else {
                        continue
                    }
                    
                    // Get Title for secondary stable sorting
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    
                    // Electron apps sometimes fail `kAXFocusedWindowAttribute`. Fallback to `kAXMainAttribute`
                    var isMain = false
                    var mainRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(window, kAXMainAttribute as CFString, &mainRef) == .success,
                       let m = mainRef as? NSNumber, m.boolValue {
                        isMain = true
                    }
                    
                    let isFocused = (frontApp?.processIdentifier == pid) && 
                                    ((focusedWindow != nil && CFEqual(window, focusedWindow!)) || isMain)
                    
                    cycleWindows.append(CycleWindow(app: app, axWindow: window, appIndex: index, title: title, frame: frame, isFocused: isFocused))
                }
            }
        }
    }
    
    // 2. Fallback if no windows exist (app is closed or completely hidden)
    if cycleWindows.isEmpty {
        if let firstID = validBundleIDs.first {
            activateApp(bundleID: firstID)
        }
        return
    }
    
    // 3. Stable Sort: App Order -> Title -> X Position -> Y Position
    // This creates an immutable array order (e.g. [VSCode_Window1, Sublime_Window1, Sublime_Window2])
    cycleWindows.sort { a, b in
        if a.appIndex != b.appIndex { return a.appIndex < b.appIndex }
        if a.title != b.title { return a.title < b.title }
        if abs(a.frame.origin.x - b.frame.origin.x) > 1.0 { return a.frame.origin.x < b.frame.origin.x }
        return a.frame.origin.y < b.frame.origin.y
    }
    
    // 4. Find the currently focused window in our stable list
    var targetIndex = 0
    if let currentIndex = cycleWindows.firstIndex(where: { $0.isFocused }) {
        // Round Robin: Take the next window, loop back to 0 if at the end
        targetIndex = (currentIndex + 1) % cycleWindows.count
    } else if let frontID = frontApp?.bundleIdentifier, let frontAppIndex = validBundleIDs.firstIndex(of: frontID) {
        // App is frontmost, but no specific window is focused (e.g., system dialog active)
        // Jump to the next app in the group
        let nextAppIndex = (frontAppIndex + 1) % validBundleIDs.count
        if let firstForNextApp = cycleWindows.firstIndex(where: { $0.appIndex == nextAppIndex }) {
            targetIndex = firstForNextApp
        }
    }
    
    let target = cycleWindows[targetIndex]
    
    // 5. Aggressive OS Targeting
    // Just activating the app isn't enough; we force the OS to raise the specific AXUIElement
    target.app.activate(options: .activateIgnoringOtherApps)
    
    let axApp = AXUIElementCreateApplication(target.app.processIdentifier)
    AXUIElementSetAttributeValue(axApp, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
    
    AXUIElementSetAttributeValue(target.axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
    AXUIElementSetAttributeValue(target.axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    AXUIElementPerformAction(target.axWindow, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, target.axWindow)
}

// Robust Helper to find the REAL frontmost app, bypassing NSWorkspace lag
func getRealFrontmostApp() -> NSRunningApplication? {
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

func keyboardEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = globalKeyboardEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    
    guard type == .keyDown else { return Unmanaged.passUnretained(event) }
    
    let flags = event.flags
    let hasModifier = flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
    if !hasModifier { return Unmanaged.passUnretained(event) }
    
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let defaults = UserDefaults.standard
    
    // --- STAGE 1: LIGHTNING FAST PRE-MATCHING ---
    // Do NOT call expensive APIs (like Window Z-Order) unless we perfectly match a registered shortcut
    
    var matchedCustomShortcut: CustomAppShortcut?
    for shortcut in cachedCustomShortcuts {
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        if !validBundleIDs.isEmpty && !shortcut.key.isEmpty {
            if let code = KeyboardInterceptor.getKeyCode(for: shortcut.key),
               keyCode == Int64(code),
               isModifierMatch(flags: flags, targetStr: shortcut.modifier) {
                matchedCustomShortcut = shortcut
                break
            }
        }
    }
    
    let mainKey = defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n"
    let mainMod = defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"
    let mainCode = KeyboardInterceptor.getKeyCode(for: mainKey)
    let isMainMatch = (mainCode != nil && keyCode == Int64(mainCode!)) && isModifierMatch(flags: flags, targetStr: mainMod)
    
    let toggleKey = defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h"
    let toggleMod = defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command"
    let toggleCode = KeyboardInterceptor.getKeyCode(for: toggleKey)
    let isToggleMatch = defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) && (toggleCode != nil && keyCode == Int64(toggleCode!)) && isModifierMatch(flags: flags, targetStr: toggleMod)
    
    let clipKey = defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u"
    let clipMod = defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command"
    let clipCode = KeyboardInterceptor.getKeyCode(for: clipKey)
    let isClipMatch = defaults.bool(forKey: AppConfig.Keys.enableClipboardManager) && (clipCode != nil && keyCode == Int64(clipCode!)) && isModifierMatch(flags: flags, targetStr: clipMod)
    
    // EARLY EXIT: If this keypress doesn't match any of our configured shortcuts, let it pass instantly.
    if matchedCustomShortcut == nil && !isMainMatch && !isToggleMatch && !isClipMatch {
        return Unmanaged.passUnretained(event)
    }
    
    // --- STAGE 2: MATCH CONFIRMED, FETCH SYSTEM STATE ---
    let frontApp = getRealFrontmostApp()
    
    // Execute Custom App Shortcut
    if let shortcut = matchedCustomShortcut {
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        
        // Dispatch to main thread immediately because AXUIElement APIs require a RunLoop context to process reliably
        DispatchQueue.main.async {
            executeCustomShortcutCycle(validBundleIDs: validBundleIDs, frontApp: frontApp)
        }
        return nil // Swallow event
    }
    
    // Execute Main Shortcut Loop
    let target = defaults.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
    let isTerminalFront = frontApp?.bundleIdentifier == target
    let isFineTermFront = NSRunningApplication.current.isActive
    
    if isMainMatch {
        let mainAnywhere = defaults.bool(forKey: AppConfig.Keys.globalShortcutAnywhere)
        let secondActivation = defaults.bool(forKey: AppConfig.Keys.secondActivationToTerminal)
        let thirdActivation = defaults.bool(forKey: AppConfig.Keys.thirdActivationToOrigin)
        
        if !mainAnywhere && !isTerminalFront && !isFineTermFront { return Unmanaged.passUnretained(event) }
        
        if isFineTermFront {
            if secondActivation { activateTerminal(); return nil }
            return Unmanaged.passUnretained(event)
        }
        
        if isTerminalFront {
            if secondActivation && thirdActivation, let originID = savedOriginBundleID, originID != target, originID != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async { activateApp(bundleID: originID) }
                return nil
            }
            activateFineTerm()
            return nil
        }
        
        if !isFineTermFront && !isTerminalFront {
            if let app = frontApp, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier, bundleID != target {
                savedOriginBundleID = bundleID
            }
            activateFineTerm()
            return nil
        }
    }
    
    // Execute Terminal Toggle
    if isToggleMatch {
        if isTerminalFront {
            if let originID = savedOriginBundleID, originID != target, originID != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async { activateApp(bundleID: originID) }
                return nil
            }
            return Unmanaged.passUnretained(event) // Fallback to native Cmd+H
        } else {
            if !isFineTermFront, let app = frontApp, let bundleID = app.bundleIdentifier, bundleID != target, bundleID != Bundle.main.bundleIdentifier {
                savedOriginBundleID = bundleID
            }
            activateTerminal()
            return nil
        }
    }
    
    // Execute Clipboard Toggle
    if isClipMatch {
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.toggleClipboardWindow() }
        }
        return nil
    }
    
    return Unmanaged.passUnretained(event)
}