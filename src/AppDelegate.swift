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
        
        // Create the connection manager window
        let contentView = ConnectionListView()
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.center()
        window.setFrameAutosaveName("Main Window")
        window.title = "NativeTab"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Start Interceptors
        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.start()
        
        keyboardInterceptor = KeyboardInterceptor()
        keyboardInterceptor?.start()
        
        print("NativeTab Started")
        
        // Request Accessibility permissions check
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            print("SUCCESS: Accessibility permissions are active.")
        } else {
            print("ERROR: Accessibility permissions NOT granted.")
            print("       1. Open System Settings -> Privacy & Security -> Accessibility")
            print("       2. Remove any old entries for 'NativeTab'")
            print("       3. Drag the new ./bin/NativeTab executable into the list")
            print("       4. Restart this app")
        }
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
