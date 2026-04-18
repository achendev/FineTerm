import Foundation

struct AppConfig {
    struct Keys {
        static let copyOnSelect = "copyOnSelect"
        static let pasteOnRightClick = "pasteOnRightClick"
        static let debugMode = "debugMode"
        
        static let targetTerminalBundleID = "targetTerminalBundleID"
        static let commandPrefix = "commandPrefix"
        static let commandSuffix = "commandSuffix"
        static let changeTerminalName = "changeTerminalName"
        static let terminalTabNameCommand = "terminalTabNameCommand"
        
        static let hideCommandInList = "hideCommandInList"
        static let smartFilter = "smartFilter"
        static let snapToTerminal = "snapToTerminal"
        
        static let globalShortcutKey = "globalShortcutKey"
        static let globalShortcutModifier = "globalShortcutModifier"
        static let globalShortcutAnywhere = "globalShortcutAnywhere"
        static let secondActivationToTerminal = "secondActivationToTerminal"
        static let thirdActivationToOrigin = "thirdActivationToOrigin"
        static let escToTerminal = "escToTerminal"
        
        static let enableTerminalToggleShortcut = "enableTerminalToggleShortcut"
        static let terminalToggleShortcutKey = "terminalToggleShortcutKey"
        static let terminalToggleShortcutModifier = "terminalToggleShortcutModifier"
        
        static let enableClipboardManager = "enableClipboardManager"
        static let clipboardShortcutKey = "clipboardShortcutKey"
        static let clipboardShortcutModifier = "clipboardShortcutModifier"
        static let clipboardMaxLines = "clipboardMaxLines"
        static let clipboardHistorySize = "clipboardHistorySize"
        static let clipboardMaxImages = "clipboardMaxImages"
        
        static let enableLibraryManager = "enableLibraryManager"
        static let libraryAddShortcutKey = "libraryAddShortcutKey"
        static let libraryAddShortcutModifier = "libraryAddShortcutModifier"
        static let libraryOpenShortcutKey = "libraryOpenShortcutKey"
        static let libraryOpenShortcutModifier = "libraryOpenShortcutModifier"
        
        static let clipboardShiftEnterToEditor = "clipboardShiftEnterToEditor"
        static let clipboardEditorBundleID = "clipboardEditorBundleID"
        static let clipboardTempExtension = "clipboardTempExtension"
        static let clipboardAutoDeleteTempFile = "clipboardAutoDeleteTempFile"
        static let clipboardAutoDeleteDelay = "clipboardAutoDeleteDelay"
        
        static let clipboardItemSizeLimitKB = "clipboardItemSizeLimitKB" 
        static let clipboardLargeItemSizeLimitMB = "clipboardLargeItemSizeLimitMB"
        
        static let customAppShortcuts = "customAppShortcuts"
        static let skipNonRunningApps = "skipNonRunningApps"
        static let skipNonRunningAppsMode = "skipNonRunningAppsMode"
        
        static let systemModifierSwapEnabled = "systemModifierSwapEnabled"
        static let systemModifierMapFn = "systemModifierMapFn"
        static let systemModifierMapCtrl = "systemModifierMapCtrl"
        static let systemModifierMapOpt = "systemModifierMapOpt"
        static let systemModifierMapCmd = "systemModifierMapCmd"
        static let systemModifierMapCapsLock = "systemModifierMapCapsLock"
        
        static let pcModeRules = "pcModeRules"
        
        static let enableNextGroupShortcut = "enableNextGroupShortcut"
        static let nextGroupModifier = "nextGroupModifier"
        static let nextGroupModifier2 = "nextGroupModifier2"
        static let nextGroupKey = "nextGroupKey"
        static let nextGroupTriggers = "nextGroupTriggers"
        
        static let enablePrevGroupShortcut = "enablePrevGroupShortcut"
        static let prevGroupModifier = "prevGroupModifier"
        static let prevGroupModifier2 = "prevGroupModifier2"
        static let prevGroupKey = "prevGroupKey"
        static let prevGroupTriggers = "prevGroupTriggers"
        
        static let enableToggleGroupShortcut = "enableToggleGroupShortcut"
        static let toggleGroupModifier = "toggleGroupModifier"
        static let toggleGroupModifier2 = "toggleGroupModifier2"
        static let toggleGroupKey = "toggleGroupKey"
        static let toggleGroupTriggers = "toggleGroupTriggers"
    }
    
    static let customAppShortcutsData = (try? JSONEncoder().encode([
        CustomAppShortcut(triggers: [ShortcutTrigger(key: "i", modifier: "option")], bundleIDs: [""])
    ])) ?? Data()
    
    // Comprehensive VM & Terminal list for standard PC bindings bypass
    static let standardExcludeList = [
       "com.apple.Terminal", "com.googlecode.iterm2", "org.tabby", "com.mitchellh.ghostty"
    ]
    
