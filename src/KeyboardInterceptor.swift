import Cocoa
import ApplicationServices

private var globalKeyboardEventTap: CFMachPort?

private var savedOriginBundleID: String?
private var lastUsedShortcutID: UUID?

// Magic tag to prevent infinite loops from our own synthesized events
private let magicEventSourceUserData: Int64 = 0x46696E65 // "Fine"

// Optimized Cache Structures
struct ParsedToAction {
    let keyCode: CGKeyCode
    let coreFlags: CGEventFlags
}

struct ParsedKeyMap {
    let original: KeyMap
    let fromKeyCode: CGKeyCode
    let fromCoreFlags: CGEventFlags
    let fromStrictFlags: [String]
    let isShell: Bool
    let shellCommand: String?
    let toActions: [ParsedToAction]
}

struct ParsedPCModeRule {
    let rule: PCModeRule
    let mappings: [ParsedKeyMap]
}

private var cachedCustomShortcuts: [CustomAppShortcut] = []
private var cachedParsedPCRules: [ParsedPCModeRule] = []
private var cachedNextGroupTriggers: [ShortcutTrigger] = []
private var cachedPrevGroupTriggers: [ShortcutTrigger] = []
private var cachedToggleGroupTriggers: [ShortcutTrigger] = []
private var userDefaultsObserver: NSObjectProtocol?

// State tracker to guarantee correct KeyUp events for synthesized KeyDowns
private var activeRemaps: [CGKeyCode: CGKeyCode] = [:]

fileprivate func refreshCustomShortcutsCache() {
    if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.customAppShortcuts),
       let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
        cachedCustomShortcuts = shortcuts
    } else {
        cachedCustomShortcuts = []
    }
    
    cachedParsedPCRules = []
    if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.pcModeRules),
       let rules = try? JSONDecoder().decode([PCModeRule].self, from: data) {
        
        for rule in rules where rule.isEnabled {
            var parsedMappings: [ParsedKeyMap] = []
            for map in rule.mappings {
                let fromParsed = KeyboardInterceptor.parseKeyString(map.from)
                guard !fromParsed.key.isEmpty else { continue }
                guard let fromCode = KeyboardInterceptor.getKeyCode(for: fromParsed.key) else { continue }
                
                var isShell = false
                var shellCommand: String? = nil
                var toActions: [ParsedToAction] = []
                
                if map.to.lowercased().hasPrefix("shell:") {
                    isShell = true
                    let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 6)
                    shellCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                } else {
                    let parts = map.to.components(separatedBy: ",")
                    for part in parts {
                        let toParsed = KeyboardInterceptor.parseKeyString(part)
                        guard !toParsed.key.isEmpty else { continue }
                        guard let code = KeyboardInterceptor.getKeyCode(for: toParsed.key) else { continue }
                        toActions.append(ParsedToAction(keyCode: code, coreFlags: toParsed.coreFlags))
                    }
                    if toActions.isEmpty { continue }
                }
                
                parsedMappings.append(ParsedKeyMap(
                    original: map, 
                    fromKeyCode: fromCode, 
                    fromCoreFlags: fromParsed.coreFlags, 
                    fromStrictFlags: fromParsed.strictFlags, 
                    isShell: isShell,
                    shellCommand: shellCommand,
                    toActions: toActions
                ))
            }
            
            // Sort by most specific modifiers first (e.g. Ctrl+Shift matches before Ctrl)
            parsedMappings.sort { $0.fromCoreFlags.rawValue.nonzeroBitCount > $1.fromCoreFlags.rawValue.nonzeroBitCount }
            cachedParsedPCRules.append(ParsedPCModeRule(rule: rule, mappings: parsedMappings))
        }
    }
    
    cachedNextGroupTriggers = loadTriggers(forKey: AppConfig.Keys.nextGroupTriggers, oldMod1: AppConfig.Keys.nextGroupModifier, oldMod2: AppConfig.Keys.nextGroupModifier2, oldKey: AppConfig.Keys.nextGroupKey, defaultKey: ".")
    cachedPrevGroupTriggers = loadTriggers(forKey: AppConfig.Keys.prevGroupTriggers, oldMod1: AppConfig.Keys.prevGroupModifier, oldMod2: AppConfig.Keys.prevGroupModifier2, oldKey: AppConfig.Keys.prevGroupKey, defaultKey: ",")
    cachedToggleGroupTriggers = loadTriggers(forKey: AppConfig.Keys.toggleGroupTriggers, oldMod1: AppConfig.Keys.toggleGroupModifier, oldMod2: AppConfig.Keys.toggleGroupModifier2, oldKey: AppConfig.Keys.toggleGroupKey, defaultKey: "/")
}

