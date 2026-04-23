import CoreGraphics
import Foundation

struct ParsedToAction {
    let keyCode: CGKeyCode
    let coreFlags: CGEventFlags
}

struct ParsedKeyMap {
    let original: KeyMap
    let fromKeyCode: CGKeyCode
    let fromCoreFlags: CGEventFlags
    let fromStrictFlags: [String]
    let isStrict: Bool
    let isShell: Bool
    let shellCommand: String?
    let isFunc: Bool
    let funcCommand: String?
    let isType: Bool
    let typeText: String?
    let toActions: [ParsedToAction]
}

struct ParsedPCModeRule {
    let rule: PCModeRule
    let mappings: [ParsedKeyMap]
}

struct ParsedShortcutTrigger {
    let keyCode: CGKeyCode?
    let coreFlags: CGEventFlags
    let strictFlags: [String]
    
    func matches(type: CGEventType, eventKeyCode: Int64, flags: CGEventFlags) -> Bool {
        if let code = keyCode {
            if type != .keyDown { return false }
            if eventKeyCode != Int64(code) { return false }
        } else {
            if type != .flagsChanged { return false }
        }
        
        let eventCoreFlags = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        if eventCoreFlags != coreFlags { return false }
        
        let raw = flags.rawValue
        for strictMod in strictFlags {
            switch strictMod {
            case "left_command": if (raw & 0x08) == 0 { return false }
            case "right_command": if (raw & 0x10) == 0 { return false }
            case "left_control": if (raw & 0x01) == 0 { return false }
            case "right_control": if (raw & 0x2000) == 0 { return false }
            case "left_option": if (raw & 0x20) == 0 { return false }
            case "right_option": if (raw & 0x40) == 0 { return false }
            case "left_shift": if (raw & 0x02) == 0 { return false }
            case "right_shift": if (raw & 0x04) == 0 { return false }
            default: break
            }
        }
        return true
    }
}

struct ParsedCustomAppShortcut {
    let id: UUID
    let bundleIDs: [String]
    let triggers: [ParsedShortcutTrigger]
}