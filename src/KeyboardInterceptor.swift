import Cocoa
import ApplicationServices

private var globalKeyboardEventTap: CFMachPort?

// State for the Origin Loop (Origin -> FineTerm -> Terminal -> Origin)
private var savedOriginBundleID: String?

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased()
        switch lower {
            case "a": return 0
            case "s": return 1
            case "d": return 2
            case "f": return 3
            case "h": return 4
            case "g": return 5
            case "z": return 6
            case "x": return 7
            case "c": return 8
            case "v": return 9
            case "b": return 11
            case "q": return 12
            case "w": return 13
            case "e": return 14
            case "r": return 15
            case "y": return 16
            case "t": return 17
            case "1": return 18
            case "2": return 19
            case "3": return 20
            case "4": return 21
            case "6": return 22
            case "5": return 23
            case "=": return 24
            case "9": return 25
            case "7": return 26
            case "-": return 27
            case "8": return 28
            case "0": return 29
            case "]": return 30
            case "o": return 31
            case "u": return 32
            case "[": return 33
            case "i": return 34
            case "p": return 35
            case "l": return 37
            case "j": return 38
            case "'": return 39
            case "k": return 40
            case ";": return 41
            case "\\": return 42
            case ",": return 43
            case "/": return 44
            case "n": return 45
            case "m": return 46
            case ".": return 47
            default: return nil
        }
    }

    func start() {
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
        globalKeyboardEventTap = nil
        eventTap = nil
        runLoopSource = nil
        savedOriginBundleID = nil
    }
}

func isModifierMatch(flags: CGEventFlags, targetStr: String) -> Bool {
    switch targetStr {
        case "command": 
            return flags.contains(.maskCommand) && !flags.contains(.maskControl) && !flags.contains(.maskAlternate)
        case "control": 
            return flags.contains(.maskControl) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
        case "option":  
            return flags.contains(.maskAlternate) && !flags.contains(.maskCommand) && !flags.contains(.maskControl)
        default: 
            return false
    }
}

// Helpers for Activation
func activateApp(bundleID: String) {
    let workspace = NSWorkspace.shared
    
    // Attempt to find the URL for the app
    guard let url = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
        print("DEBUG: Could not find URL for bundle ID: \(bundleID)")
        return
    }
    
    // Robust Activation using OpenConfiguration (Equivalent to Dock click)
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    
    workspace.openApplication(at: url, configuration: config) { app, error in
        if let error = error {
            print("DEBUG: Failed to activate \(bundleID): \(error)")
        } else {
            print("DEBUG: Successfully requested activation for \(bundleID)")
        }
    }
}

