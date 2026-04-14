import SwiftUI
import UniformTypeIdentifiers

// FileDocument to handle native export operations
struct SettingsDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        return FileWrapper(regularFileWithContents: data)
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
    
    // Import/Export States
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var documentToExport: SettingsDocument?
    @State private var importSuccess = false
    @State private var importError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Profile & Settings")
                        .font(.headline)
                    
                    Text("Backup or restore your application preferences, custom PC mode rules, and app shortcuts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Button("Export Settings...") {
                            if let data = AppConfig.exportSettings() {
                                documentToExport = SettingsDocument(data: data)
                                isExporting = true
                            }
                        }
                        
                        Button("Import Settings...") {
                            isImporting = true
                        }
                    }
                }
                
                Divider()
                
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
        .fileExporter(isPresented: $isExporting, document: documentToExport, contentType: .json, defaultFilename: "fineterm_settings_profile") { _ in }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else { return }
                defer { url.stopAccessingSecurityScopedResource() }
                if let data = try? Data(contentsOf: url) {
                    if AppConfig.importSettings(from: data) {
                        SystemModifierManager.applyCurrentSettings()
                        importSuccess = true
                    } else {
                        importError = true
                    }
                } else {
                    importError = true
                }
            case .failure:
                importError = true
            }
        }
        .alert("Import Successful", isPresented: $importSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Your settings profile has been imported.")
        }
        .alert("Import Failed", isPresented: $importError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The selected file is invalid or corrupted.")
        }
    }
}