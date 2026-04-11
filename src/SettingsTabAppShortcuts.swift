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

struct GroupNavRow: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var modifier1: String
    @Binding var modifier2: String
    @Binding var key: String
    
    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Enable this global group navigation shortcut")
            
            Text(title)
                .frame(width: 95, alignment: .leading)
                .font(.caption)
            
            Picker("", selection: $modifier1) {
                ModifierPickerContent()
            }
            .frame(width: 120).labelsHidden()
            
            Text("+")
            
            Picker("", selection: $modifier2) {
                ModifierPickerContent(includeNone: true, includeKeys: true)
            }
            .frame(width: 120).labelsHidden()

            Text("+")
            
            TextField("Key", text: Binding(
                get: { key },
                set: { val in key = String(val.prefix(10)).lowercased() }
            ))
            .frame(width: 60)
            .textFieldStyle(RoundedBorderTextFieldStyle())
        }
    }
}

struct ShortcutRowView: View {
    @Binding var shortcut: CustomAppShortcut
    let availableApps: [EditorApp]
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle("", isOn: $shortcut.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Enable or disable this shortcut group")
                    
                Picker("", selection: $shortcut.modifier) {
                    ModifierPickerContent()
                }
                .frame(width: 120)
                .labelsHidden()
                
                Text("+")
                
                Picker("", selection: Binding(
                    get: { shortcut.modifier2 ?? "none" },
                    set: { val in shortcut.modifier2 = (val == "none" ? nil : val) }
                )) {
                    ModifierPickerContent(includeNone: true, includeKeys: true)
                }
                .frame(width: 120)
                .labelsHidden()

                Text("+")
                
                TextField("Key", text: Binding(
                    get: { shortcut.key },
                    set: { val in shortcut.key = String(val.prefix(10)).lowercased() }
                ))
                .frame(width: 50)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Spacer()
                
                Button(action: { shortcut.bundleIDs.append("") }) {
                    Image(systemName: "plus.app").foregroundColor(.accentColor)
                }
                .buttonStyle(.borderless)
                .help("Add another app to cycle with this shortcut")
                
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete this shortcut entirely")
            }
            
            VStack(spacing: 6) {
                ForEach(0..<shortcut.bundleIDs.count, id: \.self) { index in
                    HStack {
                        NativeAppPicker(
                            selection: Binding(
                                get: { index < shortcut.bundleIDs.count ? shortcut.bundleIDs[index] : "" },
                                set: { val in if index < shortcut.bundleIDs.count { shortcut.bundleIDs[index] = val } }
                            ),
                            apps: availableApps
                        )
                        .frame(height: 24)
                        
                        if shortcut.bundleIDs.count > 1 {
                            Button(action: { shortcut.bundleIDs.remove(at: index) }) {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove this app from the cycle")
                        }
                    }
                }
            }
            .padding(.leading, 10)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .opacity(shortcut.isEnabled ? 1.0 : 0.6)
    }
}

struct AppShortcutsSettingsTab: View {
    @AppStorage(AppConfig.Keys.customAppShortcuts) private var shortcutsData: Data = AppConfig.customAppShortcutsData
    @State private var shortcuts: [CustomAppShortcut] = []
    @StateObject private var appListService = AppListService.shared
    @State private var saveTask: DispatchWorkItem?

    @AppStorage(AppConfig.Keys.enableNextGroupShortcut) private var enableNext = false
    @AppStorage(AppConfig.Keys.nextGroupModifier) private var nextMod1 = "right control"
    @AppStorage(AppConfig.Keys.nextGroupModifier2) private var nextMod2 = "shift"
    @AppStorage(AppConfig.Keys.nextGroupKey) private var nextKey = "."

    @AppStorage(AppConfig.Keys.enablePrevGroupShortcut) private var enablePrev = false
    @AppStorage(AppConfig.Keys.prevGroupModifier) private var prevMod1 = "right control"
    @AppStorage(AppConfig.Keys.prevGroupModifier2) private var prevMod2 = "shift"
    @AppStorage(AppConfig.Keys.prevGroupKey) private var prevKey = ","

    @AppStorage(AppConfig.Keys.enableToggleGroupShortcut) private var enableToggle = false
    @AppStorage(AppConfig.Keys.toggleGroupModifier) private var toggleMod1 = "right control"
    @AppStorage(AppConfig.Keys.toggleGroupModifier2) private var toggleMod2 = "shift"
    @AppStorage(AppConfig.Keys.toggleGroupKey) private var toggleKey = "/"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Group Navigation Shortcuts").font(.headline)
                    Text("Navigate between your shortcut groups without using their specific hotkeys.").font(.caption).foregroundColor(.secondary)

                    GroupNavRow(title: "Next Group", isEnabled: $enableNext, modifier1: $nextMod1, modifier2: $nextMod2, key: $nextKey)
                    GroupNavRow(title: "Prev Group", isEnabled: $enablePrev, modifier1: $prevMod1, modifier2: $prevMod2, key: $prevKey)
                    GroupNavRow(title: "Toggle Current", isEnabled: $enableToggle, modifier1: $toggleMod1, modifier2: $toggleMod2, key: $toggleKey)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom App Shortcuts").font(.headline)
                    Text("Bind global shortcuts to switch to any application instantly.").font(.caption).foregroundColor(.secondary)
                }
                
                VStack(spacing: 16) {
                    ForEach($shortcuts) { $shortcut in
                        ShortcutRowView(
                            shortcut: $shortcut,
                            availableApps: appListService.availableApps,
                            onDelete: {
                                shortcuts.removeAll { $0.id == shortcut.id }
                            }
                        )
                    }
                }
                
                Button(action: {
                    shortcuts.append(CustomAppShortcut(key: "", modifier: "command", modifier2: nil, bundleIDs: [""]))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add New Shortcut")
                    }
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .onAppear {
            load()
            appListService.loadApps(forceReload: false)
        }
        .onChange(of: shortcuts) { newValue in
            saveThrottled(newValue)
        }
    }
    
    private func load() {
        if let decoded = try? JSONDecoder().decode([CustomAppShortcut].self, from: shortcutsData) {
            shortcuts = decoded
        }
    }
    
    private func saveThrottled(_ currentShortcuts: [CustomAppShortcut]) {
        saveTask?.cancel()
        let task = DispatchWorkItem {
            if let encoded = try? JSONEncoder().encode(currentShortcuts) {
                DispatchQueue.main.async {
                    self.shortcutsData = encoded
                }
            }
        }
        saveTask = task
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}