import Foundation

struct KarabinerExporter {
    static let filePath = NSHomeDirectory() + "/.config/karabiner/karabiner.json"

    static func sync(rules: [PCModeRule]) {
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
                let mappedManipulators = createManipulators(from: map, appFilterMode: rule.appFilterMode, bundleIDs: rule.appBundleIDs)
                manipulators.append(contentsOf: mappedManipulators)
            }
            if !manipulators.isEmpty {
                newRules.append([
                    "description": "FineTerm: \(rule.name)",
                    "manipulators": manipulators
                ])
            }
        }

        // 2. Export System Modifier Swaps
        let systemManipulators = getSystemModifierManipulators()
        if !systemManipulators.isEmpty {
            newRules.append([
                "description": "FineTerm: System Modifier Swaps",
                "manipulators": systemManipulators
            ])
        }

        // 3. Export Global Shortcuts (UDP commands)
        let globalManipulators = getGlobalShortcutManipulators()
        if !globalManipulators.isEmpty {
            newRules.append([
                "description": "FineTerm: Global Shortcuts",
                "manipulators": globalManipulators
            ])
        }

        var targetProfileIndex = 0
        var profileUpdated = false
        for i in 0..<profiles.count {
            if let selected = profiles[i]["selected"] as? Bool, selected {
                targetProfileIndex = i
                profileUpdated = true
                break
            }
        }

        var complexMods = profiles[targetProfileIndex]["complex_modifications"] as? [String: Any] ?? ["rules": []]
        var existingRules = complexMods["rules"] as? [[String: Any]] ?? []

        // CLEAN EXISTING FINETERM RULES (Fix duplication bug)
        existingRules = existingRules.filter { rule in
            if let desc = rule["description"] as? String {
                return !desc.hasPrefix("FineTerm:")
            }
            return true
        }

        // APPEND NEW RULES
        existingRules.append(contentsOf: newRules)
        
        // SAVE
        complexMods["rules"] = existingRules
        profiles[targetProfileIndex]["complex_modifications"] = complexMods
        json["profiles"] = profiles

        if let newData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? newData.write(to: URL(fileURLWithPath: filePath))
            if UserDefaults.standard.bool(forKey: "debugMode") {
                print("DEBUG: [KarabinerExporter] Successfully synced \(newRules.count) block rules to Karabiner.")
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
        return[ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
    }

    static func makeURLManipulator(trigger: ShortcutTrigger, url: String) -> [String: Any]? {
        var k = trigger.key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    static func getSystemModifierManipulators() -> [[String: Any]] {
        guard UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled) else { return [] }
        var manipulators: [[String: Any]] = []

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

        func makeManipulator(from: String, to: String) ->[String: Any]? {
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
            return[
                "type": "basic",
                "from": ["key_code": fromKey, "modifiers": ["optional": ["any"]]],
                "to": [["key_code": toKey]]
            ]
        }

        if let m = makeManipulator(from: "fn", to: resolveToKey(base: mapFn, side: nil)) { manipulators.append(m) }
        if let m = makeManipulator(from: "left_control", to: resolveToKey(base: mapCtrl, side: "left")) { manipulators.append(m) }
        if let m = makeManipulator(from: "right_control", to: resolveToKey(base: mapCtrl, side: "right")) { manipulators.append(m) }
        if let m = makeManipulator(from: "left_option", to: resolveToKey(base: mapOpt, side: "left")) { manipulators.append(m) }
        if let m = makeManipulator(from: "right_option", to: resolveToKey(base: mapOpt, side: "right")) { manipulators.append(m) }
        if let m = makeManipulator(from: "left_command", to: resolveToKey(base: mapCmd, side: "left")) { manipulators.append(m) }
        if let m = makeManipulator(from: "right_command", to: resolveToKey(base: mapCmd, side: "right")) { manipulators.append(m) }
        if let m = makeManipulator(from: "caps_lock", to: resolveToKey(base: mapCaps, side: nil)) { manipulators.append(m) }

        return manipulators
    }

    // MARK: - Internal Mapping Logic

    static func createManipulators(from map: KeyMap, appFilterMode: AppFilterMode, bundleIDs: [String]) -> [[String: Any]] {
        let fromParts = parse(map.from)
        guard let fromKey = fromParts.key else { return[] }
        
        var keysToMap = [fromKey]
        
        // CRITICAL FIX: Karabiner does not naturally chain complex modifications.
        // If a user maps CapsLock -> F20 in System Modifiers, and creates a rule for F20,
        // we must automatically duplicate the rule to trigger on physical CapsLock directly.
        if UserDefaults.standard.bool(forKey: AppConfig.Keys.systemModifierSwapEnabled) {
            let mapCaps = UserDefaults.standard.string(forKey: AppConfig.Keys.systemModifierMapCapsLock) ?? "capslock"
            if fromKey == mapCaps && mapCaps != "capslock" {
                keysToMap.append("caps_lock")
            }
        }

        var manipulators: [[String: Any]] = []

        for key in keysToMap {
            var fromDict: [String: Any] = [:]
            applyKey(key, to: &fromDict)

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
                if let t = mapFunc(f) { toArray.append(t) }
            } else if map.to.hasPrefix("type:") {
                let t = map.to.dropFirst(5)
                let text = t.hasPrefix(" ") ? String(t.dropFirst()) : String(t)
                let escaped = text.replacingOccurrences(of: "'", with: "'\\''")
                toArray.append(["shell_command": "osascript -e 'tell application \"System Events\" to keystroke \"\(escaped)\"'"])
            } else {
                let parts = map.to.components(separatedBy: ",")
                for part in parts {
                    let toParts = parse(part)
                    if let k = toParts.key {
                        var tDict: [String: Any] = [:]
                        applyKey(k, to: &tDict)
                        if !toParts.modifiers.isEmpty {
                            tDict["modifiers"] = toParts.modifiers
                        }
                        toArray.append(tDict)
                    }
                }
            }

            guard !toArray.isEmpty else { continue }

            var manipulator: [String: Any] = [
                "type": "basic",
                "from": fromDict,
                "to": toArray
            ]

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
            
            if !conditions.isEmpty {
                manipulator["conditions"] = conditions
            }
            
            manipulators.append(manipulator)
        }
        
        return manipulators
    }

    static func applyKey(_ k: String, to dict: inout [String: Any]) {
        switch k {
        case "button1", "left_click": dict["pointing_button"] = "button1"
        case "button2", "right_click": dict["pointing_button"] = "button2"
        case "button3", "middle_click": dict["pointing_button"] = "button3"
        default: dict["key_code"] = mapKeyString(k)
        }
    }

    static func parse(_ string: String) -> (key: String?, modifiers: [String]) {
        let parts = string.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !parts.isEmpty else { return (nil,[]) }

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
        case "hyphen": return "hyphen"
        case "equal_sign": return "equal_sign"
        case "slash": return "slash"
        case "backslash": return "backslash"
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
        case "paste": return["key_code": "v", "modifiers": ["left_command"]]
        case "cut": return["key_code": "x", "modifiers": ["left_command"]]
        case "undo": return["key_code": "z", "modifiers": ["left_command"]]
        case "redo": return["key_code": "z", "modifiers": ["left_command", "left_shift"]]
        case "select_all": return["key_code": "a", "modifiers": ["left_command"]]
        case "save": return["key_code": "s", "modifiers": ["left_command"]]
        case "find": return["key_code": "f", "modifiers": ["left_command"]]
        case "lang_switch": return["key_code": "spacebar", "modifiers": ["left_control"]]
        default: return nil
        }
    }
}