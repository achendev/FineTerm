import SwiftUI

enum SettingsTab: String, CaseIterable {
    case connections = "Connections"
    case apps = "Apps"
    case clipboard = "Clipboard"
    case terminal = "Terminal"
    case advanced = "Advanced"
}

struct SettingsView: View {
    @ObservedObject var clipboardStore: ClipboardStore
    @State private var selectedTab: SettingsTab = .connections

    var body: some View {
        VStack(spacing: 0) {
            // In-window Tab Navigation
            Picker("", selection: $selectedTab) {
                Text("Connections").tag(SettingsTab.connections)
                Text("Apps").tag(SettingsTab.apps)
                Text("Clipboard").tag(SettingsTab.clipboard)
                Text("Terminal").tag(SettingsTab.terminal)
                Text("Advanced").tag(SettingsTab.advanced)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .onChange(of: selectedTab) { tab in
                // Only refresh the heavy app list when actually switching to the Apps tab
                if tab == .apps {
                    AppListService.shared.loadApps(forceReload: true)
                }
            }
            
            Divider()
            
            // Tab Content
            Group {
                switch selectedTab {
                case .connections:
                    ConnectionsSettingsTab()
                case .apps:
                    AppShortcutsSettingsTab()
                case .clipboard:
                    ClipboardSettingsTab(clipboardStore: clipboardStore)
                case .terminal:
                    TerminalSettingsTab()
                case .advanced:
                    AdvancedSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 500, minHeight: 450)
    }
}

// ---------------------------------------------------------
// App Shortcuts Setting Tab (Optimized for performance)
// ---------------------------------------------------------

// Isolated Picker View: Prevents the parent view from redrawing the entire 300+ item list during the selection animation
struct AppSelectorView: View {
    @Binding var selection: String
    let availableApps: [EditorApp]
    let onChange: () -> Void
    
    var body: some View {
        Picker("", selection: Binding(
            get: { selection },
            set: { val in
                selection = val
                // CRITICAL FIX FOR LAG: Defer the parent state update by a tiny fraction of a second.
                // This allows the native macOS dropdown menu to snap shut instantly without being 
                // blocked by SwiftUI trying to recalculate the view hierarchy.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onChange()
                }
            }
        )) {
            Text("Select an App...").tag("")
            Divider()
            ForEach(availableApps) { app in
                Text(app.name).tag(app.id)
            }
        }
        .labelsHidden()
    }
}

struct ShortcutRowView: View {
    @State private var localShortcut: CustomAppShortcut
    let availableApps: [EditorApp]
    let onChange: (CustomAppShortcut) -> Void
    let onDelete: () -> Void
    
    init(shortcut: CustomAppShortcut, availableApps: [EditorApp], onChange: @escaping (CustomAppShortcut) -> Void, onDelete: @escaping () -> Void) {
        self._localShortcut = State(initialValue: shortcut)
        self.availableApps = availableApps
        self.onChange = onChange
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Shortcut Key + Group Controls
            HStack {
                Picker("", selection: Binding(
                    get: { localShortcut.modifier },
                    set: { val in
                        localShortcut.modifier = val
                        triggerChange()
                    }
                )) {
                    Text("Command").tag("command")
                    Text("Control").tag("control")
                    Text("Option").tag("option")
                }
                .frame(width: 100)
                .labelsHidden()
                
                Text("+")
                
                TextField("Key", text: Binding(
                    get: { localShortcut.key },
                    set: { val in
                        let formatted = String(val.prefix(1)).lowercased()
                        if formatted != localShortcut.key {
                            localShortcut.key = formatted
                            triggerChange()
                        }
                    }
                ))
                .frame(width: 40)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Spacer()
                
                // Add app to this shortcut group
                Button(action: {
                    localShortcut.bundleIDs.append("")
                    triggerChange()
                }) {
                    Image(systemName: "plus.app")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Add another app to cycle with this shortcut")
                
                // Delete entire shortcut group
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete this shortcut entirely")
            }
            
            // App Selectors
            VStack(spacing: 6) {
                ForEach(localShortcut.bundleIDs.indices, id: \.self) { index in
                    HStack {
                        // Use the optimized isolated picker
                        AppSelectorView(
                            selection: $localShortcut.bundleIDs[index],
                            availableApps: availableApps,
                            onChange: triggerChange
                        )
                        
                        // Allow removing individual app if there's more than one
                        if localShortcut.bundleIDs.count > 1 {
                            Button(action: {
                                localShortcut.bundleIDs.remove(at: index)
                                triggerChange()
                            }) {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this app from the cycle")
                        }
                    }
                }
            }
            .padding(.leading, 10)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    private func triggerChange() {
        DispatchQueue.main.async {
            onChange(localShortcut)
        }
    }
}

struct AppShortcutsSettingsTab: View {
    @AppStorage(AppConfig.Keys.customAppShortcuts) private var shortcutsData: Data = AppConfig.customAppShortcutsData
    @State private var shortcuts: [CustomAppShortcut] = []
    @StateObject private var appListService = AppListService.shared
    
    // Throttler for saving
    @State private var saveTask: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom App Shortcuts")
                        .font(.headline)
                    Text("Bind global shortcuts to switch to any application instantly. Add multiple apps to cycle between them.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    // Extracting the row heavily isolates state and fixes Picker lag
                    ForEach(shortcuts) { shortcut in
                        ShortcutRowView(
                            shortcut: shortcut,
                            availableApps: appListService.availableApps,
                            onChange: { updatedShortcut in
                                if let idx = shortcuts.firstIndex(where: { $0.id == updatedShortcut.id }) {
                                    shortcuts[idx] = updatedShortcut
                                    saveThrottled()
                                }
                            },
                            onDelete: {
                                shortcuts.removeAll { $0.id == shortcut.id }
                                saveThrottled()
                            }
                        )
                    }
                }
                
                Button(action: {
                    shortcuts.append(CustomAppShortcut(key: "", modifier: "command", bundleIDs: [""]))
                    saveThrottled()
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add New Shortcut")
                    }
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .onAppear {
            load()
            // Just request a soft load on appear in case it wasn't triggered by the tab switch
            appListService.loadApps(forceReload: false)
        }
    }
    
    private func load() {
        if let decoded = try? JSONDecoder().decode([CustomAppShortcut].self, from: shortcutsData) {
            shortcuts = decoded
        }
    }
    
    private func saveThrottled() {
        saveTask?.cancel()
        
        // Copy the array to avoid thread-safety issues during encoding
        let currentShortcuts = self.shortcuts
        
        let task = DispatchWorkItem {
            // Perform heavy JSON Serialization strictly on the background thread
            if let encoded = try? JSONEncoder().encode(currentShortcuts) {
                DispatchQueue.main.async {
                    // Only jump back to main thread to assign the value (which triggers UserDefaults write)
                    self.shortcutsData = encoded
                }
            }
        }
        saveTask = task
        // Execute background serialization after 300ms debounce
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}

// ---------------------------------------------------------
// Other Setting Tabs
// ---------------------------------------------------------

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
                    Toggle("Set Terminal Tab Name Globally", isOn: $changeTerminalName)
                    
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