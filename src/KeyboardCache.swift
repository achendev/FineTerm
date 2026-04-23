import Foundation

class KeyboardCache {
    static let shared = KeyboardCache()
    
    // Pre-Parsed Shortcut Triggers
    var customShortcuts: [ParsedCustomAppShortcut] = []
    var pcRules: [ParsedPCModeRule] = []
    var nextGroupTriggers: [ParsedShortcutTrigger] = []
    var prevGroupTriggers: [ParsedShortcutTrigger] = []
    var toggleGroupTriggers: [ParsedShortcutTrigger] = []
    
    var mainShortcut: ParsedShortcutTrigger?
    var terminalToggleShortcut: ParsedShortcutTrigger?
    var clipboardShortcut: ParsedShortcutTrigger?
    var libraryAddShortcut: ParsedShortcutTrigger?
    var libraryOpenShortcut: ParsedShortcutTrigger?

    // Settings Cache
    var enableNextGroupShortcut = false
    var enablePrevGroupShortcut = false
    var enableToggleGroupShortcut = false
    var enableTerminalToggleShortcut = false
    var enableClipboardManager = false
    var enableLibraryManager = false
    var pcModeEngine = 0
    
    private var userDefaultsObserver: NSObjectProtocol?
    
    func start() {
        refresh()
        userDefaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) {[weak self] _ in
            self?.refresh()
        }
    }
    
    func stop() {
        if let obs = userDefaultsObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        userDefaultsObserver = nil
        customShortcuts.removeAll()
        pcRules.removeAll()
        nextGroupTriggers.removeAll()
        prevGroupTriggers.removeAll()
        toggleGroupTriggers.removeAll()
    }
    
    private func refresh() {
        let isDebug = UserDefaults.standard.bool(forKey: "debugMode")
        if isDebug { print("DEBUG: [KeyboardCache] Rebuilding and parsing internal rule cache...") }
        
        let defaults = UserDefaults.standard
        pcModeEngine = defaults.integer(forKey: AppConfig.Keys.pcModeEngine)
        enableNextGroupShortcut = defaults.bool(forKey: AppConfig.Keys.enableNextGroupShortcut)
        enablePrevGroupShortcut = defaults.bool(forKey: AppConfig.Keys.enablePrevGroupShortcut)
        enableToggleGroupShortcut = defaults.bool(forKey: AppConfig.Keys.enableToggleGroupShortcut)
        enableTerminalToggleShortcut = defaults.bool(forKey: AppConfig.Keys.enableTerminalToggleShortcut)
        enableClipboardManager = defaults.bool(forKey: AppConfig.Keys.enableClipboardManager)
        enableLibraryManager = defaults.bool(forKey: AppConfig.Keys.enableLibraryManager)

        mainShortcut = KeyboardParser.parseShortcutTrigger(ShortcutTrigger(
            key: defaults.string(forKey: AppConfig.Keys.globalShortcutKey) ?? "n",
            modifier: defaults.string(forKey: AppConfig.Keys.globalShortcutModifier) ?? "command"
        ))
        
        terminalToggleShortcut = KeyboardParser.parseShortcutTrigger(ShortcutTrigger(
            key: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutKey) ?? "h",
            modifier: defaults.string(forKey: AppConfig.Keys.terminalToggleShortcutModifier) ?? "command"
        ))
        
        clipboardShortcut = KeyboardParser.parseShortcutTrigger(ShortcutTrigger(
            key: defaults.string(forKey: AppConfig.Keys.clipboardShortcutKey) ?? "u",
            modifier: defaults.string(forKey: AppConfig.Keys.clipboardShortcutModifier) ?? "command"
        ))
        
        libraryAddShortcut = KeyboardParser.parseShortcutTrigger(ShortcutTrigger(
            key: defaults.string(forKey: AppConfig.Keys.libraryAddShortcutKey) ?? "n",
            modifier: defaults.string(forKey: AppConfig.Keys.libraryAddShortcutModifier) ?? "option"
        ))
        
        libraryOpenShortcut = KeyboardParser.parseShortcutTrigger(ShortcutTrigger(
            key: defaults.string(forKey: AppConfig.Keys.libraryOpenShortcutKey) ?? "m",
            modifier: defaults.string(forKey: AppConfig.Keys.libraryOpenShortcutModifier) ?? "option"
        ))

        self.customShortcuts = []
        if let data = defaults.data(forKey: AppConfig.Keys.customAppShortcuts),
           let shortcuts = try? JSONDecoder().decode([CustomAppShortcut].self, from: data) {
            for s in shortcuts where s.isEnabled {
                let parsedTriggers = s.triggers.compactMap { KeyboardParser.parseShortcutTrigger($0) }
                if !parsedTriggers.isEmpty {
                    self.customShortcuts.append(ParsedCustomAppShortcut(id: s.id, bundleIDs: s.bundleIDs, triggers: parsedTriggers))
                }
            }
        }
        
        var newPCRules: [ParsedPCModeRule] = []
        if let data = UserDefaults.standard.data(forKey: AppConfig.Keys.pcModeRules) {
            do {
                let rules = try JSONDecoder().decode([PCModeRule].self, from: data)
                
                for rule in rules where rule.isEnabled {
                    var parsedMappings: [ParsedKeyMap] = []
                    for map in rule.mappings {
                        
                        // Parse alias 'cursor_move' syntactically
                        let parts = map.from.components(separatedBy: "+").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                        let filtered = parts.filter { $0 != "cursor_move" }
                        let actualFromStr = filtered.joined(separator: " + ")
                        
                        let fromParsed = KeyboardParser.parseKeyString(actualFromStr)
                        guard !fromParsed.key.isEmpty else { continue }
                        guard let fromCode = KeyboardParser.getKeyCode(for: fromParsed.key) else { continue }
                        
                        var isShell = false
                        var shellCommand: String? = nil
                        var isFunc = false
                        var funcCommand: String? = nil
                        var isType = false
                        var typeText: String? = nil
                        var toActions: [ParsedToAction] = []
                        
                        if map.to.lowercased().hasPrefix("shell:") {
                            isShell = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 6)
                            shellCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                        } else if map.to.lowercased().hasPrefix("func:") {
                            isFunc = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 5)
                            funcCommand = String(map.to[cmdStartIndex...]).trimmingCharacters(in: .whitespaces)
                        } else if map.to.lowercased().hasPrefix("type:") {
                            isType = true
                            let cmdStartIndex = map.to.index(map.to.startIndex, offsetBy: 5)
                            let text = String(map.to[cmdStartIndex...])
                            typeText = text.hasPrefix(" ") ? String(text.dropFirst()) : text
                        } else {
                            let toPartsRaw = KeyboardParser.splitActions(map.to)
                            for part in toPartsRaw {
                                let toParsed = KeyboardParser.parseKeyString(part)
                                guard !toParsed.key.isEmpty else { continue }
                                guard let code = KeyboardParser.getKeyCode(for: toParsed.key) else { continue }
                                toActions.append(ParsedToAction(keyCode: code, coreFlags: toParsed.coreFlags))
                            }
                            if toActions.isEmpty { continue }
                        }
                        
                        parsedMappings.append(ParsedKeyMap(
                            original: map, 
                            fromKeyCode: fromCode, 
                            fromCoreFlags: fromParsed.coreFlags, 
                            fromStrictFlags: fromParsed.strictFlags, 
                            fromCustomModifiers: fromParsed.customModifiers,
                            isStrict: map.isStrict,
                            isShell: isShell,
                            shellCommand: shellCommand,
                            isFunc: isFunc,
                            funcCommand: funcCommand,
                            isType: isType,
                            typeText: typeText,
                            toActions: toActions
                        ))
                    }
                    
                    parsedMappings.sort { $0.fromCoreFlags.rawValue.nonzeroBitCount > $1.fromCoreFlags.rawValue.nonzeroBitCount }
                    newPCRules.append(ParsedPCModeRule(rule: rule, mappings: parsedMappings))
                }
            } catch {
                if isDebug { print("DEBUG: [KeyboardCache] CRITICAL ERROR decoding PCModeRules JSON: \(error)") }
            }
        }
        self.pcRules = newPCRules
        if isDebug { print("DEBUG: [KeyboardCache] Finished parsing. Active PC Groups: \(self.pcRules.count)") }
        
        self.nextGroupTriggers = loadTriggers(forKey: AppConfig.Keys.nextGroupTriggers, oldMod1: AppConfig.Keys.nextGroupModifier, oldMod2: AppConfig.Keys.nextGroupModifier2, oldKey: AppConfig.Keys.nextGroupKey, defaultKey: ".").compactMap { KeyboardParser.parseShortcutTrigger($0) }
        self.prevGroupTriggers = loadTriggers(forKey: AppConfig.Keys.prevGroupTriggers, oldMod1: AppConfig.Keys.prevGroupModifier, oldMod2: AppConfig.Keys.prevGroupModifier2, oldKey: AppConfig.Keys.prevGroupKey, defaultKey: ",").compactMap { KeyboardParser.parseShortcutTrigger($0) }
        self.toggleGroupTriggers = loadTriggers(forKey: AppConfig.Keys.toggleGroupTriggers, oldMod1: AppConfig.Keys.toggleGroupModifier, oldMod2: AppConfig.Keys.toggleGroupModifier2, oldKey: AppConfig.Keys.toggleGroupKey, defaultKey: "/").compactMap { KeyboardParser.parseShortcutTrigger($0) }
    }
    
    private func loadTriggers(forKey key: String, oldMod1: String, oldMod2: String, oldKey: String, defaultKey: String) -> [ShortcutTrigger] {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: data), !decoded.isEmpty {
            return decoded
        }
        let m1 = UserDefaults.standard.string(forKey: oldMod1) ?? "right control"
        let m2 = UserDefaults.standard.string(forKey: oldMod2) ?? "shift"
        let k = UserDefaults.standard.string(forKey: oldKey) ?? defaultKey
        return [ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
    }
}