func activateFineTerm() {
    DispatchQueue.main.async {
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let window = appDelegate.window else { return }

        // 1. Visual Prep: Unhide and Deminiaturize
        NSApp.unhide(nil)
        if window.isMiniaturized { window.deminiaturize(nil) }
        
        // 2. Logic: Snap
        if UserDefaults.standard.bool(forKey: AppConfig.Keys.snapToTerminal) {
            appDelegate.snapToTerminal()
        }

        // 3. Window System: Order Front
        // "orderFrontRegardless" allows the window to move to the active space or appear above others
        // crucial when coming from another Space.
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        
        // 4. Application: Activate
        // We use NSApp.activate because it works within the app context.
        // Doing this AFTER orderFront tells the system "This specific window is the reason we are activating".
        NSApp.activate(ignoringOtherApps: true)
        
        // 5. CRITICAL FIX for Space Switching Lag:
        // When switching Spaces (e.g. from Chrome on Space 2 to FineTerm on Space 1), 
        // macOS initially focuses the *last active app* on Space 1 (Terminal) before processing 
        // our activation request. This creates a race condition where FineTerm appears but 
        // Terminal keeps focus (gray search bar).
        // We must re-assert focus after a tiny delay to ensure we win the tug-of-war.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        
        // 6. Secondary Safety Net
        // If the space switch animation is slow (e.g. ProMotion disabled or old Mac), retry slightly later.
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
    
    // 1. Absolute Truth: Are WE active?
    if NSRunningApplication.current.isActive {
        return NSRunningApplication.current
    }
    
    // 2. Check for Stale Workspace Data
    // If Workspace says WE are active, but step 1 said NO, then Workspace is lagging.
    // We must ignore Workspace and check Window List Z-Order.
    var trustWorkspace = true
    if let id = workspaceApp?.bundleIdentifier {
        if id == myBundleID {
            trustWorkspace = false
        }
    }
    
    if trustWorkspace {
        return workspaceApp
    }
    
    // 3. Truth from Window Server (Z-Order)
    // Find the first window that isn't ours and belongs to a regular app
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return workspaceApp
    }
    
    for info in list {
        // Filter for normal window layer (0)
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
        
        let pid = pidNumber.int32Value
        if let app = NSRunningApplication(processIdentifier: pid) {
            // Ignore ourselves (we might be fading out)
            if app.bundleIdentifier == myBundleID { continue }
            
            // Found top-most non-FineTerm app (Terminal, Chrome, etc)
            if app.activationPolicy == .regular {
                return app
            }
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
    
    let defaults = UserDefaults.standard
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let debug = defaults.bool(forKey: AppConfig.Keys.debugMode)
    
    // CHECK 1: Main Shortcut (The Activation Loop)
    let mainKey = defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n"
    let mainMod = defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"
    let mainAnywhere = defaults.bool(forKey: AppConfig.Keys.globalShortcutAnywhere)
    let secondActivation = defaults.bool(forKey: AppConfig.Keys.secondActivationToTerminal)
    let thirdActivation = defaults.bool(forKey: AppConfig.Keys.thirdActivationToOrigin)
    
    // Get Robust Front App
    let frontApp = getRealFrontmostApp()
    let target = defaults.string(forKey: AppConfig.Keys.targetTerminalBundleID) ?? "com.apple.Terminal"
    let isTerminalFront = frontApp?.bundleIdentifier == target
    let isFineTermFront = NSRunningApplication.current.isActive // Absolute local truth
    
    if let mainCode = KeyboardInterceptor.getKeyCode(for: mainKey),
       keyCode == Int64(mainCode),
       isModifierMatch(flags: flags, targetStr: mainMod) {
        
        if !mainAnywhere && !isTerminalFront && !isFineTermFront {
             return Unmanaged.passUnretained(event)
        }
        
        if debug { 
            print("DEBUG: Shortcut Pressed.")
            print("   Visual Front: \(frontApp?.localizedName ?? "Unknown")")
            print("   isTerminalFront: \(isTerminalFront)")
            print("   isFineTermFront: \(isFineTermFront)")
            print("   Saved Origin: \(savedOriginBundleID ?? "None")")
        }
        
        // --- LOOP LOGIC ---
        
        // 1. FineTerm -> Terminal
        if isFineTermFront {
            if secondActivation {
                if debug { print("DEBUG: Step 2: FineTerm -> Terminal") }
                activateTerminal()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        
        // 2. Terminal -> Origin (or FineTerm)
        if isTerminalFront {
            if secondActivation && thirdActivation,
               let originID = savedOriginBundleID,
               originID != target,
               originID != Bundle.main.bundleIdentifier {
                
                if debug { print("DEBUG: Step 3: Terminal -> Origin (\(originID))") }
                DispatchQueue.main.async {
                    activateApp(bundleID: originID)
                }
                return nil
            }
            
            // Fallback: Terminal -> FineTerm
            if debug { print("DEBUG: Step 3 (Fallback): Terminal -> FineTerm") }
            activateFineTerm()
            return nil
        }
        
        // 3. Origin -> FineTerm
        if !isFineTermFront && !isTerminalFront {
            if let app = frontApp, let bundleID = app.bundleIdentifier {
                // Prevent overwriting origin with FineTerm or Terminal
                if bundleID != Bundle.main.bundleIdentifier && bundleID != target {
                    savedOriginBundleID = bundleID
                    if debug { print("DEBUG: Step 1: Origin (\(app.localizedName ?? bundleID)) -> FineTerm [Saved]") }
                } else {
                    if debug { print("DEBUG: Step 1: Origin ignored (\(bundleID)) -> FineTerm") }
                }
            }
            
            activateFineTerm()
            return nil
        }
    }
    
    // CHECK 2: Terminal Toggle Shortcut
    if defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) {
        let toggleKey = defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h"
        let toggleMod = defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command"
        
        if let toggleCode = KeyboardInterceptor.getKeyCode(for: toggleKey),
           keyCode == Int64(toggleCode),
           isModifierMatch(flags: flags, targetStr: toggleMod) {
            
            if isTerminalFront {
                // Return to the origin app
                if let originID = savedOriginBundleID,
                   originID != target,
                   originID != Bundle.main.bundleIdentifier {
                    if debug { print("DEBUG: Terminal Toggle: Terminal -> Origin (\(originID))") }
                    DispatchQueue.main.async {
                        activateApp(bundleID: originID)
                    }
                    return nil
                } else {
                    // Fallback to not intercepting if no origin is known (allows native Cmd+H hide)
                    if debug { print("DEBUG: Terminal Toggle: No origin saved, passing event.") }
                    return Unmanaged.passUnretained(event)
                }
            } else {
                // Save current app as origin and jump to Terminal
                if !isFineTermFront {
                    if let app = frontApp, let bundleID = app.bundleIdentifier,
                       bundleID != target,
                       bundleID != Bundle.main.bundleIdentifier {
                        savedOriginBundleID = bundleID
                        if debug { print("DEBUG: Terminal Toggle: Origin (\(bundleID)) -> Terminal") }
                    }
                }
                activateTerminal()
                return nil
            }
        }
    }
    
    // CHECK 3: Clipboard Shortcut
    if defaults.bool(forKey: AppConfig.Keys.enableClipboardManager) {
        let clipKey = defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u"
        let clipMod = defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command"
        
        if let clipCode = KeyboardInterceptor.getKeyCode(for: clipKey),
           keyCode == Int64(clipCode),
           isModifierMatch(flags: flags, targetStr: clipMod) {
            
            DispatchQueue.main.async {
                if let appDelegate = NSApp.delegate as? AppDelegate {
                    appDelegate.toggleClipboardWindow()
                }
            }
            return nil
        }
    }
    
    return Unmanaged.passUnretained(event)
}