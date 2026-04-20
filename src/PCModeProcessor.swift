import Cocoa
import ApplicationServices

class PCModeProcessor {
    static let shared = PCModeProcessor()
    
    var activeRemaps: [CGKeyCode: (keyCode: CGKeyCode, flags: CGEventFlags)] = [:]
    
    func reset() {
        activeRemaps.removeAll()
    }
    
    func process(type: CGEventType, keyCode: Int64, flags: CGEventFlags, event: CGEvent, frontAppID: String) -> Bool {
        // 1. Check if Karabiner Engine is Active. If so, let Karabiner handle the keys!
        if UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine) == 1 {
            return false
        }
        
        let isDebug = UserDefaults.standard.bool(forKey: "debugMode")
        let isFlagsChanged = (type == .flagsChanged)
        let rawKeyCode = CGKeyCode(keyCode)
        
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
            default: isPress = true
            }
            if !isPress { isRelease = true }
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
                return true
            }
            return false 
        }

        let originalFlags = flags
        
        for parsedRule in KeyboardCache.shared.pcRules {
            if parsedRule.rule.appFilterMode == .include && !parsedRule.rule.appBundleIDs.contains(frontAppID) { continue }
            if parsedRule.rule.appFilterMode == .exclude && parsedRule.rule.appBundleIDs.contains(frontAppID) { continue }
            
            for map in parsedRule.mappings {
                if PCModeRuleMatcher.match(map: map, rawKeyCode: rawKeyCode, originalFlags: originalFlags, isFlagsChanged: isFlagsChanged) {
                    if isDebug && type == .keyDown { print("DEBUG: [PCMode]   -> MATCHED! Executing mapping to: '\(map.original.to)'") }
                    return PCModeActionExecutor.execute(map: map, rawKeyCode: rawKeyCode, originalFlags: originalFlags, isFlagsChanged: isFlagsChanged, type: type, event: event)
                }
            }
        }
        return false
    }
}