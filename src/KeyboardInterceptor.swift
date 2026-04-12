import Cocoa
import ApplicationServices

private var globalKeyboardEventTap: CFMachPort?

// State for the Origin Loop (Origin -> FineTerm -> Terminal -> Origin)
private var savedOriginBundleID: String?
private var lastUsedShortcutID: UUID?

// Cache for Custom Shortcuts to prevent JSON decoding on every keystroke
private var cachedCustomShortcuts: [CustomAppShortcut] = []
private var cachedNextGroupTriggers: [ShortcutTrigger] = []
private var cachedPrevGroupTriggers: [ShortcutTrigger] = []
private var cachedToggleGroupTriggers: [ShortcutTrigger] = []
private var userDefaultsObserver: NSObjectProtocol?

fileprivate func refreshCustomShortcutsCache() {
    if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.customAppShortcuts),
       let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
        cachedCustomShortcuts = shortcuts
    } else {
        cachedCustomShortcuts = []
    }
    
    cachedNextGroupTriggers = loadTriggers(forKey: AppConfig.Keys.nextGroupTriggers, oldMod1: AppConfig.Keys.nextGroupModifier, oldMod2: AppConfig.Keys.nextGroupModifier2, oldKey: AppConfig.Keys.nextGroupKey, defaultKey: ".")
    cachedPrevGroupTriggers = loadTriggers(forKey: AppConfig.Keys.prevGroupTriggers, oldMod1: AppConfig.Keys.prevGroupModifier, oldMod2: AppConfig.Keys.prevGroupModifier2, oldKey: AppConfig.Keys.prevGroupKey, defaultKey: ",")
    cachedToggleGroupTriggers = loadTriggers(forKey: AppConfig.Keys.toggleGroupTriggers, oldMod1: AppConfig.Keys.toggleGroupModifier, oldMod2: AppConfig.Keys.toggleGroupModifier2, oldKey: AppConfig.Keys.toggleGroupKey, defaultKey: "/")
}

fileprivate func loadTriggers(forKey key: String, oldMod1: String, oldMod2: String, oldKey: String, defaultKey: String) ->[ShortcutTrigger] {
    if let data = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: data), !decoded.isEmpty {
        return decoded
    }
    let m1 = UserDefaults.standard.string(forKey: oldMod1) ?? "right control"
    let m2 = UserDefaults.standard.string(forKey: oldMod2) ?? "shift"
    let k = UserDefaults.standard.string(forKey: oldKey) ?? defaultKey
    return[ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
}

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
            case "esc", "escape": return 53
            case "tab": return 48
            case "space": return 49
            case "enter", "return": return 36
            case "capslock", "caps lock": return 57
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
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
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
        lastUsedShortcutID = nil
    }
}

// Ultra-fast exact modifier matching, including left/right specific checks
func isModifierMatch(flags: CGEventFlags, mod1: String, mod2: String?) -> Bool {
    var requiredMods = [String]()
    for m in [mod1, mod2].compactMap({ $0 }).filter({ $0 != "none" && !$0.isEmpty }) {
        requiredMods.append(m)
    }
    
    let hasCmd = flags.contains(.maskCommand)
    let hasCtrl = flags.contains(.maskControl)
    let hasOpt = flags.contains(.maskAlternate)
    let hasShift = flags.contains(.maskShift)
    
    let needsCmd = requiredMods.contains(where: { $0.contains("command") })
    let needsCtrl = requiredMods.contains(where: { $0.contains("control") })
    let needsOpt = requiredMods.contains(where: { $0.contains("option") })
    let needsShift = requiredMods.contains(where: { $0.contains("shift") })
    let needsCaps = requiredMods.contains("capslock")
    
    // Core Modifiers category must match perfectly
    if hasCmd != needsCmd || hasCtrl != needsCtrl || hasOpt != needsOpt || hasShift != needsShift {
        return false
    }
    
    if needsCaps && !flags.contains(.maskAlphaShift) {
        return false
    }
    
    // CoreGraphics raw values for precise Left/Right hardware matching
    let raw = flags.rawValue
    let leftCtrl = (raw & 0x01) != 0
    let leftShift = (raw & 0x02) != 0
    let rightShift = (raw & 0x04) != 0
    let leftCmd = (raw & 0x08) != 0
    let rightCmd = (raw & 0x10) != 0
    let leftOpt = (raw & 0x20) != 0
    let rightOpt = (raw & 0x40) != 0
    let rightCtrl = (raw & 0x2000) != 0
    
    // Enforce left/right strictly if requested
    for req in requiredMods {
        switch req {
        case "left command": if !leftCmd { return false }
        case "right command": if !rightCmd { return false }
        case "left control": if !leftCtrl { return false }
        case "right control": if !rightCtrl { return false }
        case "left option": if !leftOpt { return false }
        case "right option": if !rightOpt { return false }
        case "left shift": if !leftShift { return false }
        case "right shift": if !rightShift { return false }
        default: break
        }
    }
    
    return true
}

