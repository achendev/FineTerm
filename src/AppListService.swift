import Foundation
import Cocoa

class AppListService: ObservableObject {
    static let shared = AppListService()
    // Reuses EditorApp struct which has id (bundleID), name, and url
    @Published var availableApps: [EditorApp] = []
    
    private var isLoaded = false
    private let scanQueue = DispatchQueue(label: "com.fineterm.appscan", qos: .userInitiated)
    
    func loadApps(forceReload: Bool = false) {
        // If already loaded and we aren't forcing a reload, skip.
        if isLoaded && !forceReload { return }
        isLoaded = true
        
        scanQueue.async {
            var apps: [EditorApp] = []
            let fm = FileManager.default
            
            var directories = [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                URL(fileURLWithPath: "/System/Applications/Utilities"),
                URL(fileURLWithPath: "/Applications/Utilities")
            ]
            
            // Add user's personal Applications folder
            let homeApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            directories.append(homeApps)
            
            // Scan immediate subdirectories of ~/Applications to find PWA folders 
            // (e.g. "Chrome Apps.localized", "Edge Apps.localized")
            if let subdirs = try? fm.contentsOfDirectory(at: homeApps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for subdir in subdirs {
                    var isDir: ObjCBool = false
                    // If it's a directory and NOT an app itself, add it to our scan list
                    if fm.fileExists(atPath: subdir.path, isDirectory: &isDir), isDir.boolValue, subdir.pathExtension != "app" {
                        directories.append(subdir)
                    }
                }
            }
            
            var seenBundleIDs = Set<String>()
            
            for dir in directories {
                if let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                    for url in contents {
                        if url.pathExtension == "app" {
                            if let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier {
                                if !seenBundleIDs.contains(bundleID) {
                                    seenBundleIDs.insert(bundleID)
                                    let name = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                                    apps.append(EditorApp(id: bundleID, name: name, url: url))
                                }
                            }
                        }
                    }
                }
            }
            
            let sortedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                self.availableApps = sortedApps
            }
        }
    }
}