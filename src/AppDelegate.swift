import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var mouseInterceptor: MouseInterceptor?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 0. Register Default Settings
        UserDefaults.standard.register(defaults: [
            "copyOnSelect": true,
            "pasteOnRightClick": true,
            "debugMode": false
        ])

        // 1. CRITICAL: Force the app to be a regular "Foreground" app so it can accept keyboard input
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
        window.title = "MTTerminal Wrapper"
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        // Keep window floating above others
        window.level = .floating

        // Start the mouse hook
        mouseInterceptor = MouseInterceptor()
        mouseInterceptor?.start()
        
        print("MTTerminal Wrapper Started")
        
        // Request Accessibility permissions check
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if accessEnabled {
            print("SUCCESS: Accessibility permissions are active.")
        } else {
            print("ERROR: Accessibility permissions NOT granted.")
            print("       1. Open System Settings -> Privacy & Security -> Accessibility")
            print("       2. Remove any old entries for 'MTTerminalWrapper'")
            print("       3. Drag the new ./bin/MTTerminalWrapper executable into the list")
            print("       4. Restart this app")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        mouseInterceptor?.stop()
    }
}
