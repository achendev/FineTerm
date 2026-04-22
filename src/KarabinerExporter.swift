import Foundation

struct KarabinerExporter {
    static let filePath = NSHomeDirectory() + "/.config/karabiner/karabiner.json"
    private static let syncedSimpleModsKey = "KarabinerSyncedSimpleMods"

    private static func isSameSimpleMod(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        guard let aFrom = a["from"] as? [String: Any], let bFrom = b["from"] as? [String: Any],
              let aFromCode = aFrom["key_code"] as? String, let bFromCode = bFrom["key_code"] as? String else {
            return false
        }
        
        var aToCode = ""
        if let aToArray = a["to"] as? [[String: Any]], let first = aToArray.first, let code = first["key_code"] as? String {
            aToCode = code
        } else if let aToDict = a["to"] as? [String: Any], let code = aToDict["key_code"] as? String {
            aToCode = code
        }
        
        var bToCode = ""
        if let bToArray = b["to"] as? [[String: Any]], let first = bToArray.first, let code = first["key_code"] as? String {
            bToCode = code
        } else if let bToDict = b["to"] as? [String: Any], let code = bToDict["key_code"] as? String {
            bToCode = code
        }
        
        return aFromCode == bFromCode && aToCode == bToCode
    }

    private static func removeMods(_ mods: [[String: Any]], thatMatch targets: [[String: Any]]) -> [[String: Any]] {
        return mods.filter { mod in
            !targets.contains { target in isSameSimpleMod(mod, target) }
        }
    }

    static func sync(rules: [PCModeRule], engine: Int) {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              var json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              var profiles = json["profiles"] as? [[String: Any]] else {
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [KarabinerExporter] Failed to load karabiner.json. Ensure Karabiner-Elements is installed.")
            }
            return
        }

        var newRules: [[String: Any]] = []

        // 1. Export PC Mode Rules
        for rule in rules where rule.isEnabled {
            var manipulators: [[String: Any]] = []
            for map in rule.mappings {
                let mappedManipulators = createManipulators(from: map, appFilterMode: rule.appFilterMode, bundleIDs: rule.appBundleIDs, engine: engine)
                manipulators.append(contentsOf: mappedManipulators)
            }
            if !manipulators.isEmpty {
                newRules.append([
                    "description": "FineTerm: \(rule.name)",
                    "manipulators": manipulators
                ])
            }
        }

        // 2. Export Global Shortcuts (UDP commands) unconditionally handled by Karabiner
        let globalManipulators = getGlobalShortcutManipulators()
        if !globalManipulators.isEmpty {
            newRules.append([
                "description": "FineTerm: Global Shortcuts",
                "manipulators": globalManipulators
            ])
        }

        // 3. Export System Modifier Swaps (As Simple Modifications)
        var systemSimpleMods = getSystemSimpleModifications()

        // Find Target Profile
        var targetProfileIndex = 0
        for i in 0..<profiles.count {
            if let selected = profiles[i]["selected"] as? Bool, selected {
                targetProfileIndex = i
                break
            }
        }

        // --- UPDATE COMPLEX MODIFICATIONS ---
        var complexMods = profiles[targetProfileIndex]["complex_modifications"] as? [String: Any] ?? ["rules": []]
        var existingRules = complexMods["rules"] as? [[String: Any]] ?? []

        existingRules = existingRules.filter { rule in
            if let desc = rule["description"] as? String {
                return !desc.hasPrefix("FineTerm:")
            }
            return true
        }

        existingRules.append(contentsOf: newRules)
        complexMods["rules"] = existingRules
        profiles[targetProfileIndex]["complex_modifications"] = complexMods

        // --- UPDATE SIMPLE MODIFICATIONS ---
        var existingSimpleMods = profiles[targetProfileIndex]["simple_modifications"] as? [[String: Any]] ?? []
        
        existingSimpleMods = existingSimpleMods.filter { $0["__fineterm"] == nil }
        
