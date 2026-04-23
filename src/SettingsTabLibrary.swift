import SwiftUI

struct LibrarySettingsTab: View {
    @ObservedObject var libraryStore: LibraryStore
    
    @AppStorage(AppConfig.Keys.enableLibraryManager) private var enableLibraryManager = false
    @AppStorage(AppConfig.Keys.libraryAddShortcutKey) private var libraryAddShortcutKey = "n"
    @AppStorage(AppConfig.Keys.libraryAddShortcutModifier) private var libraryAddShortcutModifier = "option"
    @AppStorage(AppConfig.Keys.libraryOpenShortcutKey) private var libraryOpenShortcutKey = "m"
    @AppStorage(AppConfig.Keys.libraryOpenShortcutModifier) private var libraryOpenShortcutModifier = "option"

    @State private var stats: LibraryStats?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Toggle("Enable Library Manager", isOn: $enableLibraryManager)
                
                if enableLibraryManager {
                    VStack(alignment: .leading, spacing: 16) {
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Add to Library Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Picker("", selection: $libraryAddShortcutModifier) {
                                    ModifierPickerContent()
                                }
                                .frame(width: 120)
                                .labelsHidden()
                                
                                Text("+")
                                
                                TextField("Key", text: $libraryAddShortcutKey)
                                    .frame(width: 40)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Open Library Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Picker("", selection: $libraryOpenShortcutModifier) {
                                    ModifierPickerContent()
                                }
                                .frame(width: 120)
                                .labelsHidden()
                                
                                Text("+")
                                
                                TextField("Key", text: $libraryOpenShortcutKey)
                                    .frame(width: 40)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        
                        Divider()
                        
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
                            Button("Clear Library") {
                                libraryStore.clear()
                            }
                            .controlSize(.small)
                        }
                    }
                    .padding(.leading, 10)
                }
            }
            .padding()
        }
        .onAppear {
            fetchStats()
        }
        .onChange(of: libraryStore.items.count) { _ in
            fetchStats()
        }
    }
    
    private func fetchStats() {
        DispatchQueue.global(qos: .userInitiated).async {
            let s = libraryStore.getStats()
            DispatchQueue.main.async { self.stats = s }
        }
    }
    
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useAll]
        return formatter.string(fromByteCount: bytes)
    }
}