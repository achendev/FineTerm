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
        
        // Text Editor Integration
        static let clipboardShiftEnterToEditor = "clipboardShiftEnterToEditor"
        static let clipboardEditorBundleID = "clipboardEditorBundleID"
        static let clipboardTempExtension = "clipboardTempExtension"
        static let clipboardAutoDeleteTempFile = "clipboardAutoDeleteTempFile"
        static let clipboardAutoDeleteDelay = "clipboardAutoDeleteDelay"
        
        // Storage Limits
        static let clipboardItemSizeLimitKB = "clipboardItemSizeLimitKB" // Fast Store Limit (Default 10KB)
        static let clipboardLargeItemSizeLimitMB = "clipboardLargeItemSizeLimitMB" // Slow Store Limit (Default 5MB)
        
        // App Shortcuts
        static let customAppShortcuts = "customAppShortcuts"
    }
    
    static let customAppShortcutsData = (try? JSONEncoder().encode([CustomAppShortcut(key: "i", modifier: "option", bundleIDs: [""])])) ?? Data()
    
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
        
        // Defaults for Editor
        Keys.clipboardShiftEnterToEditor: true,
        Keys.clipboardEditorBundleID: "com.sublimetext.4", // Will fallback if missing
        Keys.clipboardTempExtension: "sh",
        Keys.clipboardAutoDeleteTempFile: true,
        Keys.clipboardAutoDeleteDelay: 2.0,
        
        // Default 10KB for list, 5MB for blobs
        Keys.clipboardItemSizeLimitKB: 10,
        Keys.clipboardLargeItemSizeLimitMB: 5,
        
        // Bindings array
        Keys.customAppShortcuts: customAppShortcutsData
    ]
    
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }
}