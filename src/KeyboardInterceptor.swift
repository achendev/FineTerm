import Cocoa
import ApplicationServices

let magicEventSourceUserData: Int64 = 0x46696E65 // "Fine"

private var globalKeyboardEventTap: CFMachPort?

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    func start() {
        KeyboardCache.shared.start()
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) | 
                        (1 << CGEventType.keyUp.rawValue) | 
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << 14) 
                        
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
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
        KeyboardCache.shared.stop()
        PCModeProcessor.shared.reset()
        ScrollModeManager.shared.isActive = false
        globalKeyboardEventTap = nil
        eventTap = nil
        runLoopSource = nil
        WindowCycleService.lastUsedOriginBundleID = nil
        WindowCycleService.lastUsedShortcutID = nil
    }
}

func keyboardEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = globalKeyboardEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    
    if event.getIntegerValueField(.eventSourceUserData) == magicEventSourceUserData {
        return Unmanaged.passUnretained(event)
    }
    
    var effectiveType = type
    var effectiveKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
    
    if type.rawValue == 14 {
        if let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 {
            let data1 = nsEvent.data1
            let mediaKeyCode = Int32((data1 & 0xFFFF0000) >> 16)
            let keyFlags = Int32(data1 & 0x0000FFFF)
            let isKeyDown = (((keyFlags & 0xFF00) >> 8) == 0xA)
            
            if let fKeyCode = KeyboardParser.mediaKeyToFKey[mediaKeyCode] {
                effectiveType = isKeyDown ? .keyDown : .keyUp
                effectiveKeyCode = Int64(fKeyCode)
            } else {
                return Unmanaged.passUnretained(event)
            }
        } else {
            return Unmanaged.passUnretained(event)
        }
    }
    
    if effectiveType == .keyDown && KeyboardEventInjector.isTypingActive {
        KeyboardEventInjector.cancelTyping()
        return nil 
    }
    
    // Trigger an immediate secure input check on Enter / Numpad Enter (to catch submitting forms)
    if effectiveType == .keyDown && (effectiveKeyCode == 36 || effectiveKeyCode == 76) {
        SecureInputMonitor.shared.triggerActiveCheck()
    }
    
    let isKeyDownOrUp = effectiveType == .keyDown || effectiveType == .keyUp || effectiveType == .flagsChanged
    let flags = event.flags
    let frontApp = WindowCycleService.getRealFrontmostApp()
    
    let engine = UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine)
    
    if isKeyDownOrUp {
        let frontAppID = frontApp?.bundleIdentifier ?? ""
        let wasSwallowed = PCModeProcessor.shared.process(type: effectiveType, keyCode: effectiveKeyCode, flags: flags, event: event, frontAppID: frontAppID)
        if wasSwallowed {
            return nil
        }
    }
    
    guard effectiveType == .keyDown || effectiveType == .flagsChanged else {
        return Unmanaged.passUnretained(event)
    }
    
    // If Karabiner is active (Full or Hybrid), it ALWAYS handles global shortcuts unconditionally via karabiner.json
    if engine > 0 {
        return Unmanaged.passUnretained(event)
    }
    
    let defaults = UserDefaults.standard
    
    let isNextMatch = defaults.bool(forKey: AppConfig.Keys.enableNextGroupShortcut) &&
        KeyboardMatcher.isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: KeyboardCache.shared.nextGroupTriggers)
                              
    let isPrevMatch = defaults.bool(forKey: AppConfig.Keys.enablePrevGroupShortcut) &&
        KeyboardMatcher.isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: KeyboardCache.shared.prevGroupTriggers)

    let isToggleGroupMatch = defaults.bool(forKey: AppConfig.Keys.enableToggleGroupShortcut) &&
        KeyboardMatcher.isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: KeyboardCache.shared.toggleGroupTriggers)
    
    var matchedCustomShortcut: CustomAppShortcut?
    for shortcut in KeyboardCache.shared.customShortcuts {
        if !shortcut.isEnabled { continue }
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        if validBundleIDs.isEmpty { continue }
        if KeyboardMatcher.isAnyTriggerMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags, triggers: shortcut.triggers) {
            matchedCustomShortcut = shortcut
            break
        }
    }
    
    let isMainMatch = KeyboardMatcher.isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isToggleMatch = defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) &&
                        KeyboardMatcher.isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command",
                                            mod2Str: nil)
                                            
    let isClipMatch = defaults.bool(forKey: AppConfig.Keys.enableClipboardManager) &&
                      KeyboardMatcher.isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command",
                                            mod2Str: nil)

    let isLibraryAddMatch = defaults.bool(forKey: AppConfig.Keys.enableLibraryManager) &&
                      KeyboardMatcher.isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.libraryAddShortcutKey) ?? "n",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.libraryAddShortcutModifier) ?? "option",
                                            mod2Str: nil)
                                            
    let isLibraryOpenMatch = defaults.bool(forKey: AppConfig.Keys.enableLibraryManager) &&
                      KeyboardMatcher.isGlobalShortcutMatch(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags,
                                            keyStr: defaults.string(forKey: AppConfig.Keys.libraryOpenShortcutKey) ?? "m",
                                            mod1Str: defaults.string(forKey: AppConfig.Keys.libraryOpenShortcutModifier) ?? "option",
                                            mod2Str: nil)
    
    if !isNextMatch && !isPrevMatch && !isToggleGroupMatch && matchedCustomShortcut == nil && !isMainMatch && !isToggleMatch && !isClipMatch && !isLibraryAddMatch && !isLibraryOpenMatch {
        return Unmanaged.passUnretained(event)
    }
    
    // Trigger an immediate secure input check on any shortcut execution (to catch switching into password fields)
    if isNextMatch || isPrevMatch || isToggleGroupMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { WindowCycleService.executeCycle(isNext: isNextMatch, isPrev: isPrevMatch, isToggle: isToggleGroupMatch) }
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    if let shortcut = matchedCustomShortcut {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { WindowCycleService.executeCustomShortcut(by: shortcut.id) }
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    if isLibraryAddMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.showLibraryAddWindow() } }
        return nil
    }

    if isLibraryOpenMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.toggleLibraryWindow() } }
        return nil
    }
    
    if isMainMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { WindowCycleService.handleMainToggle() }
        return nil
    }
    
    if isToggleMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { WindowCycleService.handleTerminalToggle() }
        return nil
    }
    
    if isClipMatch {
        SecureInputMonitor.shared.triggerActiveCheck()
        DispatchQueue.main.async { if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.toggleClipboardWindow() } }
        return nil
    }
    
    return Unmanaged.passUnretained(event)
}