    static let defaultPCRules: [PCModeRule] = [
        PCModeRule(name: "Navigation (Arrows)", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + left_arrow", to: "home"),
            KeyMap(from: "ctrl + right_arrow", to: "end"),
            KeyMap(from: "ctrl + up_arrow", to: "page_up"),
            KeyMap(from: "ctrl + down_arrow", to: "page_down"),
            KeyMap(from: "cmd + left_arrow", to: "home"),
            KeyMap(from: "cmd + right_arrow", to: "end"),
            KeyMap(from: "cmd + up_arrow", to: "page_up"),
            KeyMap(from: "cmd + down_arrow", to: "page_down")
        ]),
        PCModeRule(name: "Language Switch (Instant)", isEnabled: false, mappings: [
            KeyMap(from: "opt + left_shift", to: "func: lang_switch"),
            KeyMap(from: "shift + left_option", to: "func: lang_switch")
        ]),
        PCModeRule(name: "Delete / Backspace Word", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + delete_or_backspace", to: "opt + delete_or_backspace"),
            KeyMap(from: "opt + delete_or_backspace", to: "delete_forward")
        ]),
        PCModeRule(name: "Copy/Paste/Cut/Undo/Find/Save", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + c", to: "func: copy"),
            KeyMap(from: "ctrl + v", to: "func: paste"),
            KeyMap(from: "ctrl + x", to: "func: cut"),
            KeyMap(from: "ctrl + z", to: "func: undo"),
            KeyMap(from: "ctrl + y", to: "func: redo"),
            KeyMap(from: "ctrl + a", to: "func: select_all"),
            KeyMap(from: "ctrl + s", to: "func: save"),
            KeyMap(from: "ctrl + f", to: "func: find"),
            KeyMap(from: "ctrl + g", to: "cmd + g"),
            KeyMap(from: "ctrl + d", to: "cmd + d"),
            KeyMap(from: "ctrl + r", to: "cmd + r"),
            KeyMap(from: "ctrl + slash", to: "cmd + slash")
        ], appFilterMode: .exclude, appBundleIDs: standardExcludeList),
        PCModeRule(name: "Browser Shortcuts", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + equal_sign", to: "cmd + equal_sign"),
            KeyMap(from: "ctrl + hyphen", to: "cmd + hyphen"),
            KeyMap(from: "ctrl + 0", to: "cmd + 0"),
            KeyMap(from: "ctrl + shift + b", to: "cmd + shift + b"),
            KeyMap(from: "ctrl + shift + t", to: "cmd + shift + t")
        ], appFilterMode: .include, appBundleIDs: ["org.mozilla.firefox", "com.microsoft.Edge", "com.google.Chrome", "com.brave.Browser", "com.apple.Safari"]),
        PCModeRule(name: "Shift+F10 to Print Screen", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + shift + f10", to: "cmd + shift + 1"),
            KeyMap(from: "shift + f10", to: "cmd + shift + 2")
        ]),
        PCModeRule(name: "Shift+F12 to Paste (Standard)", isEnabled: false, mappings: [
            KeyMap(from: "shift + f12", to: "func: paste")
        ], appFilterMode: .exclude, appBundleIDs: ["org.tabby", "com.mitchellh.ghostty"]),
        PCModeRule(name: "Shift+F12 to Insert (Terminals)", isEnabled: false, mappings: [
            KeyMap(from: "shift + f12", to: "shift + insert")
        ], appFilterMode: .include, appBundleIDs: ["org.tabby", "com.mitchellh.ghostty"]),
        PCModeRule(name: "Switch Apps (Alt+Tab)", isEnabled: false, mappings: [
            KeyMap(from: "opt + tab", to: "ctrl + f4")
        ]),
        PCModeRule(name: "System Controls & Misc", isEnabled: false, mappings: [
            KeyMap(from: "cmd + f11", to: "shift + opt + volume_decrement"),
            KeyMap(from: "cmd + f12", to: "shift + opt + volume_increment"),
            KeyMap(from: "cmd + f1", to: "shift + opt + display_brightness_decrement"),
            KeyMap(from: "cmd + f2", to: "shift + opt + display_brightness_increment"),
            KeyMap(from: "ctrl + shift + m", to: "cmd + shift + m")
        ]),
        PCModeRule(name: "Tabs Management", isEnabled: false, mappings: [
            KeyMap(from: "rshift + ropt", to: "ctrl + tab"),
            KeyMap(from: "rshift + rcmd", to: "ctrl + shift + tab"),
            KeyMap(from: "rshift + up_arrow", to: "ctrl + tab"),
            KeyMap(from: "rshift + left_arrow", to: "ctrl + shift + tab"),
            KeyMap(from: "opt + w", to: "ctrl + tab"),
            KeyMap(from: "opt + q", to: "ctrl + shift + tab")
        ]),
        PCModeRule(name: "Task Manager (Ctrl+Shift+Esc)", isEnabled: false, mappings: [
            KeyMap(from: "ctrl + shift + esc", to: "shell: open '/System/Applications/Utilities/Activity Monitor.app'")
        ])
    ]
    
    static let pcModeRulesData = (try? JSONEncoder().encode(defaultPCRules)) ?? Data()
    
    static let defaults: [String: Any] = [
        Keys.copyOnSelect: true,
        Keys.pasteOnRightClick: true,
        Keys.debugMode: false,
        
        Keys.targetTerminalBundleID: "com.apple.Terminal",
        Keys.commandPrefix: "unset HISTFILE ; clear ; ",
        Keys.commandSuffix: " && exit",
        Keys.changeTerminalName: true,
        Keys.terminalTabNameCommand: "( ( sleep 2 ; printf '\\e]1;%s\\a' '$PROFILE_NAME' ) 2>/dev/null & ) 2>/dev/null ; clear ; ",
        
        Keys.hideCommandInList: true,
        Keys.smartFilter: true,
        Keys.snapToTerminal: false,
        
        Keys.globalShortcutKey: "n",
        Keys.globalShortcutModifier: "command",
        Keys.globalShortcutAnywhere: false,
        Keys.secondActivationToTerminal: true,
        Keys.thirdActivationToOrigin: true,
        Keys.escToTerminal: false,
        
        Keys.enableTerminalToggleShortcut: true,
        Keys.terminalToggleShortcutKey: "h",
        Keys.terminalToggleShortcutModifier: "command",
        
        Keys.enableClipboardManager: false,
        Keys.clipboardShortcutKey: "u",
        Keys.clipboardShortcutModifier: "command",
        Keys.clipboardMaxLines: 2,
        Keys.clipboardHistorySize: 100,
        Keys.clipboardMaxImages: 50,
        
        Keys.enableLibraryManager: false,
        Keys.libraryAddShortcutKey: "n",
        Keys.libraryAddShortcutModifier: "option",
        Keys.libraryOpenShortcutKey: "m",
        Keys.libraryOpenShortcutModifier: "option",
        
        Keys.clipboardShiftEnterToEditor: true,
        Keys.clipboardEditorBundleID: "com.sublimetext.4",
        Keys.clipboardTempExtension: "sh",
        Keys.clipboardAutoDeleteTempFile: true,
        Keys.clipboardAutoDeleteDelay: 2.0,
        
        Keys.clipboardItemSizeLimitKB: 10,
        Keys.clipboardLargeItemSizeLimitMB: 5,
        
        Keys.customAppShortcuts: customAppShortcutsData,
        Keys.skipNonRunningApps: false,
        Keys.skipNonRunningAppsMode: 0,
        
        Keys.systemModifierSwapEnabled: false,
        Keys.systemModifierMapFn: "control",
        Keys.systemModifierMapCtrl: "globe",
        Keys.systemModifierMapOpt: "command",
        Keys.systemModifierMapCmd: "option",
        Keys.systemModifierMapCapsLock: "capslock",
        
        Keys.pcModeRules: pcModeRulesData,
        
        Keys.enableNextGroupShortcut: false,
        Keys.nextGroupModifier: "right control",
        Keys.nextGroupModifier2: "shift",
        Keys.nextGroupKey: ".",
        Keys.nextGroupTriggers: Data(),
        
        Keys.enablePrevGroupShortcut: false,
        Keys.prevGroupModifier: "right control",
        Keys.prevGroupModifier2: "shift",
        Keys.prevGroupKey: ",",
        Keys.prevGroupTriggers: Data(),
        
        Keys.enableToggleGroupShortcut: false,
        Keys.toggleGroupModifier: "right control",
        Keys.toggleGroupModifier2: "shift",
        Keys.toggleGroupKey: "/",
        Keys.toggleGroupTriggers: Data()
    ]
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }
    
    static func exportSettings() -> Data? {
        var dict: [String: Any] = [:]
        for key in defaults.keys {
            let val = UserDefaults.standard.object(forKey: key) ?? defaults[key]
            if let dataVal = val as? Data {
                if let jsonObject = try? JSONSerialization.jsonObject(with: dataVal, options: []) {
                    dict[key] = jsonObject
                } else {
                    dict[key] = dataVal.base64EncodedString()
                }
            } else {
                dict[key] = val
            }
        }
        return try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
    }

    static func importSettings(from data: Data) -> Bool {
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return false }
        for (key, val) in dict {
            guard defaults.keys.contains(key) else { continue }
            
            if defaults[key] is Data {
                if let arrayVal = val as? [Any], let jsonData = try? JSONSerialization.data(withJSONObject: arrayVal) {
                    UserDefaults.standard.set(jsonData, forKey: key)
                } else if let dictVal = val as? [String: Any], let jsonData = try? JSONSerialization.data(withJSONObject: dictVal) {
                    UserDefaults.standard.set(jsonData, forKey: key)
                } else if let strVal = val as? String, let decodedData = Data(base64Encoded: strVal) {
                    UserDefaults.standard.set(decodedData, forKey: key)
                }
            } else {
                UserDefaults.standard.set(val, forKey: key)
            }
        }
        return true
    }
}