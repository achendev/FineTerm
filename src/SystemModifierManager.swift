import Foundation

struct SystemModifierManager {
    // HID Usage Tables (Apple standard):
    // Caps Lock:    0x700000039
    // Left Control: 0x7000000E0
    // Left Option:  0x7000000E2
    // Left Command: 0x7000000E3
    // Right Control:0x7000000E4
    // Right Option: 0x7000000E6
    // Right Command:0x7000000E7
    // Globe / Fn:   0xFF00000003
    // F1-F12:       0x70000003A - 0x700000045
    // F13-F24:      0x700000068 - 0x700000073
    
    static func applyCurrentSettings() {
        let enabled = UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled)
        let engine = UserDefaults.standard.integer(forKey: AppConfig.Keys.pcModeEngine)
        
        // CRITICAL FIX: If Karabiner is active (Engine 1 or 2), we MUST clear hidutil.
        // Karabiner is already handling the system modifier swaps via karabiner.json.
        // If we leave hidutil active, the modifiers get swapped twice, ruining App Switches and PC Mode rules.
        if !enabled || engine > 0 {
            reset()
            return
        }
        
        let fnTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapFn) ?? "control"
        let ctrlTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCtrl) ?? "globe"
        let optTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapOpt) ?? "command"
        let cmdTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCmd) ?? "option"
        let capsLockTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCapsLock) ?? "capslock"
        
        var mappings: [String] = []
        
        func getDst(for target: String, isRight: Bool) -> Int {
            if target.hasPrefix("f"), let fNum = Int(target.dropFirst()) {
                if fNum >= 1 && fNum <= 12 {
                    return 0x70000003A + fNum - 1
                } else if fNum >= 13 && fNum <= 24 {
                    // macOS WindowServer drops HID usages for F21-F24 because there are no CGKeyCodes for them.
                    // We secretly alias F21-F24 to F17-F20 hardware keys so they reliably reach the CGEventTap.
                    let adjustedNum = fNum > 20 ? fNum - 4 : fNum
                    return 0x700000068 + adjustedNum - 13
                }
            }
            
            switch target {
            case "globe": return 0xFF00000003
            case "control": return isRight ? 0x7000000E4 : 0x7000000E0
            case "option": return isRight ? 0x7000000E6 : 0x7000000E2
            case "command": return isRight ? 0x7000000E7 : 0x7000000E3
            case "capslock": return 0x700000039
            default: return 0
            }
        }
        
        // 1. Map Globe / Fn (Only has Left variant in hardware)
        if fnTarget != "globe" {
            let dst = getDst(for: fnTarget, isRight: false)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0xFF00000003,\"HIDKeyboardModifierMappingDst\":\(dst)}")
        }
        
        // 2. Map Control (Both Left and Right keys)
        if ctrlTarget != "control" {
            let lDst = getDst(for: ctrlTarget, isRight: false)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E0,\"HIDKeyboardModifierMappingDst\":\(lDst)}")
            
            let rDst = getDst(for: ctrlTarget, isRight: true)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E4,\"HIDKeyboardModifierMappingDst\":\(rDst)}")
        }
        
        // 3. Map Option
        if optTarget != "option" {
            let lDst = getDst(for: optTarget, isRight: false)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E2,\"HIDKeyboardModifierMappingDst\":\(lDst)}")
            
            let rDst = getDst(for: optTarget, isRight: true)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E6,\"HIDKeyboardModifierMappingDst\":\(rDst)}")
        }
        
        // 4. Map Command
        if cmdTarget != "command" {
            let lDst = getDst(for: cmdTarget, isRight: false)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E3,\"HIDKeyboardModifierMappingDst\":\(lDst)}")
            
            let rDst = getDst(for: cmdTarget, isRight: true)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x7000000E7,\"HIDKeyboardModifierMappingDst\":\(rDst)}")
        }
        
        // 5. Map Caps Lock
        if capsLockTarget != "capslock" {
            let dst = getDst(for: capsLockTarget, isRight: false)
            mappings.append("{\"HIDKeyboardModifierMappingSrc\":0x700000039,\"HIDKeyboardModifierMappingDst\":\(dst)}")
        }
        
        let json = "{\"UserKeyMapping\": [\(mappings.joined(separator: ","))]}"
        runHidutil(with: json)
    }
    
    static func reset() {
        let json = "{\"UserKeyMapping\": []}"
        runHidutil(with: json)
    }
    
    private static func runHidutil(with json: String) {
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = ["property", "--set", json]
        try? task.run()
    }
}