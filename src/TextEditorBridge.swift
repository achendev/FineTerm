import Cocoa
import Foundation
import UniformTypeIdentifiers

struct EditorApp: Identifiable, Hashable {
    let id: String // Bundle ID
    let name: String
    let url: URL
}

class TextEditorBridge: ObservableObject {
    static let shared = TextEditorBridge()
    
    @Published var availableEditors: [EditorApp] = []
    
    private init() {
        refreshEditors()
    }
    
    func warmUp() {
        // Trigger initialization
        refreshEditors()
    }
    
    func refreshEditors() {
        // Strategy: Ask the system which apps can open a plain text file.
        // This effectively finds TextEdit, Sublime, VSCode, Xcode, BBEdit, etc.
        let tempDir = FileManager.default.temporaryDirectory
        let dummyFile = tempDir.appendingPathComponent("scan_editors_dummy.txt")
        
        // Ensure dummy file exists for the check
        try? "test".write(to: dummyFile, atomically: true, encoding: .utf8)
        
        var apps: [EditorApp] = []
        
        // Use LSCopyApplicationURLsForURL equivalent in modern Swift
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: dummyFile)
        
        for url in urls {
            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                let name = FileManager.default.displayName(atPath: url.path)
                apps.append(EditorApp(id: bundleID, name: name, url: url))
            }
        }
        
        // Cleanup
        try? FileManager.default.removeItem(at: dummyFile)
        
        // Remove duplicates (sometimes system returns same app twice)
        let uniqueApps = Array(Set(apps)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        
        DispatchQueue.main.async {
            self.availableEditors = uniqueApps
            self.ensureDefaultSelection()
        }
    }
    
    private func ensureDefaultSelection() {
        let defaults = UserDefaults.standard
        let currentID = defaults.string(forKey: AppConfig.Keys.clipboardEditorBundleID)
        
        // If the current ID is set and exists in our list, we are good.
        if let currentID = currentID, availableEditors.contains(where: { $0.id == currentID }) {
            return
        }
        
        // Otherwise, try to find a "Best" default
        // Priority: Sublime -> VSCode -> TextEdit
        let preferred = ["com.sublimetext.4", "com.sublimetext.3", "com.microsoft.VSCode", "com.apple.TextEdit"]
        
        for prefID in preferred {
            if availableEditors.contains(where: { $0.id == prefID }) {
                defaults.set(prefID, forKey: AppConfig.Keys.clipboardEditorBundleID)
                return
            }
        }
        
        // Fallback to first available
        if let first = availableEditors.first {
            defaults.set(first.id, forKey: AppConfig.Keys.clipboardEditorBundleID)
        }
    }
    
    func open(content: String) {
        let defaults = UserDefaults.standard
        
        // 1. Get Settings
        let rawExt = defaults.string(forKey: AppConfig.Keys.clipboardTempExtension) ?? "sh"
        let ext = rawExt.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
        let targetBundleID = defaults.string(forKey: AppConfig.Keys.clipboardEditorBundleID) ?? "com.apple.TextEdit"
        
        let shouldAutoDelete = defaults.bool(forKey: AppConfig.Keys.clipboardAutoDeleteTempFile)
        let deleteDelay = defaults.double(forKey: AppConfig.Keys.clipboardAutoDeleteDelay)
        
        // 2. Prepare File
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.prefix(8)
        let fileName = "snippet_\(uuid).\(ext)"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // 3. Resolve App URL from Bundle ID
            let workspace = NSWorkspace.shared
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: targetBundleID) else {
                print("TextEditorBridge: Could not find app for bundle ID \(targetBundleID)")
                // Fallback to default open
                workspace.open(fileURL)
                return
            }
            
            // 4. Check if it is Sublime Text (for CLI optimization)
            let isSublime = targetBundleID.contains("sublimetext")
            
            if isSublime {
                // TRY SUBL CLI strategy
                let sublPath = appURL.appendingPathComponent("Contents/SharedSupport/bin/subl")
                if FileManager.default.fileExists(atPath: sublPath.path) {
                    let task = Process()
                    task.executableURL = sublPath
                    task.arguments = [fileURL.path]
                    
                    try task.run()
                    
                    if let runningApp = workspace.runningApplications.first(where: { $0.bundleURL == appURL }) {
                        runningApp.activate(options: .activateIgnoringOtherApps)
                    }
                    
                    if shouldAutoDelete {
                        cleanup(fileURL, delay: deleteDelay)
                    }
                    return
                }
            }
            
            // 5. Generic Open (VS Code, TextEdit, Xcode, etc)
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            
            workspace.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
                if let error = error {
                    print("TextEditorBridge: Open Error: \(error)")
                }
                
                if shouldAutoDelete {
                    // Use user delay, but ensure at least minimal time for app launch
                    let effectiveDelay = max(deleteDelay, 0.5)
                    self.cleanup(fileURL, delay: effectiveDelay)
                }
            }
            
        } catch {
            print("TextEditorBridge Error: \(error)")
        }
    }
    
    private func cleanup(_ url: URL, delay: TimeInterval) {
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + delay) {
            try? FileManager.default.removeItem(at: url)
            if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
                print("TextEditorBridge: Cleaned up \(url.lastPathComponent)")
            }
        }
    }
}