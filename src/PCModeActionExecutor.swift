import Cocoa
import ApplicationServices

struct PCModeActionExecutor {
    static func execute(map: ParsedKeyMap, rawKeyCode: CGKeyCode, originalFlags: CGEventFlags, isFlagsChanged: Bool, type: CGEventType, event: CGEvent) -> Bool {
        let isPress = isPressEvent(rawKeyCode: rawKeyCode, originalFlags: originalFlags, isFlagsChanged: isFlagsChanged, type: type)
        
        if map.isShell {
            if isPress {
                if let cmd = map.shellCommand {
                    let task = Process()
                    task.launchPath = "/bin/sh"
                    task.arguments = ["-c", cmd]
                    try? task.run()
                }
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: 0, flags: [])
            }
            return true
        }
        
        if map.isFunc {
            if isPress {
                if let cmd = map.funcCommand { executeFuncCommand(cmd) }
                
                // If it is a holdable function like scroll_mode, record it with a magic key code
                if map.funcCommand == "scroll_mode" {
                    ScrollModeManager.shared.isActive = true
                    PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: 3000, flags: [])
                } else {
                    PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: 0, flags: [])
                }
            }
            return true
        }
        
        if map.isType {
            if isPress {
                if let text = map.typeText {
                    KeyboardEventInjector.typeText(text, delayMs: 10)
                }
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: 0, flags: [])
            }
            return true
        }
        
        if map.toActions.count > 1 {
            if isPress {
                executeMacro(actions: map.toActions)
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: 0, flags: [])
            }
            return true
        }
        
        let action = map.toActions[0]
        
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
        let extraFlags = coreEventFlags.subtracting(map.fromCoreFlags)
        var newCoreFlags = action.coreFlags
        newCoreFlags.formUnion(extraFlags)
        
        var finalFlags = originalFlags
        finalFlags.remove([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn, .maskNumericPad])
        finalFlags.formUnion(newCoreFlags)
        
        return executeStandardAction(action: action, rawKeyCode: rawKeyCode, finalFlags: finalFlags, isFlagsChanged: isFlagsChanged, isPress: isPress, event: event)
    }
    
    private static func isPressEvent(rawKeyCode: CGKeyCode, originalFlags: CGEventFlags, isFlagsChanged: Bool, type: CGEventType) -> Bool {
        if !isFlagsChanged && type == .keyDown { return true }
        if isFlagsChanged {
            switch rawKeyCode {
            case 56, 60: return originalFlags.contains(.maskShift)
            case 59, 62: return originalFlags.contains(.maskControl)
            case 58, 61: return originalFlags.contains(.maskAlternate)
            case 55, 54: return originalFlags.contains(.maskCommand)
            case 57: return true
            default: return false
            }
        }
        return false
    }
    
    private static func executeFuncCommand(_ cmd: String) {
        switch cmd {
        case "lang_switch": LangSwitchService.shared.switchKeyboardLanguage()
        case "copy": KeyboardEventInjector.injectInstantMacro(keyCode: 8, flags: .maskCommand)
        case "paste": KeyboardEventInjector.injectInstantMacro(keyCode: 9, flags: .maskCommand)
        case "cut": KeyboardEventInjector.injectInstantMacro(keyCode: 7, flags: .maskCommand)
        case "undo": KeyboardEventInjector.injectInstantMacro(keyCode: 6, flags: .maskCommand)
        case "redo":
            var flags: CGEventFlags = .maskCommand
            flags.insert(.maskShift)
            KeyboardEventInjector.injectInstantMacro(keyCode: 6, flags: flags)
        case "select_all": KeyboardEventInjector.injectInstantMacro(keyCode: 0, flags: .maskCommand)
        case "save": KeyboardEventInjector.injectInstantMacro(keyCode: 1, flags: .maskCommand)
        case "find": KeyboardEventInjector.injectInstantMacro(keyCode: 3, flags: .maskCommand)
        case "type_clipboard":
            if let string = NSPasteboard.general.string(forType: .string) {
                KeyboardEventInjector.typeText(string, delayMs: 10)
            }
        default: break
        }
    }
    
    private static func executeMacro(actions: [ParsedToAction]) {
        for action in actions {
            if action.keyCode >= 2000 {
                let btn = Int32(action.keyCode - 2000)
                KeyboardEventInjector.postMouseEvent(button: btn, isDown: true)
                usleep(1000)
                KeyboardEventInjector.postMouseEvent(button: btn, isDown: false)
                usleep(1000)
            } else if action.keyCode >= 1000 {
                let mediaKey = Int32(action.keyCode - 1000)
                let finalFlags = action.coreFlags
                KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                usleep(1000)
                KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: finalFlags)
                usleep(1000)
            } else {
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
        }
    }
    
    private static func executeStandardAction(action: ParsedToAction, rawKeyCode: CGKeyCode, finalFlags: CGEventFlags, isFlagsChanged: Bool, isPress: Bool, event: CGEvent) -> Bool {
        if action.keyCode >= 2000 {
            let btn = Int32(action.keyCode - 2000)
            if isFlagsChanged {
                if isPress {
                    KeyboardEventInjector.postMouseEvent(button: btn, isDown: true)
                    KeyboardEventInjector.postMouseEvent(button: btn, isDown: false)
                }
                return true
            } else {
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags)
                let isRepeat = (rawKeyCode < 2000) && (event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
                if !isRepeat { KeyboardEventInjector.postMouseEvent(button: btn, isDown: true) }
                return true
            }
        } else if action.keyCode >= 1000 {
            let mediaKey = Int32(action.keyCode - 1000)
            if isFlagsChanged {
                if isPress {
                    KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                    KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: false, flags: finalFlags)
                }
                return true
            } else {
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: finalFlags)
                KeyboardEventInjector.postMediaKeyEvent(mediaKey: mediaKey, isDown: true, flags: finalFlags)
                return true
            }
        } else {
            var augmentedFlags = finalFlags
            let navKeys: Set<CGKeyCode> = [114, 115, 119, 116, 121, 123, 124, 125, 126, 117]
            let fnKeys: Set<CGKeyCode> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
            if navKeys.contains(action.keyCode) || fnKeys.contains(action.keyCode) { augmentedFlags.insert(.maskSecondaryFn) }
            if navKeys.contains(action.keyCode) { augmentedFlags.insert(.maskNumericPad) }

            if isFlagsChanged {
                if isPress {
                    PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: augmentedFlags)
                    let source = CGEventSource(stateID: .hidSystemState)
                    if let down = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) {
                        down.flags = augmentedFlags
                        down.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                        down.post(tap: .cghidEventTap)
                    }
                    if rawKeyCode == 57 {
                        PCModeProcessor.shared.activeRemaps.removeValue(forKey: rawKeyCode)
                        if let up = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: false) {
                            up.flags = augmentedFlags
                            up.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                            up.post(tap: .cghidEventTap)
                        }
                    }
                }
                return true
            } else {
                PCModeProcessor.shared.activeRemaps[rawKeyCode] = (keyCode: action.keyCode, flags: augmentedFlags)
                let source = CGEventSource(stateID: .hidSystemState)
                if let newEvent = CGEvent(keyboardEventSource: source, virtualKey: action.keyCode, keyDown: true) {
                    newEvent.flags = augmentedFlags
                    newEvent.setIntegerValueField(.eventSourceUserData, value: magicEventSourceUserData)
                    newEvent.post(tap: .cghidEventTap)
                }
                return true
            }
        }
    }
}