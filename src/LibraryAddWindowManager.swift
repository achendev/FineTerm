import Cocoa
import SwiftUI

class LibraryAddWindowManager: NSObject, NSWindowDelegate {
    private var window: ClipboardWindow!
    private var store: LibraryStore
    private var previousApp: NSRunningApplication?
    
    init(store: LibraryStore) {
        self.store = store
        super.init()
        setupWindow()
    }
    
    private func setupWindow() {
        window = ClipboardWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add to Library"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        window.onEsc = { [weak self] in self?.close() }
    }
    
    func show() {
        if let currentApp = NSWorkspace.shared.frontmostApplication {
            if currentApp.bundleIdentifier != Bundle.main.bundleIdentifier {
                previousApp = currentApp
            }
        }
        
        let contentView = LibraryAddView(store: store) { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: contentView)
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func close() {
        guard window.isVisible else { return }
        window.orderOut(nil)
        
        // TEAR DOWN VIEW - Fixes SwiftUI memory/observer leaks in the background
        window.contentView = nil
        
        if let prev = previousApp, !prev.isTerminated {
            prev.activate(options: [])
            previousApp = nil
        } else {
            let hasVisibleMainWindow = NSApp.windows.contains { $0 !== window && $0.isVisible && !$0.isMiniaturized }
            if !hasVisibleMainWindow { NSApp.hide(nil) }
        }
    }
    
    func windowDidResignKey(_ notification: Notification) {
        if let win = notification.object as? NSWindow, win === window {
            DispatchQueue.main.async { if self.window.isVisible { self.close() } }
        }
    }
}