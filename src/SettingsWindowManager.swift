import Cocoa
import SwiftUI

class SettingsWindow: NSWindow {
    // Callback for Esc
    private var localMonitor: Any?

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        
        // Intercept Esc (53) locally for this window
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
    
    func open() {
        if let win = window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newWindow = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 650),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Settings"
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.setFrameAutosaveName("Settings Window")
        newWindow.delegate = self
        
        let settingsView = SettingsView()
        
        newWindow.contentView = NSHostingView(rootView: settingsView)
        
        self.window = newWindow
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        window?.close()
    }
    
    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
