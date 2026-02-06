import Foundation

struct AppConfig {
    struct Keys {
        static let copyOnSelect = "copyOnSelect"
        static let pasteOnRightClick = "pasteOnRightClick"
        static let debugMode = "debugMode"
        
        static let commandPrefix = "commandPrefix"
        static let commandSuffix = "commandSuffix"
        static let changeTerminalName = "changeTerminalName"
        
        static let hideCommandInList = "hideCommandInList"
        static let smartFilter = "smartFilter"
        static let snapToTerminal = "snapToTerminal"
        
        static let globalShortcutKey = "globalShortcutKey"
        static let globalShortcutModifier = "globalShortcutModifier"
        static let globalShortcutAnywhere = "globalShortcutAnywhere"
        static let secondActivationToTerminal = "secondActivationToTerminal"
        static let thirdActivationToOrigin = "thirdActivationToOrigin"
        static let escToTerminal = "escToTerminal"
        
        static let enableClipboardManager = "enableClipboardManager"
        static let clipboardShortcutKey = "clipboardShortcutKey"
        static let clipboardShortcutModifier = "clipboardShortcutModifier"
        static let clipboardMaxLines = "clipboardMaxLines"
        static let clipboardHistorySize = "clipboardHistorySize"
    }
    
    static let defaults: [String: Any] = [
        Keys.copyOnSelect: true,
        Keys.pasteOnRightClick: true,
        Keys.debugMode: false,
        
        Keys.commandPrefix: "unset HISTFILE ; clear ; ",
        Keys.commandSuffix: " && exit",
        Keys.changeTerminalName: true,
        
        Keys.hideCommandInList: true,
        Keys.smartFilter: true,
        Keys.snapToTerminal: false,
        
        Keys.globalShortcutKey: "n",
        Keys.globalShortcutModifier: "command",
        Keys.globalShortcutAnywhere: false,
        Keys.secondActivationToTerminal: true,
        Keys.thirdActivationToOrigin: true,
        Keys.escToTerminal: false,
        
        Keys.enableClipboardManager: false,
        Keys.clipboardShortcutKey: "u",
        Keys.clipboardShortcutModifier: "command",
        Keys.clipboardMaxLines: 2,
        Keys.clipboardHistorySize: 100
    ]
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }
}
