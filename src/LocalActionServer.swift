import Foundation
import Network
import Cocoa

class LocalActionServer {
    static let shared = LocalActionServer()
    private var listener: NWListener?
    
    func start() {
        do {
            guard let port = NWEndpoint.Port(rawValue: 61234) else { return }
            let parameters = NWParameters.udp
            
            listener = try NWListener(using: parameters, on: port)
            
            listener?.newConnectionHandler = { connection in
                connection.start(queue: .main)
                self.receive(on: connection)
            }
            
            listener?.start(queue: .global(qos: .background))
            if UserDefaults.standard.bool(forKey: AppConfig.Keys.debugMode) {
                print("DEBUG: [LocalActionServer] Started on UDP 127.0.0.1:61234")
            }
        } catch {
            print("DEBUG: [LocalActionServer] Failed to start: \(error)")
        }
    }
    
    private func receive(on connection: NWConnection) {
        connection.receiveMessage { data, context, isComplete, error in
            if let data = data, let message = String(data: data, encoding: .utf8) {
                self.handleMessage(message)
            }
            connection.cancel()
        }
    }
    
    private func handleMessage(_ message: String) {
        DispatchQueue.main.async {
            let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch msg {
            case "fineterm/next-group": WindowCycleService.executeCycle(isNext: true, isPrev: false, isToggle: false)
            case "fineterm/prev-group": WindowCycleService.executeCycle(isNext: false, isPrev: true, isToggle: false)
            case "fineterm/toggle-group": WindowCycleService.executeCycle(isNext: false, isPrev: false, isToggle: true)
            case "fineterm/clipboard": if let d = NSApp.delegate as? AppDelegate { d.toggleClipboardWindow() }
            case "fineterm/library-add": if let d = NSApp.delegate as? AppDelegate { d.showLibraryAddWindow() }
            case "fineterm/library-open": if let d = NSApp.delegate as? AppDelegate { d.toggleLibraryWindow() }
            case "fineterm/terminal-toggle": WindowCycleService.handleTerminalToggle()
            case "fineterm/main-toggle": WindowCycleService.handleMainToggle()
            case "fineterm/lang-switch": LangSwitchService.shared.switchKeyboardLanguage()
            case "fineterm/type-clipboard":
                if let string = NSPasteboard.general.string(forType: .string) {
                    // Set a brisk 10ms delay for smooth typing via fast macro server
                    KeyboardEventInjector.typeText(string, delayMs: 10)
                }
            default:
                if msg.hasPrefix("fineterm/custom-shortcut?id=") {
                    let idStr = msg.replacingOccurrences(of: "fineterm/custom-shortcut?id=", with: "")
                    if let id = UUID(uuidString: idStr) { WindowCycleService.executeCustomShortcut(by: id) }
                } else if msg.hasPrefix("fineterm/type-text?b64=") {
                    let b64 = msg.replacingOccurrences(of: "fineterm/type-text?b64=", with: "")
                    if let data = Data(base64Encoded: b64), let text = String(data: data, encoding: .utf8) {
                        KeyboardEventInjector.typeText(text, delayMs: 10)
                    }
                }
            }
        }
    }
}