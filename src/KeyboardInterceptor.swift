import Cocoa
import ApplicationServices

let magicEventSourceUserData: Int64 = 0x46696E65 // "Fine"

private var globalKeyboardEventTap: CFMachPort?
private var savedOriginBundleID: String?
private var lastUsedShortcutID: UUID?

class KeyboardInterceptor {
    var eventTap: CFMachPort?
    var runLoopSource: CFRunLoopSource?

    func start() {
        KeyboardCache.shared.start()
        
        // 14 is NX_SYSDEFINED (System Defined Events like Media Keys)
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
        globalKeyboardEventTap = nil
        eventTap = nil
        runLoopSource = nil
        savedOriginBundleID = nil
        lastUsedShortcutID = nil
    }
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
    
    // Evaluate possible System Defined Events (Media Keys translated to F-keys)
    var effectiveType = type
    var effectiveKeyCode = event.getIntegerValueField(.keyboardEventKeycode)
    
    if type.rawValue == 14 { // NX_SYSDEFINED
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
    
    let isKeyDownOrUp = effectiveType == .keyDown || effectiveType == .keyUp || effectiveType == .flagsChanged
    let flags = event.flags
    
    let frontApp = WindowCycleService.getRealFrontmostApp()
    
    // Execute PC Mode Mapping (First Priority)
    if isKeyDownOrUp {
        let frontAppID = frontApp?.bundleIdentifier ?? ""
        let wasSwallowed = PCModeProcessor.shared.process(type: effectiveType, keyCode: effectiveKeyCode, flags: flags, event: event, frontAppID: frontAppID)
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
    
    if isNextMatch || isPrevMatch || isToggleGroupMatch {
        let validShortcuts = WindowCycleService.getActivatableShortcuts()
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
                let baseIdx = currentIdx == -1 ? -1 : currentIdx
                let nextIdx = (baseIdx + 1) % validShortcuts.count
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
                DispatchQueue.main.async { WindowCycleService.executeCustomShortcutCycle(validBundleIDs: t.bundleIDs.filter({!$0.isEmpty}), frontApp: frontApp) }
            }
        }
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    if let shortcut = matchedCustomShortcut {
        lastUsedShortcutID = shortcut.id
        let validBundleIDs = shortcut.bundleIDs.filter { !$0.isEmpty }
        DispatchQueue.main.async {
            WindowCycleService.executeCustomShortcutCycle(validBundleIDs: validBundleIDs, frontApp: frontApp)
        }
        return effectiveType == .keyDown ? nil : Unmanaged.passUnretained(event)
    }
    
    if isLibraryAddMatch {
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.showLibraryAddWindow() }
        }
        return nil
    }

    if isLibraryOpenMatch {
        DispatchQueue.main.async {
            if let appDelegate = NSApp.delegate as? AppDelegate { appDelegate.toggleLibraryWindow() }
        }
        return nil
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
            if secondActivation { WindowCycleService.activateTerminal(); return nil }
            return Unmanaged.passUnretained(event)
        }
        
        if isTerminalFront {
            if secondActivation && thirdActivation, let originID = savedOriginBundleID, originID != target, originID != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async { WindowCycleService.activateApp(bundleID: originID) }
                return nil
            }
            WindowCycleService.activateFineTerm()
            return nil
        }
        
        if !isFineTermFront && !isTerminalFront {
            if let app = frontApp, let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier, bundleID != target {
                savedOriginBundleID = bundleID
            }
            WindowCycleService.activateFineTerm()
            return nil
        }
    }
    
    if isToggleMatch {
        if isTerminalFront {
            if let originID = savedOriginBundleID, originID != target, originID != Bundle.main.bundleIdentifier {
                DispatchQueue.main.async { WindowCycleService.activateApp(bundleID: originID) }
                return nil
            }
            return Unmanaged.passUnretained(event)
        } else {
            if !isFineTermFront, let app = frontApp, let bundleID = app.bundleIdentifier, bundleID != target, bundleID != Bundle.main.bundleIdentifier {
                savedOriginBundleID = bundleID
            }
            WindowCycleService.activateTerminal()
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