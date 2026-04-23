import Foundation
import Cocoa

class AppListService: ObservableObject {
    static let shared = AppListService()
    @Published var availableApps: [EditorApp] = []
    
    private var isLoaded = false
    private let scanQueue = DispatchQueue(label: "com.fineterm.appscan", qos: .userInitiated)
    
    // Explicit 16x16 icon cache to strip multi-megabyte NSImage representations
    private var iconCache: [String: NSImage] = [:]
    
    func loadApps(forceReload: Bool = false) {
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
            
            let homeApps = fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            directories.append(homeApps)
            
            if let subdirs = try? fm.contentsOfDirectory(at: homeApps, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for subdir in subdirs {
                    var isDir: ObjCBool = false
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
    
    func getIcon(for app: EditorApp) -> NSImage? {
        if let cached = iconCache[app.id] { return cached }
        
        let rawIcon = NSWorkspace.shared.icon(forFile: app.url.path)
        let smallSize = NSSize(width: 16, height: 16)
        let smallIcon = NSImage(size: smallSize)
        
        // Rasterize to explicit small bitmap to permanently dump the huge .icns payload
        smallIcon.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        rawIcon.draw(in: NSRect(origin: .zero, size: smallSize), from: NSRect(origin: .zero, size: rawIcon.size), operation: .sourceOver, fraction: 1.0)
        smallIcon.unlockFocus()
        
        iconCache[app.id] = smallIcon
        return smallIcon
    }
    
    func clearCache() {
        DispatchQueue.main.async {
            self.availableApps = []
            self.iconCache.removeAll()
            self.isLoaded = false
        }
    }
}