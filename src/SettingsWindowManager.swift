import Cocoa
import SwiftUI

class SettingsWindow: NSWindow {
    private var localMonitor: Any?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        self.localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow else { return event }
            
            if event.keyCode == 53 { // Esc
                self.close()
                return nil // Swallow event
            }
            return event
        }
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    
    override var canBecomeKey: Bool {
        return true
    }
}

class SettingsWindowManager: NSObject, NSWindowDelegate {
    private var window: SettingsWindow?
    private var clipboardStore: ClipboardStore!
    private var libraryStore: LibraryStore!
    
    init(store: ClipboardStore, libraryStore: LibraryStore) {
        self.clipboardStore = store
        self.libraryStore = libraryStore
        super.init()
    }
    
    func open() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newWindow = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Settings"
        // Keep deterministic memory control. Do not let AppKit auto-release it.
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.setFrameAutosaveName("Settings Window")
        newWindow.delegate = self
        
        let settingsView = SettingsView(clipboardStore: clipboardStore, libraryStore: libraryStore)
        
        newWindow.contentView = NSHostingView(rootView: settingsView)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
    }
    
    func windowWillClose(_ notification: Notification) {
        // CRITICAL FIX: Defer the teardown to the next RunLoop cycle.
        // Synchronously modifying the contentView during windowWillClose crashes the 
        // AppKit/SwiftUI bridging engine because the window is still traversing its responder chain.
        DispatchQueue.main.async { [weak self] in
            // Destroy the view tree and drop the reference to free up the heavy memory footprint
            self?.window?.contentView = nil
            self?.window = nil
            
            // Clear the 16x16 icon cache and App List
            AppListService.shared.clearCache()
        }
    }
}