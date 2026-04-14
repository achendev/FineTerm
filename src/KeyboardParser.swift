import CoreGraphics
import Foundation

struct KeyboardParser {
    // Maps NX_KEYTYPE media keys to standard F-key keycodes
    static let mediaKeyToFKey: [Int32: CGKeyCode] = [
        0: 111,  // VolUp -> F12
        1: 103,  // VolDown -> F11
        7: 109,  // Mute -> F10
        2: 120,  // BrightnessUp -> F2
        3: 122,  // BrightnessDown -> F1
        21: 97,  // KbdBrightUp -> F6
        22: 96,  // KbdBrightDown -> F5
        16: 100, // Play -> F8
        17: 101, // Next -> F9
        18: 98   // Prev -> F7
    ]

    static let specialKeyCodes: [String: CGKeyCode] = [
        "esc": 53, "escape": 53, "tab": 48, "space": 49, "spacebar": 49,
        "enter": 36, "return": 36, "capslock": 57, "caps_lock": 57,
        "left_arrow": 123, "right_arrow": 124, "down_arrow": 125, "up_arrow": 126,
        "home": 115, "end": 119, "page_up": 116, "page_down": 121,
        "delete_or_backspace": 51, "delete_forward": 117, "insert": 114,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "f13": 105, "f14": 107, "f15": 113, "f16": 106, "f17": 64, "f18": 79, "f19": 80, "f20": 90,
        // Aliasing F21-F24 to F17-F20 as safety nets since macOS drops actual F21-F24 HID events
        "f21": 64, "f22": 79, "f23": 80, "f24": 90,
        "hyphen": 27, "equal_sign": 24, "slash": 44, "backslash": 42,
        "left_shift": 56, "right_shift": 60, "left_control": 59, "right_control": 62,
        "left_option": 58, "right_option": 61, "left_command": 55, "right_command": 54,
        "lshift": 56, "rshift": 60, "lctrl": 59, "rctrl": 62,
        "lopt": 58, "ropt": 61, "lcmd": 55, "rcmd": 54,
        "alt": 58, "lalt": 58, "ralt": 61,
        "cmd": 55, "ctrl": 59, "shift": 56,
        
        // Virtual KeyCodes for system media keys
        "volume_increment": 1000, "vol_up": 1000,
        "volume_decrement": 1001, "vol_down": 1001,
        "display_brightness_increment": 1002, "brightness_up": 1002,
        "display_brightness_decrement": 1003, "brightness_down": 1003,
        "mute": 1007,
        "play_pause": 1016, "play": 1016,
        "next_track": 1017,
        "prev_track": 1018,
        "illumination_increment": 1021, "kbd_brightness_up": 1021,
        "illumination_decrement": 1022, "kbd_brightness_down": 1022,
        
        // Virtual KeyCodes for Mouse Buttons
        "button1": 2001, "left_click": 2001,
        "button2": 2002, "right_click": 2002,
        "button3": 2003, "middle_click": 2003
    ]

    static func getKeyCode(for char: String) -> CGKeyCode? {
        let lower = char.lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet.punctuationCharacters).inverted)
                        .joined()
                        .trimmingCharacters(in: .whitespaces)
                        
        if let code = specialKeyCodes[lower] { return code }
        
        switch lower {
            case "a": return 0; case "s": return 1; case "d": return 2; case "f": return 3; case "h": return 4
            case "g": return 5; case "z": return 6; case "x": return 7; case "c": return 8; case "v": return 9
            case "b": return 11; case "q": return 12; case "w": return 13; case "e": return 14; case "r": return 15
            case "y": return 16; case "t": return 17; case "1": return 18; case "2": return 19; case "3": return 20
            case "4": return 21; case "6": return 22; case "5": return 23; case "=": return 24; case "9": return 25
            case "7": return 26; case "-": return 27; case "8": return 28; case "0": return 29; case "]": return 30
            case "o": return 31; case "u": return 32; case "[": return 33; case "i": return 34; case "p": return 35
            case "l": return 37; case "j": return 38; case "'": return 39; case "k": return 40; case ";": return 41
            case "\\": return 42; case ",": return 43; case "/": return 44; case "n": return 45; case "m": return 46
            case ".": return 47; default: return nil
        }
    }
    
    static func parseKeyString(_ input: String) -> (coreFlags: CGEventFlags, strictFlags: [String], key: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("shell:") {
            return ([], [], trimmed)
        }
        
        let rawParts = input.components(separatedBy: "+")
        let parts = rawParts.map { 
            $0.components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet.punctuationCharacters).inverted).joined().lowercased() 
        }.filter { !$0.isEmpty }
        
        guard !parts.isEmpty else { return ([], [], "") }
        
        var coreFlags: CGEventFlags = []
        var strictFlags: [String] = []
        let key = parts.last!
        
        if parts.count > 1 {
            for rawMod in parts.dropLast() {
                let mod = rawMod.replacingOccurrences(of: " ", with: "_")
                switch mod {
                case "cmd", "command": coreFlags.insert(.maskCommand)
                case "ctrl", "control": coreFlags.insert(.maskControl)
                case "opt", "alt", "option": coreFlags.insert(.maskAlternate)
                case "shift": coreFlags.insert(.maskShift)
                case "fn", "globe": coreFlags.insert(.maskSecondaryFn)
                
                case "lcmd", "left_command": coreFlags.insert(.maskCommand); strictFlags.append("left_command")
                case "rcmd", "right_command": coreFlags.insert(.maskCommand); strictFlags.append("right_command")
                case "lctrl", "left_control": coreFlags.insert(.maskControl); strictFlags.append("left_control")
                case "rctrl", "right_control": coreFlags.insert(.maskControl); strictFlags.append("right_control")
                case "lopt", "left_option", "lalt": coreFlags.insert(.maskAlternate); strictFlags.append("left_option")
                case "ropt", "right_option", "ralt": coreFlags.insert(.maskAlternate); strictFlags.append("right_option")
                case "lshift", "left_shift": coreFlags.insert(.maskShift); strictFlags.append("left_shift")
                case "rshift", "right_shift": coreFlags.insert(.maskShift); strictFlags.append("right_shift")
                default: 
                    if UserDefaults.standard.bool(forKey: "debugMode") {
                        print("DEBUG: [KeyboardParser] FAILED to parse modifier '\(mod)' in rule '\(input)'")
                    }
                    return ([], [], "") 
                }
            }
        }
        
        return (coreFlags, strictFlags, key)
    }
}