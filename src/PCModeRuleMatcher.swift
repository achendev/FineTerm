import CoreGraphics

struct PCModeRuleMatcher {
    static func match(map: ParsedKeyMap, rawKeyCode: CGKeyCode, originalFlags: CGEventFlags, isFlagsChanged: Bool) -> Bool {
        if map.fromKeyCode != rawKeyCode { return false }
        
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
        
        if map.isStrict {
            if coreEventFlags != map.fromCoreFlags { return false }
        } else {
            if !coreEventFlags.isSuperset(of: map.fromCoreFlags) { return false }
        }
        
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
        return strictMatch
    }
}