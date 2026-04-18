import SwiftUI
import Cocoa

struct NativeAppPicker: NSViewRepresentable {
    @Binding var selection: String
    var apps: [EditorApp]
    
    func makeNSView(context: Context) -> NSPopUpButton {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.target = context.coordinator
        popUp.action = #selector(Coordinator.selectionChanged(_:))
        popUp.isBordered = true
        popUp.autoenablesItems = false
        popUp.focusRingType = .none
        return popUp
    }
    
    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        if nsView.itemArray.count != apps.count + 2 {
            nsView.removeAllItems()
            
            let defaultItem = NSMenuItem(title: "Select an App...", action: nil, keyEquivalent: "")
            defaultItem.representedObject = ""
            nsView.menu?.addItem(defaultItem)
            nsView.menu?.addItem(NSMenuItem.separator())
            
            for app in apps {
                let item = NSMenuItem(title: app.name, action: nil, keyEquivalent: "")
                item.representedObject = app.id
                let icon = NSWorkspace.shared.icon(forFile: app.url.path)
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
                nsView.menu?.addItem(item)
            }
        }
        
        if let index = nsView.itemArray.firstIndex(where: { ($0.representedObject as? String) == selection }) {
            if nsView.indexOfSelectedItem != index {
                nsView.selectItem(at: index)
            }
        } else {
            nsView.selectItem(at: 0)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: NativeAppPicker
        init(_ parent: NativeAppPicker) { self.parent = parent }
        
        @objc func selectionChanged(_ sender: NSPopUpButton) {
            if let selectedID = sender.selectedItem?.representedObject as? String {
                parent.selection = selectedID
            }
        }
    }
}