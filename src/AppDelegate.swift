import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var mouseInterceptor: MouseInterceptor?
    var keyboardInterceptor: KeyboardInterceptor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 0. Register Default Settings
        UserDefaults.standard.register(defaults: [
            "copyOnSelect": true,
            "pasteOnRightClick": true,
            "debugMode": false,
            // Default Wrappers
            "commandPrefix": "unset HISTFILE ; clear ; ",
            "commandSuffix": " && exit",
            // UI Defaults
            "hideCommandInList": true,
            "smartFilter": true,
            // Global Shortcut
            "globalShortcutKey": "n",
            "globalShortcutModifier": "command",
            "globalShortcutAnywhere": false
        ])

        // 1. Setup Main Menu (Crucial for Cmd+C, Cmd+V, Cmd+A in TextFields)
        setupMainMenu()

        // 2. CRITICAL: Force the app to be a regular "Foreground" app so it can accept keyboard input
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "NativeTab"
        
        checkPermissionsAndStart()
    }

    func checkPermissionsAndStart() {
        if PermissionManager.checkAccessibility() {
            startMainApp()
        } else {
            showPermissionOverlay()
        }
    }

    func showPermissionOverlay() {
        let permissionView = PermissionView { [weak self] in
            self?.startMainApp()
        }
        window.contentView = NSHostingView(rootView: permissionView)
        window.styleMask = [.titled, .closable] // Simplify style for permission check
        // Resize window to fit permission view
        window.setContentSize(NSSize(width: 380, height: 320))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func startMainApp() {
        // Restore standard style and size
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 320, height: 500))
        window.center()
        
        let contentView = ConnectionListView()
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Start Interceptors
        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.start()
        
        keyboardInterceptor = KeyboardInterceptor()
        keyboardInterceptor?.start()
        
        print("NativeTab Started")
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mouseInterceptor?.stop()
        keyboardInterceptor?.stop()
    }
    
    // Manually create the Menu Bar. 
    // This is required for pure Swift apps without XIBs to support standard text editing shortcuts.
    func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. App Menu (NativeTab)
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        
        appMenu.addItem(withTitle: "About NativeTab", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit NativeTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // 2. Edit Menu (Cut, Copy, Paste, Select All)
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = NSMenu(title: "Edit")
        mainMenu.addItem(editMenuItem)
        let editMenu = editMenuItem.submenu!

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        NSApp.mainMenu = mainMenu
    }
}
