import SwiftUI

struct SettingsView: View {
    // Configuration Keys
    @AppStorage(AppConfig.Keys.copyOnSelect) private var copyOnSelect = true
    @AppStorage(AppConfig.Keys.pasteOnRightClick) private var pasteOnRightClick = true
    @AppStorage(AppConfig.Keys.debugMode) private var debugMode = false
    
    @AppStorage(AppConfig.Keys.commandPrefix) private var commandPrefix = ""
    @AppStorage(AppConfig.Keys.commandSuffix) private var commandSuffix = ""
    @AppStorage(AppConfig.Keys.changeTerminalName) private var changeTerminalName = true
    
    @AppStorage(AppConfig.Keys.hideCommandInList) private var hideCommandInList = true
    @AppStorage(AppConfig.Keys.smartFilter) private var smartFilter = true
    @AppStorage(AppConfig.Keys.snapToTerminal) private var snapToTerminal = false
    
    @AppStorage(AppConfig.Keys.globalShortcutKey) private var globalShortcutKey = "n"
    @AppStorage(AppConfig.Keys.globalShortcutModifier) private var globalShortcutModifier = "command"
    @AppStorage(AppConfig.Keys.globalShortcutAnywhere) private var globalShortcutAnywhere = false
    @AppStorage(AppConfig.Keys.secondActivationToTerminal) private var secondActivationToTerminal = true
    @AppStorage(AppConfig.Keys.thirdActivationToOrigin) private var thirdActivationToOrigin = true
    @AppStorage(AppConfig.Keys.escToTerminal) private var escToTerminal = false
    
    @AppStorage(AppConfig.Keys.enableClipboardManager) private var enableClipboardManager = false
    @AppStorage(AppConfig.Keys.clipboardShortcutKey) private var clipboardShortcutKey = "u"
    @AppStorage(AppConfig.Keys.clipboardShortcutModifier) private var clipboardShortcutModifier = "command"
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var clipboardMaxLines = 2
    @AppStorage(AppConfig.Keys.clipboardHistorySize) private var clipboardHistorySize = 100
    
    // New Text Editor Settings
    @AppStorage(AppConfig.Keys.clipboardShiftEnterToEditor) private var clipboardShiftEnterToEditor = true
    @AppStorage(AppConfig.Keys.clipboardEditorBundleID) private var clipboardEditorBundleID = "com.apple.TextEdit"
    @AppStorage(AppConfig.Keys.clipboardTempExtension) private var clipboardTempExtension = "sh"
    @AppStorage(AppConfig.Keys.clipboardAutoDeleteTempFile) private var clipboardAutoDeleteTempFile = true
    @AppStorage(AppConfig.Keys.clipboardAutoDeleteDelay) private var clipboardAutoDeleteDelay = 2.0
    
    // Storage Limit
    @AppStorage(AppConfig.Keys.clipboardItemSizeLimitKB) private var clipboardItemSizeLimitKB = 10
    
    @State private var runOnStartup: Bool = LaunchAtLoginManager.isEnabled()
    