        if let previousData = UserDefaults.standard.data(forKey: syncedSimpleModsKey),
           let previousMods = try? JSONSerialization.jsonObject(with: previousData, options: []) as? [[String: Any]] {
            existingSimpleMods = removeMods(existingSimpleMods, thatMatch: previousMods)
        } else {
            let fallbackMods = getFallbackSimpleModifications()
            existingSimpleMods = removeMods(existingSimpleMods, thatMatch: fallbackMods)
        }
        
        for i in 0..<systemSimpleMods.count {
            systemSimpleMods[i].removeValue(forKey: "__fineterm")
        }
        
        existingSimpleMods.append(contentsOf: systemSimpleMods)
        profiles[targetProfileIndex]["simple_modifications"] = existingSimpleMods
        
        if let trackedData = try? JSONSerialization.data(withJSONObject: systemSimpleMods, options: []) {
            UserDefaults.standard.set(trackedData, forKey: syncedSimpleModsKey)
        }

        // SAVE
        json["profiles"] = profiles

        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: filePath))
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [KarabinerExporter] Successfully synced \(newRules.count) block rules and \(systemSimpleMods.count) simple modifications to Karabiner.")
            }
        }
    }

    static func clear() {
        guard FileManager.default.fileExists(atPath: filePath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              var json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              var profiles = json["profiles"] as? [[String: Any]] else {
            return
        }

        var modified = false
        for i in 0..<profiles.count {
            
            if var complexMods = profiles[i]["complex_modifications"] as? [String: Any],
               let existingRules = complexMods["rules"] as? [[String: Any]] {

                let filtered = existingRules.filter { rule in
                    if let desc = rule["description"] as? String {
                        return !desc.hasPrefix("FineTerm:")
                    }
                    return true
                }

                if filtered.count != existingRules.count {
                    complexMods["rules"] = filtered
                    profiles[i]["complex_modifications"] = complexMods
                    modified = true
                }
            }
            
            if let existingSimpleMods = profiles[i]["simple_modifications"] as? [[String: Any]] {
                var filtered = existingSimpleMods.filter { $0["__fineterm"] == nil }
                
                if let previousData = UserDefaults.standard.data(forKey: syncedSimpleModsKey),
                   let previousMods = try? JSONSerialization.jsonObject(with: previousData, options: []) as? [[String: Any]] {
                    filtered = removeMods(filtered, thatMatch: previousMods)
                } else {
                    let fallbackMods = getFallbackSimpleModifications()
                    filtered = removeMods(filtered, thatMatch: fallbackMods)
                }
                
                if filtered.count != existingSimpleMods.count {
                    profiles[i]["simple_modifications"] = filtered
                    modified = true
                }
            }
        }

        if modified {
            json["profiles"] = profiles
            if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? newData.write(to: URL(fileURLWithPath: filePath))
                if UserDefaults.standard.bool(forKey: "debugMode") {
                    print("DEBUG: [KarabinerExporter] Cleared existing FineTerm rules from Karabiner.")
                }
            }
        }
        
        UserDefaults.standard.removeObject(forKey: syncedSimpleModsKey)
    }

    // MARK: - App Shortcuts & Navigations
    static func getGlobalShortcutManipulators() -> [[String: Any]] {
        var manipulators: [[String: Any]] = []

        func addTrigger(_ trigger: ShortcutTrigger, url: String) {
            if let m = makeURLManipulator(trigger: trigger, url: url) { manipulators.append(m) }
        }

        let d = UserDefaults.standard

        if let data = d.data(forKey: AppConfig.Keys.customAppShortcuts),
           let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
            for s in shortcuts where s.isEnabled {
                for t in s.triggers { addTrigger(t, url: "fineterm://action/custom-shortcut?id=\(s.id.uuidString)") }
            }
        }

        if d.bool(forKey: AppConfig.Keys.enableNextGroupShortcut) {
            for t in loadGroupTriggers(data: d.data(forKey: AppConfig.Keys.nextGroupTriggers), mod1Key: AppConfig.Keys.nextGroupModifier, mod2Key: AppConfig.Keys.nextGroupModifier2, keyKey: AppConfig.Keys.nextGroupKey, defKey: ".") {
                addTrigger(t, url: "fineterm://action/next-group")
            }
        }
        
        if d.bool(forKey: AppConfig.Keys.enablePrevGroupShortcut) {
            for t in loadGroupTriggers(data: d.data(forKey: AppConfig.Keys.prevGroupTriggers), mod1Key: AppConfig.Keys.prevGroupModifier, mod2Key: AppConfig.Keys.prevGroupModifier2, keyKey: AppConfig.Keys.prevGroupKey, defKey: ",") {
                addTrigger(t, url: "fineterm://action/prev-group")
            }
        }
        
        if d.bool(forKey: AppConfig.Keys.enableToggleGroupShortcut) {
            for t in loadGroupTriggers(data: d.data(forKey: AppConfig.Keys.toggleGroupTriggers), mod1Key: AppConfig.Keys.toggleGroupModifier, mod2Key: AppConfig.Keys.toggleGroupModifier2, keyKey: AppConfig.Keys.toggleGroupKey, defKey: "/") {
                addTrigger(t, url: "fineterm://action/toggle-group")
            }
        }

        if d.bool(forKey: AppConfig.Keys.enableClipboardManager) {
            addTrigger(ShortcutTrigger(key: d.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u", modifier: d.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command"), url: "fineterm://action/clipboard")
        }

        if d.bool(forKey: AppConfig.Keys.enableLibraryManager) {
            addTrigger(ShortcutTrigger(key: d.string(forKey: AppConfig.Keys.libraryAddShortcutKey) ?? "n", modifier: d.string(forKey: AppConfig.Keys.libraryAddShortcutModifier) ?? "option"), url: "fineterm://action/library-add")
            addTrigger(ShortcutTrigger(key: d.string(forKey: AppConfig.Keys.libraryOpenShortcutKey) ?? "m", modifier: d.string(forKey: AppConfig.Keys.libraryOpenShortcutModifier) ?? "option"), url: "fineterm://action/library-open")
        }

        if d.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut) {
            addTrigger(ShortcutTrigger(key: d.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h", modifier: d.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command"), url: "fineterm://action/terminal-toggle")
        }

        addTrigger(ShortcutTrigger(key: d.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n", modifier: d.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"), url: "fineterm://action/main-toggle")

        return manipulators
    }

    static func loadGroupTriggers(data: Data?, mod1Key: String, mod2Key: String, keyKey: String, defKey: String) -> [ShortcutTrigger] {
        if let d = data, let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: d), !decoded.isEmpty {
            return decoded
        }
        let m1 = UserDefaults.standard.string(forKey: mod1Key) ?? "right control"
        let m2 = UserDefaults.standard.string(forKey: mod2Key) ?? "shift"
        let k = UserDefaults.standard.string(forKey: keyKey) ?? defKey
        return [ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
    }

    static func makeURLManipulator(trigger: ShortcutTrigger, url: String) ->[String: Any]? {
        var k = trigger.key.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .controlCharacters).joined().lowercased()
        var primaryMod = trigger.modifier.replacingOccurrences(of: " ", with: "_")
        var secMod = trigger.modifier2?.replacingOccurrences(of: " ", with: "_")

        func mapModName(_ m: String) -> String {
            switch m {
            case "command", "cmd", "lcmd", "left_command": return "left_command"
            case "rcmd", "right_command": return "right_command"
            case "control", "ctrl", "lctrl", "left_control": return "left_control"
            case "rctrl", "right_control": return "right_control"
            case "option", "opt", "alt", "lopt", "left_option": return "left_option"
            case "ropt", "right_option", "ralt": return "right_option"
            case "shift", "lshift", "left_shift": return "left_shift"
            case "rshift", "right_shift": return "right_shift"
            case "fn", "globe": return "fn"
            case "capslock": return "caps_lock"
            default: return m
            }
        }

        primaryMod = mapModName(primaryMod)
        if let s = secMod, s != "none" { secMod = mapModName(s) } else { secMod = nil }

        var fromDict: [String: Any] = [:]
        var mods: [String] = []

        if k.isEmpty {
            k = primaryMod
            if let s = secMod { mods.append(s) }
        } else {
            k = mapKeyString(k)
            mods.append(primaryMod)
            if let s = secMod { mods.append(s) }
        }

        fromDict["key_code"] = k
        if !mods.isEmpty {
            fromDict["modifiers"] = ["mandatory": mods, "optional": ["any"]]
        } else {
            fromDict["modifiers"] = ["optional": ["any"]]
        }

        let payload = url.replacingOccurrences(of: "fineterm://action/", with: "fineterm/")

        let manipulator: [String: Any] = [
            "type": "basic",
            "from": fromDict,
            "to": [["shell_command": "/bin/bash -c \"echo -n '\(payload)' > /dev/udp/127.0.0.1/61234\""]]
        ]

        return manipulator
    }

    // MARK: - System Modifier Swaps

    static func getFallbackSimpleModifications() -> [[String: Any]] {
        var simpleMods: [[String: Any]] = []

        let mapFn = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapFn) ?? "control"
        let mapCtrl = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCtrl) ?? "globe"
        let mapOpt = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapOpt) ?? "command"
        let mapCmd = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCmd) ?? "option"
        let mapCaps = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCapsLock) ?? "capslock"

        func resolveToKey(base: String, side: String?) -> String {
            if base == "globe" { return "fn" }
            if base == "capslock" { return "caps_lock" }
            if base.hasPrefix("f") { return base } 
            if let s = side { return "\(s)_\(base)" }
            return "left_\(base)"
        }

        func makeSimpleMod(from: String, to: String) -> [String: Any]? {
            var toKey = to == "globe" ? "fn" : to
            switch toKey {
            case "control": toKey = "left_control"
            case "option": toKey = "left_option"
            case "command": toKey = "left_command"
            case "capslock": toKey = "caps_lock"
            default: break
            }
            
            let fromKey = from == "globe" ? "fn" : from
            if fromKey == toKey { return nil }
            
            return [
                "from": ["key_code": fromKey],
                "to": [["key_code": toKey]],
                "__fineterm": true
            ]
        }

        if let m = makeSimpleMod(from: "fn", to: resolveToKey(base: mapFn, side: nil)) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "left_control", to: resolveToKey(base: mapCtrl, side: "left")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "right_control", to: resolveToKey(base: mapCtrl, side: "right")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "left_option", to: resolveToKey(base: mapOpt, side: "left")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "right_option", to: resolveToKey(base: mapOpt, side: "right")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "left_command", to: resolveToKey(base: mapCmd, side: "left")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "right_command", to: resolveToKey(base: mapCmd, side: "right")) { simpleMods.append(m) }
        if let m = makeSimpleMod(from: "caps_lock", to: resolveToKey(base: mapCaps, side: nil)) { simpleMods.append(m) }

        return simpleMods
    }

    static func getSystemSimpleModifications() -> [[String: Any]] {
        guard UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled) else { return [] }
        return getFallbackSimpleModifications()
    }

    // MARK: - Internal Mapping Logic

    static func createManipulators(from map: KeyMap, appFilterMode: AppFilterMode, bundleIDs: [String], engine: Int) -> [[String: Any]] {
        let fromParts = parse(map.from)
        guard let fromKey = fromParts.key else { return [] }
        
        var manipulators: [[String: Any]] = []

        var fromDict: [String: Any] = [:]
        applyKey(fromKey, to: &fromDict)

        if !fromParts.modifiers.isEmpty {
            fromDict["modifiers"] = ["mandatory": fromParts.modifiers, "optional": ["any"]]
        } else {
            fromDict["modifiers"] = ["optional": ["any"]]
        }

        var toArray: [[String: Any]] = []

        if map.to.hasPrefix("shell:") {
            let cmd = map.to.dropFirst(6).trimmingCharacters(in: .whitespaces)
            toArray.append(["shell_command": cmd])
        } else if map.to.hasPrefix("func:") {
            let f = map.to.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if f == "type_clipboard" {
                toArray.append(["shell_command": "/bin/bash -c \"echo -n 'fineterm/type-clipboard' > /dev/udp/127.0.0.1/61234\""])
            } else if let t = mapFunc(f) {
                toArray.append(t)
            }
        } else if map.to.hasPrefix("type:") {
            let t = map.to.dropFirst(5)
            let text = t.hasPrefix(" ") ? String(t.dropFirst()) : String(t)
            if let base64 = text.data(using: .utf8)?.base64EncodedString() {
                toArray.append(["shell_command": "/bin/bash -c \"echo -n 'fineterm/type-text?b64=\(base64)' > /dev/udp/127.0.0.1/61234\""])
            }
        } else {
            let parts = KeyboardParser.splitActions(map.to)
            for part in parts {
                let toParts = parse(part)
                if let k = toParts.key {
                    var tDict: [String: Any] = [:]
                    applyKey(k, to: &tDict)
                    
                    var outMods = toParts.modifiers
                    
                    let mappedK = mapKeyString(k)
                    let fnKeys: Set<String> = [
                        "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", 
                        "f13", "f14", "f15", "f16", "f17", "f18", "f19", "f20", "f21", "f22", "f23", "f24",
                        "home", "end", "page_up", "page_down", "left_arrow", "right_arrow", "up_arrow", "down_arrow",
                        "insert", "delete_forward"
                    ]
                    
                    if fnKeys.contains(mappedK) && !outMods.contains("fn") {
                        outMods.append("fn")
                    }
                    
                    if !outMods.isEmpty {
                        tDict["modifiers"] = outMods
                    }
                    toArray.append(tDict)
                }
            }
        }

        guard !toArray.isEmpty else { return [] }

        var manipulator: [String: Any] = [
            "type": "basic",
            "from": fromDict,
            "to": toArray
        ]
        
        if map.to.trimmingCharacters(in: .whitespaces) == "func: scroll_mode" {
            var aloneDict: [String: Any] = [:]
            applyKey(fromKey, to: &aloneDict)
            if !fromParts.modifiers.isEmpty {
                aloneDict["modifiers"] = fromParts.modifiers
            }
            manipulator["to_if_alone"] = [aloneDict]
        }

        var conditions: [[String: Any]] = []

        if appFilterMode != .none && !bundleIDs.isEmpty {
            let validIDs = bundleIDs.filter { !$0.isEmpty }.map { "^" + $0.replacingOccurrences(of: ".", with: "\\.") + "$" }
            if !validIDs.isEmpty {
                conditions.append([
                    "type": appFilterMode == .include ? "frontmost_application_if" : "frontmost_application_unless",
                    "bundle_identifiers": validIDs
                ])
            }
        }
        
        if engine == 2 {
            conditions.append([
                "type": "variable_if",
                "name": "fineterm_secure_input",
                "value": 1
            ])
        }
        
        if !conditions.isEmpty {
            manipulator["conditions"] = conditions
        }
        
        manipulators.append(manipulator)
        
        return manipulators
    }

    static func applyKey(_ k: String, to dict: inout[String: Any]) {
        let mapped = mapKeyString(k)
        switch mapped {
        case "button1", "left_click": dict["pointing_button"] = "button1"
        case "button2", "right_click": dict["pointing_button"] = "button2"
        case "button3", "middle_click": dict["pointing_button"] = "button3"
        case "volume_increment", "volume_decrement", "mute", "play_or_pause", "fastforward", "rewind", "display_brightness_increment", "display_brightness_decrement", "illumination_increment", "illumination_decrement":
            dict["consumer_key_code"] = mapped
        case "vol_up": dict["consumer_key_code"] = "volume_increment"
        case "vol_down": dict["consumer_key_code"] = "volume_decrement"
        case "play", "play_pause": dict["consumer_key_code"] = "play_or_pause"
        case "next_track": dict["consumer_key_code"] = "fastforward"
        case "prev_track": dict["consumer_key_code"] = "rewind"
        case "brightness_up": dict["consumer_key_code"] = "display_brightness_increment"
        case "brightness_down": dict["consumer_key_code"] = "display_brightness_decrement"
        case "kbd_brightness_up": dict["consumer_key_code"] = "illumination_increment"
        case "kbd_brightness_down": dict["consumer_key_code"] = "illumination_decrement"
        default: dict["key_code"] = mapped
        }
    }

    static func parse(_ string: String) -> (key: String?, modifiers: [String]) {
        let cleanedString = string.components(separatedBy: .controlCharacters).joined()
        let parts = cleanedString.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return (nil, []) }

        let rawKey = parts.last!
        var modifiers: [String] = []

        for mod in parts.dropLast() {
            switch mod {
            case "cmd", "command", "lcmd", "left_command": modifiers.append("left_command")
            case "rcmd", "right_command": modifiers.append("right_command")
            case "ctrl", "control", "lctrl", "left_control": modifiers.append("left_control")
            case "rctrl", "right_control": modifiers.append("right_control")
            case "opt", "alt", "option", "lopt", "left_option": modifiers.append("left_option")
            case "ropt", "right_option", "ralt": modifiers.append("right_option")
            case "shift", "lshift", "left_shift": modifiers.append("left_shift")
            case "rshift", "right_shift": modifiers.append("right_shift")
            case "fn", "globe": modifiers.append("fn")
            default: break
            }
        }

        let key = mapKeyString(rawKey)
        return (key, modifiers)
    }

    static func mapKeyString(_ k: String) -> String {
        switch k {
        case ",", "comma": return "comma"
        case ".", "period": return "period"
        case ";", "semicolon": return "semicolon"
        case "'", "quote": return "quote"
        case "[", "open_bracket": return "open_bracket"
        case "]", "close_bracket": return "close_bracket"
        case "`", "grave_accent_and_tilde": return "grave_accent_and_tilde"
        case "\\", "backslash": return "backslash"
        case "-": return "hyphen"
        case "=": return "equal_sign"
        case "/": return "slash"
        case "delete_or_backspace": return "delete_or_backspace"
        case "delete_forward": return "delete_forward"
        case "return", "enter": return "return_or_enter"
        case "esc", "escape": return "escape"
        case "left_arrow": return "left_arrow"
        case "right_arrow": return "right_arrow"
        case "up_arrow": return "up_arrow"
        case "down_arrow": return "down_arrow"
        case "space", "spacebar": return "spacebar"
        case "capslock", "caps_lock": return "caps_lock"
        case "page_up": return "page_up"
        case "page_down": return "page_down"
        case "home": return "home"
        case "end": return "end"
        case "insert": return "insert"
        default: return k
        }
    }

    static func mapFunc(_ f: String) ->[String: Any]? {
        switch f {
        case "copy": return ["key_code": "c", "modifiers": ["left_command"]]
        case "paste": return ["key_code": "v", "modifiers": ["left_command"]]
        case "cut": return ["key_code": "x", "modifiers": ["left_command"]]
        case "undo": return ["key_code": "z", "modifiers": ["left_command"]]
        case "redo": return ["key_code": "z", "modifiers": ["left_command", "left_shift"]]
        case "select_all": return ["key_code": "a", "modifiers": ["left_command"]]
        case "save": return ["key_code": "s", "modifiers": ["left_command"]]
        case "find": return ["key_code": "f", "modifiers": ["left_command"]]
        case "lang_switch": return ["shell_command": "/bin/bash -c \"echo -n 'fineterm/lang-switch' > /dev/udp/127.0.0.1/61234\""]
        case "scroll_mode": return ["software_function": ["mouse_motion_to_scroll": ["options": ["momentum_scroll_enabled": true, "speed_multiplier": 1.0]]]]
        default: return nil
        }
    }
}