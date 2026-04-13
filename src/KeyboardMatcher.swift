import CoreGraphics

struct KeyboardMatcher {
    
    static func isExactModifierMatch(flags: CGEventFlags, required: [String]) -> Bool {
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

    static func isGlobalShortcutMatch(type: CGEventType, eventKeyCode: Int64, flags: CGEventFlags, keyStr: String, mod1Str: String, mod2Str: String?) -> Bool {
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
            guard let code = KeyboardParser.getKeyCode(for: keyStr) else { return false }
            return eventKeyCode == Int64(code) && isExactModifierMatch(flags: flags, required: [mod1Str.replacingOccurrences(of: " ", with: "_"), (mod2Str ?? "none").replacingOccurrences(of: " ", with: "_")])
        }
    }

    static func isAnyTriggerMatch(type: CGEventType, eventKeyCode: Int64, flags: CGEventFlags, triggers: [ShortcutTrigger]) -> Bool {
        for trigger in triggers {
            if isGlobalShortcutMatch(type: type, eventKeyCode: eventKeyCode, flags: flags, keyStr: trigger.key, mod1Str: trigger.modifier, mod2Str: trigger.modifier2) {
                return true
            }
        }
        return false
    }
}