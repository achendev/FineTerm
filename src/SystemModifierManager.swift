import Foundation

struct SystemModifierManager {
    // HID Usage Tables (Apple standard):
    // Left Control: 0x7000000E0
    // Left Option:  0x7000000E2
    // Left Command: 0x7000000E3
    // Right Control:0x7000000E4
    // Right Option: 0x7000000E6
    // Right Command:0x7000000E7
    // Globe / Fn:   0xFF00000003
    
    static func applyCurrentSettings() {
        let enabled = UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled)
        if !enabled {
            reset()
            return
        }
        
        let fnTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapFn) ?? "globe"
        let ctrlTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCtrl) ?? "control"
        let optTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapOpt) ?? "option"
        let cmdTarget = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCmd) ?? "command"
        
        var mappings: [String] = []
        
        func getDst(for target: String, isRight: Bool) -> Int {
            switch target {
            case "globe": return 0xFF00000003
            case "control": return isRight ? 0x7000000E4 : 0x7000000E0
            case "option": return isRight ? 0x7000000E6 : 0x7000000E2
            case "command": return isRight ? 0x7000000E7 : 0x7000000E3
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