import SwiftUI

struct SettingsView: View {
    @ObservedObject var clipboardStore: ClipboardStore

    var body: some View {
        TabView {
            ConnectionsSettingsTab()
                .tabItem {
                    Label("Connections", systemImage: "network")
                }
            
            ClipboardSettingsTab(clipboardStore: clipboardStore)
                .tabItem {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }
            
            TerminalSettingsTab()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
            
            AdvancedSettingsTab()
                .tabItem {
                    Label("Advanced", systemImage: "gearshape")
                }
        }
        .padding()
        .frame(minWidth: 450, minHeight: 450)
    }
}

struct ConnectionsSettingsTab: View {
    @AppStorage(AppConfig.Keys.globalShortcutKey) private var globalShortcutKey = "n"
    @AppStorage(AppConfig.Keys.globalShortcutModifier) private var globalShortcutModifier = "command"
    @AppStorage(AppConfig.Keys.globalShortcutAnywhere) private var globalShortcutAnywhere = false
    @AppStorage(AppConfig.Keys.secondActivationToTerminal) private var secondActivationToTerminal = true
    @AppStorage(AppConfig.Keys.thirdActivationToOrigin) private var thirdActivationToOrigin = true
    @AppStorage(AppConfig.Keys.escToTerminal) private var escToTerminal = false
    
    @AppStorage(AppConfig.Keys.enableTerminalToggleShortcut) private var enableTerminalToggleShortcut = true
    @AppStorage(AppConfig.Keys.terminalToggleShortcutKey) private var terminalToggleShortcutKey = "h"
    @AppStorage(AppConfig.Keys.terminalToggleShortcutModifier) private var terminalToggleShortcutModifier = "command"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Main Shortcut:")
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
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("System-wide (Global)", isOn: $globalShortcutAnywhere)
                    Toggle("Second Activation to Terminal", isOn: $secondActivationToTerminal)
                    
                    if secondActivationToTerminal {
                        Toggle("Third Activation Back to Origin", isOn: $thirdActivationToOrigin)
                            .padding(.leading, 20)
                    }
                    
                    Toggle("Esc to Terminal", isOn: $escToTerminal)
                }
                .padding(.leading, 10)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Terminal Toggle Shortcut", isOn: $enableTerminalToggleShortcut)
                    
                    if enableTerminalToggleShortcut {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Picker("", selection: $terminalToggleShortcutModifier) {
                                    Text("Command").tag("command")
                                    Text("Control").tag("control")
                                    Text("Option").tag("option")
                                }
                                .frame(width: 100)
                                .labelsHidden()
                                
                                Text("+")
                                
                                TextField("Key", text: $terminalToggleShortcutKey)
                                    .frame(width: 40)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.leading, 10)
            }
            .padding()
        }
    }
}

struct ClipboardSettingsTab: View {
    @ObservedObject var clipboardStore: ClipboardStore
    @ObservedObject private var editorBridge = TextEditorBridge.shared

    @AppStorage(AppConfig.Keys.enableClipboardManager) private var enableClipboardManager = false
    @AppStorage(AppConfig.Keys.clipboardShortcutKey) private var clipboardShortcutKey = "u"
    @AppStorage(AppConfig.Keys.clipboardShortcutModifier) private var clipboardShortcutModifier = "command"
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var clipboardMaxLines = 2
    @AppStorage(AppConfig.Keys.clipboardHistorySize) private var clipboardHistorySize = 100
    @AppStorage(AppConfig.Keys.clipboardMaxImages) private var clipboardMaxImages = 50
    
    @AppStorage(AppConfig.Keys.clipboardShiftEnterToEditor) private var clipboardShiftEnterToEditor = true
    @AppStorage(AppConfig.Keys.clipboardEditorBundleID) private var clipboardEditorBundleID = "com.apple.TextEdit"
    @AppStorage(AppConfig.Keys.clipboardTempExtension) private var clipboardTempExtension = "sh"
    @AppStorage(AppConfig.Keys.clipboardAutoDeleteTempFile) private var clipboardAutoDeleteTempFile = true
    @AppStorage(AppConfig.Keys.clipboardAutoDeleteDelay) private var clipboardAutoDeleteDelay = 2.0
    
    @AppStorage(AppConfig.Keys.clipboardItemSizeLimitKB) private var clipboardItemSizeLimitKB = 10
    @AppStorage(AppConfig.Keys.clipboardLargeItemSizeLimitMB) private var clipboardLargeItemSizeLimitMB = 5

    @State private var stats: ClipboardStats?
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Enable Clipboard Manager", isOn: $enableClipboardManager)
                
