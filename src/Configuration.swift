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
        
        // Text Editor Integration
        static let clipboardShiftEnterToEditor = "clipboardShiftEnterToEditor"
        static let clipboardEditorBundleID = "clipboardEditorBundleID"
        static let clipboardTempExtension = "clipboardTempExtension"
        static let clipboardAutoDeleteTempFile = "clipboardAutoDeleteTempFile"
        static let clipboardAutoDeleteDelay = "clipboardAutoDeleteDelay"
        
        // Storage Limit
        static let clipboardItemSizeLimitKB = "clipboardItemSizeLimitKB"
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
        Keys.clipboardHistorySize: 100,
        
        // Defaults for Editor
        Keys.clipboardShiftEnterToEditor: true,
        Keys.clipboardEditorBundleID: "com.sublimetext.4", // Will fallback if missing
        Keys.clipboardTempExtension: "sh",
        Keys.clipboardAutoDeleteTempFile: true,
        Keys.clipboardAutoDeleteDelay: 2.0,
        
        // Default 10KB
        Keys.clipboardItemSizeLimitKB: 10
    ]
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }
}