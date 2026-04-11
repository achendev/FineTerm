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
    @Binding var triggers: [ShortcutTrigger]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<triggers.count, id: \.self) { index in
                HStack(spacing: 6) {
                    if index == 0 {
                        Toggle("", isOn: $isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .frame(width: 38, alignment: .leading)
                            .help("Enable this global group navigation shortcut")
                        
                        Button(action: { triggers.append(ShortcutTrigger(key: "", modifier: "command")) }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                        
                        Text(title)
                            .frame(width: 85, alignment: .leading)
                            .font(.caption)
                    } else {
                        Spacer().frame(width: 38)
                        
                        Button(action: { triggers.remove(at: index) }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .frame(width: 16)
                        
                        Text("")
                            .frame(width: 85, alignment: .leading)
                    }
                    
                    Picker("", selection: $triggers[index].modifier) {
                        ModifierPickerContent()
                    }
                    .frame(width: 120).labelsHidden()
                    
                    Text("+")
                    
                    Picker("", selection: Binding(
                        get: { triggers[index].modifier2 ?? "none" },
                        set: { val in triggers[index].modifier2 = (val == "none" ? nil : val) }
                    )) {
                        ModifierPickerContent(includeNone: true, includeKeys: true)
                    }
                    .frame(width: 120).labelsHidden()

                    Text("+")
                    
                    TextField("Key", text: Binding(
                        get: { triggers[index].key },
                        set: { val in triggers[index].key = String(val.prefix(10)).lowercased() }
                    ))
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }
}

struct ShortcutRowView: View {
    @Binding var shortcut: CustomAppShortcut
    let availableApps: [EditorApp]
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<shortcut.triggers.count, id: \.self) { index in
                        HStack(spacing: 6) {
                            if index == 0 {
                                Toggle("", isOn: $shortcut.isEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .frame(width: 38, alignment: .leading)
                                    .help("Enable or disable this shortcut group")
                                    
                                Button(action: { shortcut.triggers.append(ShortcutTrigger(key: "", modifier: "command")) }) {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.accentColor)
                                .frame(width: 16)
                            } else {
                                Spacer().frame(width: 38)
                                
                                Button(action: { shortcut.triggers.remove(at: index) }) {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                                .frame(width: 16)
                            }
                            
                            Picker("", selection: $shortcut.triggers[index].modifier) {
                                ModifierPickerContent()
                            }
                            .frame(width: 120)
                            .labelsHidden()
                            
                            Text("+")
                            
                            Picker("", selection: Binding(
                                get: { shortcut.triggers[index].modifier2 ?? "none" },
                                set: { val in shortcut.triggers[index].modifier2 = (val == "none" ? nil : val) }
                            )) {
                                ModifierPickerContent(includeNone: true, includeKeys: true)
                            }
                            .frame(width: 120)
                            .labelsHidden()

                            Text("+")
                            
                            TextField("Key", text: Binding(
                                get: { shortcut.triggers[index].key },
                                set: { val in shortcut.triggers[index].key = String(val.prefix(10)).lowercased() }
                            ))
                            .frame(width: 50)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack {
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
                }
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
    @AppStorage(AppConfig.Keys.nextGroupTriggers) private var nextGroupTriggersData: Data = Data()
    @State private var nextTriggers: [ShortcutTrigger] = []

    @AppStorage(AppConfig.Keys.enablePrevGroupShortcut) private var enablePrev = false
    @AppStorage(AppConfig.Keys.prevGroupTriggers) private var prevGroupTriggersData: Data = Data()
    @State private var prevTriggers: [ShortcutTrigger] = []

    @AppStorage(AppConfig.Keys.enableToggleGroupShortcut) private var enableToggle = false
    @AppStorage(AppConfig.Keys.toggleGroupTriggers) private var toggleGroupTriggersData: Data = Data()
    @State private var toggleTriggers: [ShortcutTrigger] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Group Navigation Shortcuts").font(.headline)
                    Text("Navigate between your shortcut groups without using their specific hotkeys.").font(.caption).foregroundColor(.secondary)

                    GroupNavRow(title: "Next Group", isEnabled: $enableNext, triggers: $nextTriggers)
                    GroupNavRow(title: "Prev Group", isEnabled: $enablePrev, triggers: $prevTriggers)
                    GroupNavRow(title: "Toggle Current", isEnabled: $enableToggle, triggers: $toggleTriggers)
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
                    shortcuts.append(CustomAppShortcut(triggers: [ShortcutTrigger(key: "", modifier: "command")], bundleIDs: [""]))
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add New Bind")
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
        .onChange(of: nextTriggers) { val in if let d = try? JSONEncoder().encode(val) { nextGroupTriggersData = d } }
        .onChange(of: prevTriggers) { val in if let d = try? JSONEncoder().encode(val) { prevGroupTriggersData = d } }
        .onChange(of: toggleTriggers) { val in if let d = try? JSONEncoder().encode(val) { toggleGroupTriggersData = d } }
    }
    
    private func load() {
        if let decoded = try? JSONDecoder().decode([CustomAppShortcut].self, from: shortcutsData) {
            shortcuts = decoded
        }
        nextTriggers = loadGroupTriggers(data: nextGroupTriggersData, mod1Key: AppConfig.Keys.nextGroupModifier, mod2Key: AppConfig.Keys.nextGroupModifier2, keyKey: AppConfig.Keys.nextGroupKey, defKey: ".")
        prevTriggers = loadGroupTriggers(data: prevGroupTriggersData, mod1Key: AppConfig.Keys.prevGroupModifier, mod2Key: AppConfig.Keys.prevGroupModifier2, keyKey: AppConfig.Keys.prevGroupKey, defKey: ",")
        toggleTriggers = loadGroupTriggers(data: toggleGroupTriggersData, mod1Key: AppConfig.Keys.toggleGroupModifier, mod2Key: AppConfig.Keys.toggleGroupModifier2, keyKey: AppConfig.Keys.toggleGroupKey, defKey: "/")
    }
    
    private func loadGroupTriggers(data: Data, mod1Key: String, mod2Key: String, keyKey: String, defKey: String) -> [ShortcutTrigger] {
        if let decoded = try? JSONDecoder().decode([ShortcutTrigger].self, from: data), !decoded.isEmpty {
            return decoded
        }
        // Fallback to old scalar keys migration
        let m1 = UserDefaults.standard.string(forKey: mod1Key) ?? "right control"
        let m2 = UserDefaults.standard.string(forKey: mod2Key) ?? "shift"
        let k = UserDefaults.standard.string(forKey: keyKey) ?? defKey
        return[ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
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