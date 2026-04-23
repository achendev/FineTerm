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
    // CRITICAL: Wrapping high-frequency event callbacks in autoreleasepool instantly
    // frees temporary CFDictionary objects created during WindowServer queries, 
    // preventing the heap from ballooning to 150MB+ during rapid typing.
    return autoreleasepool {
        if type == .tapDisabledByTimeout {
            if let tap = globalKeyboardEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        } else if type == .tapDisabledByUserInput {
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
        
        if effectiveType == .keyDown && (effectiveKeyCode == 36 || effectiveKeyCode == 76) {
            SecureInputMonitor.shared.triggerActiveCheck()
        }
        
        let isKeyDownOrUp = effectiveType == .keyDown || effectiveType == .keyUp || effectiveType == .flagsChanged
        let flags = event.flags
        
        let cache = KeyboardCache.shared
        let engine = cache.pcModeEngine
        
        var lazyFrontAppID: String? = nil
        let getFrontAppID: () -> String = {
            if let id = lazyFrontAppID { return id }
            let app = WindowCycleService.getRealFrontmostApp()
            let id = app?.bundleIdentifier ?? ""
            lazyFrontAppID = id
            return id
        }
        
        if isKeyDownOrUp {
            let wasSwallowed = PCModeProcessor.shared.process(type: effectiveType, keyCode: effectiveKeyCode, flags: flags, event: event, getFrontAppID: getFrontAppID)
            if wasSwallowed { return nil }
        }
        
        guard effectiveType == .keyDown || effectiveType == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }
        
        if engine > 0 {
            return Unmanaged.passUnretained(event)
        }
        
        let isNextMatch = cache.enableNextGroupShortcut && cache.nextGroupTriggers.contains { $0.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) }
        let isPrevMatch = cache.enablePrevGroupShortcut && cache.prevGroupTriggers.contains { $0.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) }
        let isToggleGroupMatch = cache.enableToggleGroupShortcut && cache.toggleGroupTriggers.contains { $0.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) }
        
        var matchedCustomShortcut: ParsedCustomAppShortcut?
        for shortcut in cache.customShortcuts {
            if shortcut.triggers.contains(where: { $0.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) }) {
                matchedCustomShortcut = shortcut
                break
            }
        }
        
        let isMainMatch = cache.mainShortcut?.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) ?? false
        let isToggleMatch = cache.enableTerminalToggleShortcut && (cache.terminalToggleShortcut?.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) ?? false)
        let isClipMatch = cache.enableClipboardManager && (cache.clipboardShortcut?.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) ?? false)
        let isLibraryAddMatch = cache.enableLibraryManager && (cache.libraryAddShortcut?.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) ?? false)
        let isLibraryOpenMatch = cache.enableLibraryManager && (cache.libraryOpenShortcut?.matches(type: effectiveType, eventKeyCode: effectiveKeyCode, flags: flags) ?? false)
        
        if !isNextMatch && !isPrevMatch && !isToggleGroupMatch && matchedCustomShortcut == nil && !isMainMatch && !isToggleMatch && !isClipMatch && !isLibraryAddMatch && !isLibraryOpenMatch {
            return Unmanaged.passUnretained(event)
        }
        
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
}