fileprivate func loadTriggers(forKey key: String, oldMod1: String, oldMod2: String, oldKey: String, defaultKey: String) -> [ShortcutTrigger] {
    if let data = UserDefaults.standard.data(forKey: key),
       let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: data), !decoded.isEmpty {
        return decoded
    }
    let m1 = UserDefaults.standard.string(forKey: oldMod1) ?? "right control"
    let m2 = UserDefaults.standard.string(forKey: oldMod2) ?? "shift"
    let k = UserDefaults.standard.string(forKey: oldKey) ?? defaultKey
    return [ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
}

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?
    
    // Maps NX_KEYTYPE media keys to standard F-key keycodes
    static let mediaKeyToFKey: [Int32: CGKeyCode] = [
        0: 111,  // VolUp -> F12
        1: 103,  // VolDown -> F11
        7: 109,  // Mute -> F10
        2: 120,  // BrightnessUp -> F2
        3: 122,  // BrightnessDown -> F1
        21: 97,  // KbdBrightUp -> F6
        22: 96,  // KbdBrightDown -> F5
        16: 100, // Play -> F8
        17: 101, // Next -> F9
        18: 98   // Prev -> F7
    ]

    static let specialKeyCodes: [String: CGKeyCode] = [
        "esc": 53, "escape": 53, "tab": 48, "space": 49, "spacebar": 49,
        "enter": 36, "return": 36, "capslock": 57, "caps_lock": 57,
        "left_arrow": 123, "right_arrow": 124, "down_arrow": 125, "up_arrow": 126,
        "home": 115, "end": 119, "page_up": 116, "page_down": 121,
        "delete_or_backspace": 51, "delete_forward": 117, "insert": 114,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        "hyphen": 27, "equal_sign": 24, "slash": 44, "backslash": 42,
        "left_shift": 56, "right_shift": 60, "left_control": 59, "right_control": 62,
        "left_option": 58, "right_option": 61, "left_command": 55, "right_command": 54,
        "lshift": 56, "rshift": 60, "lctrl": 59, "rctrl": 62,
        "lopt": 58, "ropt": 61, "lcmd": 55, "rcmd": 54,
        "alt": 58, "lalt": 58, "ralt": 61,
        "cmd": 55, "ctrl": 59, "shift": 56,
        
        // Virtual KeyCodes for system media keys
        "volume_increment": 1000, "vol_up": 1000,
        "volume_decrement": 1001, "vol_down": 1001,
        "display_brightness_increment": 1002, "brightness_up": 1002,
        "display_brightness_decrement": 1003, "brightness_down": 1003,
        "mute": 1007,
        "play_pause": 1016, "play": 1016,
        "next_track": 1017,
        "prev_track": 1018,
        "illumination_increment": 1021, "kbd_brightness_up": 1021,
        "illumination_decrement": 1022, "kbd_brightness_down": 1022,
        
        // Virtual KeyCodes for Mouse Buttons
        "button1": 2001, "left_click": 2001,
        "button2": 2002, "right_click": 2002,
        "button3": 2003, "middle_click": 2003
    ]

    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased().trimmingCharacters(in: .whitespaces)
        if let code = specialKeyCodes[lower] { return code }
        
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
    
    static func parseKeyString(_ input: String) -> (coreFlags: CGEventFlags, strictFlags: [String], key: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("shell:") {
            return ([], [], trimmed)
        }
        
        let rawParts = input.components(separatedBy: "+")
        let parts = rawParts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        
        guard !parts.isEmpty else { return ([], [], "") }
        
        var coreFlags: CGEventFlags = []
        var strictFlags: [String] = []
        let key = parts.last!
        
        if parts.count > 1 {
            for mod in parts.dropLast() {
                switch mod {
                case "cmd", "command": coreFlags.insert(.maskCommand)
                case "ctrl", "control": coreFlags.insert(.maskControl)
                case "opt", "alt", "option": coreFlags.insert(.maskAlternate)
                case "shift": coreFlags.insert(.maskShift)
                
                case "lcmd", "left_command": coreFlags.insert(.maskCommand); strictFlags.append("left_command")
                case "rcmd", "right_command": coreFlags.insert(.maskCommand); strictFlags.append("right_command")
                case "lctrl", "left_control": coreFlags.insert(.maskControl); strictFlags.append("left_control")
                case "rctrl", "right_control": coreFlags.insert(.maskControl); strictFlags.append("right_control")
                case "lopt", "left_option", "lalt": coreFlags.insert(.maskAlternate); strictFlags.append("left_option")
                case "ropt", "right_option", "ralt": coreFlags.insert(.maskAlternate); strictFlags.append("right_option")
                case "lshift", "left_shift": coreFlags.insert(.maskShift); strictFlags.append("left_shift")
                case "rshift", "right_shift": coreFlags.insert(.maskShift); strictFlags.append("right_shift")
                default: break
                }
            }
        }
        return (coreFlags, strictFlags, key)
    }

    static func postMediaKeyEvent(mediaKey: Int32, isDown: Bool, flags: CGEventFlags) {
        let loc = NSPoint(x: 0, y: 0)
        let data1 = (Int(mediaKey) << 16) | (isDown ? 0xA00 : 0xB00)
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
        
        if let ev = NSEvent.otherEvent(
            with: .systemDefined,
            location: loc,
            modifierFlags: nsFlags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        ), let cg = ev.cgEvent {
            cg.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            cg.post(tap: .cghidEventTap)
        }
    }
    
    static func postMouseEvent(button: Int32, isDown: Bool) {
        guard let currentEvent = CGEvent(source: nil) else { return }
        let loc = currentEvent.location
        
        let type: CGEventType
        let mouseButton: CGMouseButton
        
        switch button {
        case 1:
            type = isDown ? .leftMouseDown : .leftMouseUp
            mouseButton = .left
        case 2:
            type = isDown ? .rightMouseDown : .rightMouseUp
            mouseButton = .right
        case 3:
            type = isDown ? .otherMouseDown : .otherMouseUp
            mouseButton = .center
        default: return
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        if let mouseEvent = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: loc, mouseButton: mouseButton) {
            mouseEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
            mouseEvent.post(tap: .cghidEventTap)
        }
    }

    func start() {
        refreshCustomShortcutsCache()
        userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            refreshCustomShortcutsCache()
        }
        
        // 14 is NX_SYSDEFINED (System Defined Events like Media Keys)
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.keyUp.rawValue) | 
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << 14) 
                        
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
        activeRemaps.removeAll()
    }
}

