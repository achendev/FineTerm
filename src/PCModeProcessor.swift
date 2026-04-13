import Cocoa
import ApplicationServices

class PCModeProcessor {
    static let shared = PCModeProcessor()
    
    // CRITICAL FIX: We now store the exact flags used during the initial key press so we can restore them on release
    var activeRemaps: [CGKeyCode: (keyCode: CGKeyCode, flags: CGEventFlags)] = [:]
    
    func reset() {
        activeRemaps.removeAll()
    }
    
    func process(type: CGEventType, keyCode: Int64, flags: CGEventFlags, event: CGEvent, frontAppID: String) -> Bool {
        let isFlagsChanged = (type == .flagsChanged)
        let rawKeyCode = CGKeyCode(keyCode)
        
        // 1. Un-stick Logic for KeyUp OR Modifier Release
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
            if let mapping = activeRemaps[rawKeyCode] {
                activeRemaps.removeValue(forKey: rawKeyCode)
                let mappedTo = mapping.keyCode
                let mappedFlags = mapping.flags
                
                if mappedTo >= 2000 {
                    let btn = Int32(mappedTo - 2000)
                    KeyboardEventInjector.postMouseEvent(button: btn, isDown: false)
                } else if mappedTo >= 1000 {
                    let mediaKey = Int32(mappedTo - 1000)
                    KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: mappedFlags)
                } else if mappedTo != 0 {
                    let source = CGEventSource(stateID: .hidSystemState)
                    if let newEvent = CGEvent(keyboardEventSource: source, virtualKey: mappedTo, keyDown: false) {
                        var finalFlags = flags
                        
                        // RESTORE the modifiers that were present during the keyDown event
                        finalFlags.formUnion(mappedFlags)
                        
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
        }

        // 2. Process Rules for KeyDown and FlagsChanged (Presses)
        let originalFlags = flags
        
        for parsedRule in KeyboardCache.shared.pcRules {
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
                        activeRemaps[rawKeyCode] = (keyCode: 0, flags: []) // Track so KeyUp/ModRelease is swallowed smoothly
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
                        activeRemaps[rawKeyCode] = (keyCode: 0, flags: []) // Swallow subsequent KeyUp/ModRelease of original trigger
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
                            KeyboardEventInjector.postMouseEvent(button: btn, isDown: true)
                            KeyboardEventInjector.postMouseEvent(button: btn, isDown: false)
                        }
                        return true
                    } else {
                        activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags)
                        
                        // Filter keyboard autorepeats for mouse buttons
                        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                        if !isRepeat {
                            KeyboardEventInjector.postMouseEvent(button: btn, isDown: true)
                        }
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
                            KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                            KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: finalFlags)
                        }
                        return true
                    } else {
                        activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags)
                        KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
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
                            activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags) // Ensures Un-stick logic catches release
                            
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
                        activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags)
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
}