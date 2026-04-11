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
    let debug = defaults.bool(forKey: AppConfig.Keys.debugMode)
    let frontApp = getRealFrontmostApp()
    
    // Execute Custom App Shortcut
    if let shortcut = matchedCustomShortcut {
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        let frontID = frontApp?.bundleIdentifier ?? ""
        
        if let currentIndex = validBundleIDs.firstIndex(of: frontID) {
            // We are ALREADY in this group -> Cycle to the next app
            let nextIndex = (currentIndex + 1) % validBundleIDs.count
            let targetApp = validBundleIDs[nextIndex]
            if debug { print("DEBUG: Cycling group to \(targetApp)") }
            DispatchQueue.main.async { activateApp(bundleID: targetApp) }
        } else {
            // Coming from outside -> Find the most recently active app in this group using Focus Tracker
            let targetApp = AppFocusTracker.shared.getMostRecent(from: validBundleIDs) ?? validBundleIDs[0]
            if debug { print("DEBUG: Switching to most recent in group: \(targetApp)") }
            DispatchQueue.main.async { activateApp(bundleID: targetApp) }
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