func isExactModifierMatch(flags: CGEventFlags, required: [String]) -> Bool {
    let hasCmd = flags.contains(.maskCommand)
    let hasCtrl = flags.contains(.maskControl)
    let hasOpt = flags.contains(.maskAlternate)
    let hasShift = flags.contains(.maskShift)
    
    let reqCmd = required.contains(where: { $0.contains("command") })
    let reqCtrl = required.contains(where: { $0.contains("control") })
    let reqOpt = required.contains(where: { $0.contains("option") })
    let reqShift = required.contains(where: { $0.contains("shift") })
    
    if reqCmd != hasCmd || reqCtrl != hasCtrl || reqOpt != hasOpt || reqShift != hasShift { return false }
    
    let raw = flags.rawValue
    let leftCtrl = (raw & 0x01) != 0
    let leftShift = (raw & 0x02) != 0
    let rightShift = (raw & 0x04) != 0
    let leftCmd = (raw & 0x08) != 0
    let rightCmd = (raw & 0x10) != 0
    let leftOpt = (raw & 0x20) != 0
    let rightOpt = (raw & 0x40) != 0
    let rightCtrl = (raw & 0x2000) != 0
    
    for req in required {
        switch req {
        case "left_command": if !leftCmd { return false }
        case "right_command": if !rightCmd { return false }
        case "left_control": if !leftCtrl { return false }
        case "right_control": if !rightCtrl { return false }
        case "left_option": if !leftOpt { return false }
        case "right_option": if !rightOpt { return false }
        case "left_shift": if !leftShift { return false }
        case "right_shift": if !rightShift { return false }
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
            if !isSpecific { return false }
        }
        return type == .flagsChanged && isExactModifierMatch(flags: flags, required: [m1.replacingOccurrences(of: " ", with: "_"), m2.replacingOccurrences(of: " ", with: "_")])
    } else {
        if type != .keyDown { return false }
        guard let code = KeyboardInterceptor.getKeyCode(for: keyStr) else { return false }
        return eventKeyCode == Int64(code) && isExactModifierMatch(flags: flags, required: [mod1Str.replacingOccurrences(of: " ", with: "_"), (mod2Str ?? "none").replacingOccurrences(of: " ", with: "_")])
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

func executeCustomShortcutCycle(validBundleIDs: [String], frontApp: NSRunningApplication?) {
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

func processPCModeRules(type: CGEventType, keyCode: Int64, flags: CGEventFlags, frontAppID: String) -> Bool {
    let isFlagsChanged = (type == .flagsChanged)
    let rawKeyCode = CGKeyCode(keyCode)
    
    // 1. Un-stick Logic for KeyUp OR Modifier Release
    // This solves the bug where mapping `opt + shift` leaves mapped standard keys permanently "pressed"
    var isRelease = false
    if type == .keyUp {
        isRelease = true
    } else if isFlagsChanged {
        var isPress = false
        switch rawKeyCode {
        case 56, 60: isPress = flags.contains(.maskShift)
        case 59, 62: isPress = flags.contains(.maskControl)
        case 58, 61: isPress = flags.contains(.maskAlternate)
        case 55, 54: isPress = flags.contains(.maskCommand)
        default: isPress = true // assume press for unknown modifiers to avoid accidental un-stick fallthrough
        }
        if !isPress {
            isRelease = true
        }
    }
    
    if isRelease {
        if let mappedTo = activeRemaps[rawKeyCode] {
            activeRemaps.removeValue(forKey: rawKeyCode)
            
            if mappedTo >= 2000 {
                let btn = Int32(mappedTo - 2000)
                KeyboardInterceptor.postMouseEvent(button: btn, isDown: false)
            } else if mappedTo >= 1000 {
                let mediaKey = Int32(mappedTo - 1000)
                KeyboardInterceptor.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: flags)
            } else if mappedTo != 0 {
                let source = CGEventSource(stateID: .hidSystemState)
                if let newEvent = CGEvent(keyboardEventSource: source, virtualKey: mappedTo, keyDown: false) {
                    var finalFlags = flags
                    let navKeys: Set<CGKeyCode> = [114, 115, 119, 116, 121, 123, 124, 125, 126, 117]
                    let fnKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
                    if navKeys.contains(mappedTo) || fnKeys.contains(mappedTo) { finalFlags.insert(.maskSecondaryFn) }
                    if navKeys.contains(mappedTo) { finalFlags.insert(.maskNumericPad) }
                    
                    newEvent.flags = finalFlags
                    newEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                    newEvent.post(tap: .cghidEventTap)
                }
            }
            return true // Swallow original KeyUp / Modifier Release so OS doesn't receive partial keys
        }
        if type == .keyUp {
            return false // Was not remapped, let normal keyUp pass through
        }
        // If it's a modifier release that wasn't remapped, it just falls through to allow normal evaluation
    }

    // 2. Process Rules for KeyDown and FlagsChanged (Presses)
    let originalFlags = flags
    
    for parsedRule in cachedParsedPCRules {
        if parsedRule.rule.appFilterMode == .include && !parsedRule.rule.appBundleIDs.contains(frontAppID) { continue }
        if parsedRule.rule.appFilterMode == .exclude && parsedRule.rule.appBundleIDs.contains(frontAppID) { continue }
        
        for map in parsedRule.mappings {
            if map.fromKeyCode != rawKeyCode { continue }
            
            var cleanEventFlags = originalFlags
            if isFlagsChanged {
                switch rawKeyCode {
                case 56, 60: cleanEventFlags.remove(.maskShift)
                case 59, 62: cleanEventFlags.remove(.maskControl)
                case 58, 61: cleanEventFlags.remove(.maskAlternate)
                case 55, 54: cleanEventFlags.remove(.maskCommand)
                default: break
                }
            }
            
            let coreEventFlags = cleanEventFlags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            if !coreEventFlags.isSuperset(of: map.fromCoreFlags) { continue }
            
            var strictMatch = true
            let raw = cleanEventFlags.rawValue
            for strictMod in map.fromStrictFlags {
                switch strictMod {
                case "left_command": if (raw & 0x08) == 0 { strictMatch = false }
                case "right_command": if (raw & 0x10) == 0 { strictMatch = false }
                case "left_control": if (raw & 0x01) == 0 { strictMatch = false }
                case "right_control": if (raw & 0x2000) == 0 { strictMatch = false }
                case "left_option": if (raw & 0x20) == 0 { strictMatch = false }
                case "right_option": if (raw & 0x40) == 0 { strictMatch = false }
                case "left_shift": if (raw & 0x02) == 0 { strictMatch = false }
                case "right_shift": if (raw & 0x04) == 0 { strictMatch = false }
                default: break
                }
            }
            if !strictMatch { continue }
            
            // Match found!
            
            if map.isShell {
                var shouldExecute = false
                if !isFlagsChanged && type == .keyDown {
                    shouldExecute = true
                } else if isFlagsChanged {
                    var isPress = false
                    switch rawKeyCode {
                    case 56, 60: isPress = originalFlags.contains(.maskShift)
                    case 59, 62: isPress = originalFlags.contains(.maskControl)
                    case 58, 61: isPress = originalFlags.contains(.maskAlternate)
                    case 55, 54: isPress = originalFlags.contains(.maskCommand)
                    case 57: isPress = true
                    default: break
                    }
                    shouldExecute = isPress
                }
                
                if shouldExecute {
                    if let cmd = map.shellCommand {
                        let task = Process()
                        task.launchPath = "/bin/sh"
                        task.arguments = ["-c", cmd]
                        try? task.run()
                    }
                    activeRemaps[rawKeyCode] = 0 // Track so KeyUp/ModRelease is swallowed smoothly
                }
                return true
            }

            if map.toActions.count > 1 {
                // Macro Sequence Handling
                var shouldExecute = false
                if !isFlagsChanged && type == .keyDown {
                    shouldExecute = true
                } else if isFlagsChanged {
                    var isPress = false
                    switch rawKeyCode {
                    case 56, 60: isPress = originalFlags.contains(.maskShift)
                    case 59, 62: isPress = originalFlags.contains(.maskControl)
                    case 58, 61: isPress = originalFlags.contains(.maskAlternate)
                    case 55, 54: isPress = originalFlags.contains(.maskCommand)
                    case 57: isPress = true // CapsLock toggle triggers full press
                    default: break
                    }
                    shouldExecute = isPress
                }

                if shouldExecute {
                    for action in map.toActions {
                        var finalFlags = action.coreFlags
                        let navKeys: Set<CGKeyCode> = [114, 115, 119, 116, 121, 123, 124, 125, 126, 117]
                        let fnKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
                        if navKeys.contains(action.keyCode) || fnKeys.contains(action.keyCode) { finalFlags.insert(.maskSecondaryFn) }
                        if navKeys.contains(action.keyCode) { finalFlags.insert(.maskNumericPad) }

                        let source = CGEventSource(stateID: .hidSystemState)
                        if let down = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) {
                            down.flags = finalFlags
                            down.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                            down.post(tap: .cghidEventTap)
                        }
                        usleep(1000)
                        if let up = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: false) {
                            up.flags = finalFlags
                            up.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                            up.post(tap: .cghidEventTap)
                        }
                        usleep(1000)
                    }
                    activeRemaps[rawKeyCode] = 0 // Swallow subsequent KeyUp/ModRelease of original trigger
                }
                return true
            }

            // Standard Single Key Mapping
            let action = map.toActions[0]
            
            let extraFlags = coreEventFlags.subtracting(map.fromCoreFlags)
            var newCoreFlags = action.coreFlags
            newCoreFlags.formUnion(extraFlags)
            
            var finalFlags = originalFlags
            finalFlags.remove([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskNumericPad])
            finalFlags.formUnion(newCoreFlags)
            
            if action.keyCode >= 2000 {
                // Map to Mouse Button
                let btn = Int32(action.keyCode - 2000)
                if isFlagsChanged {
                    var isPress = false
                    switch rawKeyCode {
                    case 56, 60: isPress = originalFlags.contains(.maskShift)
                    case 59, 62: isPress = originalFlags.contains(.maskControl)
                    case 58, 61: isPress = originalFlags.contains(.maskAlternate)
                    case 55, 54: isPress = originalFlags.contains(.maskCommand)
                    case 57: isPress = true // CapsLock toggle triggers full press
                    default: break
                    }
                    if isPress {
                        KeyboardInterceptor.postMouseEvent(button: btn, isDown: true)
                        KeyboardInterceptor.postMouseEvent(button: btn, isDown: false)
                    }
                    return true
                } else {
                    activeRemaps[rawKeyCode] = action.keyCode
                    KeyboardInterceptor.postMouseEvent(button: btn, isDown: true)
                    return true
                }
            } else if action.keyCode >= 1000 {
                // Map to a Media Key (Volume/Brightness)
                let mediaKey = Int32(action.keyCode - 1000)
                if isFlagsChanged {
                    var isPress = false
                    switch rawKeyCode {
                    case 56, 60: isPress = originalFlags.contains(.maskShift)
                    case 59, 62: isPress = originalFlags.contains(.maskControl)
                    case 58, 61: isPress = originalFlags.contains(.maskAlternate)
                    case 55, 54: isPress = originalFlags.contains(.maskCommand)
                    case 57: isPress = true // CapsLock
                    default: break
                    }
                    if isPress {
                        KeyboardInterceptor.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                        KeyboardInterceptor.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: finalFlags)
                    }
                    return true
                } else {
                    activeRemaps[rawKeyCode] = action.keyCode
                    KeyboardInterceptor.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                    return true
                }
            } else {
                // Map to Standard Key
                let navKeys: Set<CGKeyCode> = [114, 115, 119, 116, 121, 123, 124, 125, 126, 117]
                let fnKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
                
                if navKeys.contains(action.keyCode) || fnKeys.contains(action.keyCode) {
                    finalFlags.insert(.maskSecondaryFn)
                }
                if navKeys.contains(action.keyCode) {
                    finalFlags.insert(.maskNumericPad)
                }
                
                if isFlagsChanged {
                    var isPress = false
                    var isCapsLock = false
                    switch rawKeyCode {
                    case 56, 60: isPress = originalFlags.contains(.maskShift)
                    case 59, 62: isPress = originalFlags.contains(.maskControl)
                    case 58, 61: isPress = originalFlags.contains(.maskAlternate)
                    case 55, 54: isPress = originalFlags.contains(.maskCommand)
                    case 57: 
                        isPress = true // CapsLock
                        isCapsLock = true
                    default: break
                    }
                    
                    if isPress {
                        activeRemaps[rawKeyCode] = action.keyCode // Ensures Un-stick logic catches release
                        
                        let source = CGEventSource(stateID: .hidSystemState)
                        if let down = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) {
                            down.flags = finalFlags
                            down.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                            down.post(tap: .cghidEventTap)
                        }
                        // CapsLock doesn't fire naturally on release
                        if isCapsLock {
                            activeRemaps.removeValue(forKey: rawKeyCode)
                            if let up = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: false) {
                                up.flags = finalFlags
                                up.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                                up.post(tap: .cghidEventTap)
                            }
                        }
                    }
                    return true
                } else {
                    activeRemaps[rawKeyCode] = action.keyCode
                    let source = CGEventSource(stateID: .hidSystemState)
                    if let newEvent = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) {
                        newEvent.flags = finalFlags
                        newEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        newEvent.post(tap: .cghidEventTap)
                    }
                    return true
                }
            }
        }
    }
    return false
}

func keyboardEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = globalKeyboardEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    
    // Safety Net: Prevent infinite loops from our own synthesized CGEvents
    if event.getIntegerValueField(.eventSourceUserData) == magicEventSourceUserData {
        return Unmanaged.passUnretained(event)
    }
    
    // --- SPECIAL CAPS LOCK -> MOUSE BUTTON HYBRID HOOK ---
    // If hidutil mapped Caps Lock to F20-F18 to simulate mouse clicks, catch it here.
    if UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled) {
        let capsTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCapsLock) ?? "capslock"
        if capsTarget.hasPrefix("button") {
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            
            // F20 = 90, F19 = 80, F18 = 79
            if (capsTarget == "button1" && keyCode == 90) ||
               (capsTarget == "button2" && keyCode == 80) ||
               (capsTarget == "button3" && keyCode == 79) {
                
                let btnStr = capsTarget.replacingOccurrences(of: "button", with: "")
                let btn = Int32(btnStr) ?? 1
                
                if type == .keyDown || type == .keyUp {
                    KeyboardInterceptor.postMouseEvent(button: btn, isDown: type == .keyDown)
                    return nil // Swallow event
                }
            }
        }
    }
    
    // Evaluate possible System Defined Events (Media Keys translated to F-keys)
    var effectiveType = type
    var effectiveKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
    
    if type.rawValue == 14 { // NX_SYSDEFINED
        if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
            let data1 = nsEvent.data1
            let mediaKeyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = Int32(data1 & 0x0000FFFF)
            let isKeyDown = (((keyFlags & 0xFF00) >> 8) == 0xA)
            
            if let fKeyCode = KeyboardInterceptor.mediaKeyToFKey[mediaKeyCode] {
                effectiveType = isKeyDown ? .keyDown : .keyUp
                effectiveKeyCode = Int64(fKeyCode)
            } else {
                return Unmanaged.passUnretained(event)
            }
        } else {
            return Unmanaged.passUnretained(event)
        }
    }
    
    let isKeyDownOrUp = effectiveType == .keyDown || effectiveType == .keyUp || effectiveType == .flagsChanged
    let flags = event.flags
    
    let frontApp = getRealFrontmostApp()
    
    // Execute PC Mode Mapping (First Priority)
    if isKeyDownOrUp {
        let frontAppID = frontApp?.bundleIdentifier ?? ""
        let wasSwallowed = processPCModeRules(type: effectiveType, keyCode: effectiveKeyCode, flags: flags, frontAppID: frontAppID)
        if wasSwallowed {
            return nil
        }
    }
    
    // Only evaluate Global Shortcuts on purely unswallowed keyDown/flagsChanged events
    guard effectiveType == .keyDown || effectiveType == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }
    
    let defaults = UserDefaults.standard
    
    let isNextMatch = defaults.bool(forKey: AppConfig.Keys.enableNextGroupShortcut) &&
        isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: cachedNextGroupTriggers)
                              
    let isPrevMatch = defaults.bool(forKey: AppConfig.Keys.enablePrevGroupShortcut) &&
        isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: cachedPrevGroupTriggers)

    let isToggleGroupMatch = defaults.bool(forKey: AppConfig.Keys.enableToggleGroupShortcut) &&
        isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: cachedToggleGroupTriggers)
    
    var matchedCustomShortcut: CustomAppShortcut?
    for shortcut in cachedCustomShortcuts {
        if !shortcut.isEnabled { continue }
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        if validBundleIDs.isEmpty { continue }
        
        if isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: shortcut.triggers) {
            matchedCustomShortcut = shortcut
            break
        }
    }
    
    let isMainMatch = isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isToggleMatch = defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) &&
                        isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isClipMatch = defaults.bool(forKey: AppConfig.Keys.enableClipboardManager) &&
                      isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command",
                                            mod2Str: nil)
    
    if !isNextMatch && !isPrevMatch && !isToggleGroupMatch && matchedCustomShortcut == nil && !isMainMatch && !isToggleMatch && !isClipMatch {
        return Unmanaged.passUnretained(event)
    }
    
    if isNextMatch || isPrevMatch || isToggleGroupMatch {
        let validShortcuts = cachedCustomShortcuts.filter { $0.isEnabled && $0.bundleIDs.contains(where: { !$0.isEmpty }) }
        if !validShortcuts.isEmpty {
            var target: CustomAppShortcut?
            var currentIdx = -1
            
            if let frontID = frontApp?.bundleIdentifier {
                currentIdx = validShortcuts.firstIndex(where: { $0.bundleIDs.contains(frontID) }) ?? -1
            }
            
            if currentIdx == -1 {
                currentIdx = validShortcuts.firstIndex(where: { $0.id == lastUsedShortcutID }) ?? -1
            }
            
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
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    if let shortcut = matchedCustomShortcut {
        lastUsedShortcutID = shortcut.id
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        DispatchQueue.main.async {
            executeCustomShortcutCycle(validBundleIDs: validBundleIDs, frontApp: frontApp)
        }
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
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