                if enableClipboardManager {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Shortcut
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
                        
                        // Display
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
                        
                        Divider()
                        
                        // Editor Integration
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Shift + Enter opens in Text Editor", isOn: $clipboardShiftEnterToEditor)
                            
                            if clipboardShiftEnterToEditor {
                                HStack {
                                    Text("Editor:")
                                        .font(.caption)
                                        .frame(width: 70, alignment: .leading)
                                    
                                    Picker("", selection: $clipboardEditorBundleID) {
                                        ForEach(editorBridge.availableEditors) { editor in
                                            Text(editor.name).tag(editor.id)
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
                        
                        Divider()
                        
                        // Storage
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Storage & Limits:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text("Max Text Items:")
                                    .font(.caption)
                                    .frame(width: 90, alignment: .leading)
                                TextField("100", value: $clipboardHistorySize, formatter: NumberFormatter())
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            HStack {
                                Text("Max Images:")
                                    .font(.caption)
                                    .frame(width: 90, alignment: .leading)
                                TextField("50", value: $clipboardMaxImages, formatter: NumberFormatter())
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            HStack {
                                Text("List Limit (KB):")
                                    .font(.caption)
                                    .frame(width: 90, alignment: .leading)
                                TextField("10", value: $clipboardItemSizeLimitKB, formatter: NumberFormatter())
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            HStack {
                                Text("Full Limit (MB):")
                                    .font(.caption)
                                    .frame(width: 90, alignment: .leading)
                                TextField("5", value: $clipboardLargeItemSizeLimitMB, formatter: NumberFormatter())
                                    .frame(width: 80)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                            
                            // Statistics Section
                            if let s = stats {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Current Usage Stats:")
                                        .font(.caption)
                                        .bold()
                                    
                                    HStack {
                                        Text("Items: \(s.totalItems)")
                                        Spacer()
                                        Text("Index File: \(formatBytes(s.historyDiskSizeBytes))")
                                    }
                                    .font(.caption)
                                    
                                    HStack {
                                        Text("Images: \(s.imageCount) (\(formatBytes(s.imageContentSizeBytes)))")
                                        Spacer()
                                        Text("Blobs File: \(formatBytes(s.blobsDiskSizeBytes))")
                                    }
                                    .font(.caption)
                                    
                                    HStack {
                                        Text("Big Blobs: \(s.textBlobCount) (\(formatBytes(s.textBlobContentSizeBytes)))")
                                        Spacer()
                                    }
                                    .font(.caption)
                                }
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                            }
                            
                            HStack(spacing: 12) {
                                Button("Clear History") {
                                    NSApp.sendAction(#selector(AppDelegate.clearClipboardHistory), to: nil, from: nil)
                                }
                                .controlSize(.small)
                                
                                Button("Remove Duplicates") {
                                    clipboardStore.removeDuplicates()
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.leading, 10)
                }
            }
            .padding()
        }
        .onAppear {
            editorBridge.refreshEditors()
            stats = clipboardStore.getStats()
        }
        .onChange(of: clipboardStore.history.count) { _ in
            stats = clipboardStore.getStats()
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: bytes)
    }
}

struct TerminalSettingsTab: View {
    @AppStorage(AppConfig.Keys.targetTerminalBundleID) private var targetTerminalBundleID = "com.apple.Terminal"
    @AppStorage(AppConfig.Keys.commandPrefix) private var commandPrefix = ""
    @AppStorage(AppConfig.Keys.commandSuffix) private var commandSuffix = ""
    @AppStorage(AppConfig.Keys.changeTerminalName) private var changeTerminalName = true
    @AppStorage(AppConfig.Keys.terminalTabNameCommand) private var terminalTabNameCommand = "( ( sleep 2 ; printf '\\e]1;%s\\a' '$PROFILE_NAME' ) 2>/dev/null & ) 2>/dev/null ; clear ; "
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Target Terminal:")
                        .font(.caption)
                    Picker("", selection: $targetTerminalBundleID) {
                        Text("Apple Terminal").tag("com.apple.Terminal")
                        Text("iTerm2").tag("com.googlecode.iterm2")
                        Text("Ghostty").tag("com.mitchellh.ghostty")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefix:")
                            .font(.caption)
                        TextField("e.g. unset HISTFILE", text: $commandPrefix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suffix:")
                            .font(.caption)
                        TextField("e.g. && exit", text: $commandSuffix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Set Terminal Tab Name", isOn: $changeTerminalName)
                    
                    if changeTerminalName {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tab Name Command:")
                                .font(.caption)
                            TextField("e.g. printf '\\e]1;%s\\a' '$PROFILE_NAME'", text: $terminalTabNameCommand)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            .padding()
        }
    }
}

struct AdvancedSettingsTab: View {
    @AppStorage(AppConfig.Keys.hideCommandInList) private var hideCommandInList = true
    @AppStorage(AppConfig.Keys.smartFilter) private var smartFilter = true
    @AppStorage(AppConfig.Keys.snapToTerminal) private var snapToTerminal = false
    @AppStorage(AppConfig.Keys.copyOnSelect) private var copyOnSelect = true
    @AppStorage(AppConfig.Keys.pasteOnRightClick) private var pasteOnRightClick = true
    @AppStorage(AppConfig.Keys.debugMode) private var debugMode = false
    
    @State private var runOnStartup: Bool = LaunchAtLoginManager.isEnabled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior")
                        .font(.headline)
                    
                    Toggle("Hide Command in List", isOn: $hideCommandInList)
                    Toggle("Smart Search (Multi-word)", isOn: $smartFilter)
                    Toggle("Snap to Terminal (Left Side)", isOn: $snapToTerminal)
                        .onChange(of: snapToTerminal) { newValue in
                            NSApp.sendAction(#selector(AppDelegate.refreshTerminalObserverState), to: nil, from: nil)
                        }
                    Toggle("Copy on Select", isOn: $copyOnSelect)
                    Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("System")
                        .font(.headline)
                    
                    Toggle("Run on Startup", isOn: $runOnStartup)
                        .onChange(of: runOnStartup) { newValue in 
                            LaunchAtLoginManager.setEnabled(newValue) 
                        }
                    
                    Toggle("Debug Mode", isOn: $debugMode)
                }
            }
            .padding()
        }
    }
}