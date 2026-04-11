import SwiftUI

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