    // Observe the bridge for the list of editors
    @ObservedObject private var editorBridge = TextEditorBridge.shared
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // 1. Connection Manager
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connection Manager")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Picker("", selection: $globalShortcutModifier) {
                                    Text("Command").tag("command")
                                    Text("Control").tag("control")
                                    Text("Option").tag("option")
                                }
                                .frame(width: 100)
                                .labelsHidden()
                                
                                Text("+")
                                
                                TextField("Key", text: $globalShortcutKey)
                                    .frame(width: 40)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        .padding(.leading, 10)
                        
                        Toggle("System-wide (Global)", isOn: $globalShortcutAnywhere)
                        Toggle("Second Activation to Terminal", isOn: $secondActivationToTerminal)
                        
                        if secondActivationToTerminal {
                            Toggle("Third Activation Back to Origin", isOn: $thirdActivationToOrigin)
                                .padding(.leading, 20)
                        }
                        
                        Toggle("Esc to Terminal", isOn: $escToTerminal)
                    }
                    
                    Divider()
                    
                    // 2. Clipboard Manager
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Clipboard Manager")
                            .font(.headline)
                        
                        Toggle("Enable Clipboard Manager", isOn: $enableClipboardManager)
                        
                        if enableClipboardManager {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Shortcut:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Picker("", selection: $clipboardShortcutModifier) {
                                        Text("Command").tag("command")
                                        Text("Control").tag("control")
                                        Text("Option").tag("option")
                                    }
                                    .frame(width: 100)
                                    .labelsHidden()
                                    
                                    Text("+")
                                    
                                    TextField("Key", text: $clipboardShortcutKey)
                                        .frame(width: 40)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                            }
                            .padding(.leading, 10)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Display:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text("Max Lines:")
                                        .font(.caption)
                                    TextField("2", value: $clipboardMaxLines, formatter: NumberFormatter())
                                        .frame(width: 40)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                            }
                            .padding(.leading, 10)
                            
                            // Editor Integration
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("Shift + Enter opens in Text Editor", isOn: $clipboardShiftEnterToEditor)
                                
                                if clipboardShiftEnterToEditor {
                                    HStack {
                                        Text("Editor:")
                                            .font(.caption)
                                            .frame(width: 70, alignment: .leading)
                                        
                                        Picker("", selection: $clipboardEditorBundleID) {
                                            ForEach(editorBridge.availableEditors) { editor in
                                                Text(editor.name)
                                                    .tag(editor.id)
                                            }
                                        }
                                        .labelsHidden()
                                    }
                                    .padding(.leading, 20)
                                    
                                    HStack {
                                        Text("Extension:")
                                            .font(.caption)
                                            .frame(width: 70, alignment: .leading)
                                        
                                        TextField("sh", text: $clipboardTempExtension)
                                            .textFieldStyle(RoundedBorderTextFieldStyle())
                                            .frame(width: 60)
                                    }
                                    .padding(.leading, 20)
                                    
                                    HStack(spacing: 4) {
                                        Toggle("Auto delete temp file after:", isOn: $clipboardAutoDeleteTempFile)
                                            .font(.caption)
                                        
                                        if clipboardAutoDeleteTempFile {
                                            TextField("2", value: $clipboardAutoDeleteDelay, formatter: NumberFormatter())
                                                .frame(width: 40)
                                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                            Text("sec")
                                                .font(.caption)
                                        }
                                    }
                                    .padding(.leading, 20)
                                }
                            }
                            .padding(.top, 4)
                            
                            // Storage
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Storage:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Text("Max Items:")
                                        .font(.caption)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("100", value: $clipboardHistorySize, formatter: NumberFormatter())
                                        .frame(width: 50)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                
                                HStack {
                                    Text("Item Limit (KB):")
                                        .font(.caption)
                                        .frame(width: 80, alignment: .leading)
                                    TextField("10", value: $clipboardItemSizeLimitKB, formatter: NumberFormatter())
                                        .frame(width: 50)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                }
                                
                                Button("Clear History") {
                                    NSApp.sendAction(#selector(AppDelegate.clearClipboardHistory), to: nil, from: nil)
                                }
                                .controlSize(.small)
                            }
                            .padding(.leading, 10)
                        }
                    }
                    
                    Divider()
                    
                    // 3. Command Wrappers
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Command Wrappers")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prefix:")
                                .font(.caption)
                            TextField("e.g. unset HISTFILE", text: $commandPrefix)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suffix:")
                                .font(.caption)
                            TextField("e.g. && exit", text: $commandSuffix)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        Toggle("Set Terminal Tab Name", isOn: $changeTerminalName)
                    }
                    
                    Divider()
                    
                    // 4. UI & Behavior
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Behavior")
                            .font(.headline)
                        
                        Toggle("Hide Command in List", isOn: $hideCommandInList)
                        Toggle("Smart Search (Multi-word)", isOn: $smartFilter)
                        Toggle("Snap to Terminal (Left Side)", isOn: $snapToTerminal)
                            .onChange(of: snapToTerminal) { newValue in
                                // Trigger refresh of observer in AppDelegate
                                NSApp.sendAction(#selector(AppDelegate.refreshTerminalObserverState), to: nil, from: nil)
                            }
                        Toggle("Copy on Select", isOn: $copyOnSelect)
                        Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                    }
                    
                    Divider()
                    
                    // 5. System
                    VStack(alignment: .leading, spacing: 10) {
                        Text("System")
                            .font(.headline)
                        
                        Toggle("Run on Startup", isOn: $runOnStartup)
                            .onChange(of: runOnStartup) { LaunchAtLoginManager.setEnabled($0) }
                        
                        Toggle("Debug Mode", isOn: $debugMode)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 600)
        .onAppear {
            editorBridge.refreshEditors()
        }
    }
}