func isGlobalShortcutMatch(type: CGEventType, eventKeyCode: Int64, flags: CGEventFlags, keyStr: String, mod1Str: String, mod2Str: String?) -> Bool {
    if keyStr.isEmpty {
        let m1 = mod1Str
        let m2 = mod2Str ?? "none"
        
        if m1 == "none" && m2 == "none" { return false }
        
        if m1 == "none" || m2 == "none" {
            let activeMod = m1 != "none" ? m1 : m2
            let isSpecific = activeMod.hasPrefix("left ") || activeMod.hasPrefix("right ")
            if !isSpecific { return false } // Block single-modifier pure shortcuts unless they are specific left/right
        }
        
        return type == .flagsChanged && isModifierMatch(flags: flags, mod1: m1, mod2: m2)
    } else {
        if type != .keyDown { return false }
        guard let code = KeyboardInterceptor.getKeyCode(for: keyStr) else { return false }
        return eventKeyCode == Int64(code) && isModifierMatch(flags: flags, mod1: mod1Str, mod2: mod2Str)
    }
}

func isAnyTriggerMatch(type: CGEventType, eventKeyCode: Int64, flags: CGEventFlags, triggers: [ShortcutTrigger]) -> Bool {
    for trigger in triggers {
        if isGlobalShortcutMatch(type: type, eventKeyCode: eventKeyCode, flags: flags, keyStr: trigger.key, mod1Str: trigger.modifier, mod2Str: trigger.modifier2) {
            return true
        }
    }
    return false
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
    let frontID = frontApp?.bundleIdentifier ?? ""
    let isDebug = UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode)
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
        if isDebug { print("DEBUG: Switching from outside to most recent in group: \(targetAppID)") }
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
                    } else {
                        continue
                    }
                    
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    
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
    
    guard type == .keyDown || type == .flagsChanged else { return Unmanaged.passUnretained(event) }
    
    let flags = event.flags
    let keyCode = type == .keyDown ? event.getIntegerValueField(.keyboardEventKeycode) : -1
    let defaults = UserDefaults.standard
    
    // --- STAGE 1: LIGHTNING FAST PRE-MATCHING (Zero System Calls) ---
    
    let isNextMatch = defaults.bool(forKey: AppConfig.Keys.enableNextGroupShortcut) &&
        isAnyTriggerMatch(type: type, eventKeyCode: keyCode, flags: flags, triggers: cachedNextGroupTriggers)
                              
    let isPrevMatch = defaults.bool(forKey: AppConfig.Keys.enablePrevGroupShortcut) &&
        isAnyTriggerMatch(type: type, eventKeyCode: keyCode, flags: flags, triggers: cachedPrevGroupTriggers)

    let isToggleGroupMatch = defaults.bool(forKey: AppConfig.Keys.enableToggleGroupShortcut) &&
        isAnyTriggerMatch(type: type, eventKeyCode: keyCode, flags: flags, triggers: cachedToggleGroupTriggers)
    
    var matchedCustomShortcut: CustomAppShortcut?
    for shortcut in cachedCustomShortcuts {
        if !shortcut.isEnabled { continue }
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        if validBundleIDs.isEmpty { continue }
        
        if isAnyTriggerMatch(type: type, eventKeyCode: keyCode, flags: flags, triggers: shortcut.triggers) {
            matchedCustomShortcut = shortcut
            break
        }
    }
    
    let isMainMatch = isGlobalShortcutMatch(type: type, eventKeyCode: keyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isToggleMatch = defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) &&
                        isGlobalShortcutMatch(type: type, eventKeyCode: keyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isClipMatch = defaults.bool(forKey: AppConfig.Keys.enableClipboardManager) &&
                      isGlobalShortcutMatch(type: type, eventKeyCode: keyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command",
                                            mod2Str: nil)
    
    // EARLY EXIT
    if !isNextMatch && !isPrevMatch && !isToggleGroupMatch && matchedCustomShortcut == nil && !isMainMatch && !isToggleMatch && !isClipMatch {
        return Unmanaged.passUnretained(event)
    }
    
    // --- STAGE 2: MATCH CONFIRMED, FETCH SYSTEM STATE ---
    let frontApp = getRealFrontmostApp()
    
    // Execute Group Navigation
    if isNextMatch || isPrevMatch || isToggleGroupMatch {
        let validShortcuts = cachedCustomShortcuts.filter { $0.isEnabled && $0.bundleIDs.contains(where: { !$0.isEmpty }) }
        if !validShortcuts.isEmpty {
            var target: CustomAppShortcut?
            var currentIdx = -1
            
            // 1. Check if frontmost app belongs to ANY group
            if let frontID = frontApp?.bundleIdentifier {
                currentIdx = validShortcuts.firstIndex(where: { $0.bundleIDs.contains(frontID) }) ?? -1
            }
            
            // 2. Fallback to last remembered group if outside a bound app
            if currentIdx == -1 {
                currentIdx = validShortcuts.firstIndex(where: { $0.id == lastUsedShortcutID }) ?? -1
            }
            
            // 3. Navigate Direction
            if isNextMatch {
                let nextIdx = (currentIdx + 1) % validShortcuts.count
                target = validShortcuts[nextIdx]
            } else if isPrevMatch {
                let baseIdx = currentIdx == -1 ? 0 : currentIdx
                let prevIdx = (baseIdx - 1 + validShortcuts.count) % validShortcuts.count
                target = validShortcuts[prevIdx]
            } else if isToggleGroupMatch {
                let baseIdx = currentIdx == -1 ? 0 : currentIdx
                target = validShortcuts[baseIdx]
            }
            
            if let t = target {
                lastUsedShortcutID = t.id
                DispatchQueue.main.async { executeCustomShortcutCycle(validBundleIDs: t.bundleIDs.filter({!$0.isEmpty}), frontApp: frontApp) }
            }
        }
        return type == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    // Execute Specific Custom Shortcut
    if let shortcut = matchedCustomShortcut {
        lastUsedShortcutID = shortcut.id
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        DispatchQueue.main.async {
            executeCustomShortcutCycle(validBundleIDs: validBundleIDs, frontApp: frontApp)
        }
        return type == .keyDown ? nil : Unmanaged.passUnretained(event)
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
    
    if isToggleMatch {
        if isTerminalFront {
            if let originID = savedOriginBundleID, originID != target, originID != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async { activateApp(bundleID: originID) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        } else {
            if !isFineTermFront, let app = frontApp, let bundleID = app.bundleIdentifier, bundleID != target, bundleID != Bundle.main.bundleIdentifier {
                savedOriginBundleID = bundleID
            }
            activateTerminal()
            return nil
        }
    }
    
    if isClipMatch {
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.toggleClipboardWindow() }
        }
        return nil
    }
    
    return Unmanaged.passUnretained(event)
}