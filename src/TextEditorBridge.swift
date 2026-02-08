import Cocoa
import Foundation

class TextEditorBridge {
    static let shared = TextEditorBridge()
    
    private var editorAppURL: URL?
    private var isSublime = false
    
    private init() {
        detectEditor()
    }
    
    func warmUp() {
        // Cached on init
    }
    
    private func detectEditor() {
        let candidates = [
            "com.sublimetext.4",
            "com.sublimetext.3",
            "com.sublimetext.2",
            "com.sublimetext"
        ]
        
        let workspace = NSWorkspace.shared
        
        for id in candidates {
            if let url = workspace.urlForApplication(withBundleIdentifier: id) {
                print("TextEditorBridge: Detected Sublime Text at \(url.path)")
                editorAppURL = url
                isSublime = true
                return
            }
        }
        
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            print("TextEditorBridge: Fallback to TextEdit")
            editorAppURL = url
            isSublime = false
        }
    }
    
    func open(content: String) {
        // Strategy: Create a temporary .sh file to force Bash syntax highlighting.
        // Then, delete the file shortly after opening.
        // This causes the editor (Sublime) to treat it as an unsaved buffer (dirty state),
        // effectively mimicking an "Untitled" tab behavior (Cmd+S triggers Save As),
        // but with the correct syntax automatically applied.
        
        let tempDir = FileManager.default.temporaryDirectory
        let uuid = UUID().uuidString.prefix(8)
        let fileName = "snippet_\(uuid).sh"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // 1. Sublime Text CLI
            if isSublime, let appURL = editorAppURL {
                let sublPath = appURL.appendingPathComponent("Contents/SharedSupport/bin/subl")
                
                if FileManager.default.fileExists(atPath: sublPath.path) {
                    let task = Process()
                    task.executableURL = sublPath
                    task.arguments = [fileURL.path]
                    
                    do {
                        try task.run()
                        
                        // Activate App
                        if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleURL == appURL }) {
                            runningApp.activate(options: .activateIgnoringOtherApps)
                        }
                        
                        // CLEANUP: Delete the file after 2 seconds.
                        // This ensures we don't clutter the system, and Sublime handles deleted open files gracefully
                        // by treating them as dirty buffers requiring a "Save As".
                        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) {
                            try? FileManager.default.removeItem(at: fileURL)
                            if UserDefaults.standard.bool(forKey: "debugMode") {
                                print("TextEditorBridge: Cleanup temporary snippet file: \(fileURL.lastPathComponent)")
                            }
                        }
                        
                        return
                    } catch {
                        print("TextEditorBridge: Failed to run subl, falling back to NSWorkspace. Error: \(error)")
                    }
                }
            }
            
            // 2. Fallback (NSWorkspace)
            if let appURL = editorAppURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                
                NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config) { app, error in
                    if let error = error {
                        print("TextEditorBridge Error (NSWorkspace): \(error)")
                    }
                    // For fallback (TextEdit), we also clean up, but with a longer delay to ensure loading.
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 5.0) {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
                }
            } else {
                NSWorkspace.shared.open(fileURL)
            }
            
        } catch {
            print("TextEditorBridge Error: \(error)")
        }
    }
}