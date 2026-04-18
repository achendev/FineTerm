import SwiftUI
import Cocoa
import UniformTypeIdentifiers

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
    
    @AppStorage(AppConfig.Keys.skipNonRunningApps) private var skipNonRunningApps = false
    @AppStorage(AppConfig.Keys.skipNonRunningAppsMode) private var skipNonRunningAppsMode = 0
    
    @State private var draggedShortcut: CustomAppShortcut?

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
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Skip apps that are not running", isOn: $skipNonRunningApps)
                        if skipNonRunningApps {
                            HStack {
                                Text("Apply rule:").font(.caption).foregroundColor(.secondary)
                                Picker("", selection: $skipNonRunningAppsMode) {
                                    Text("When cycling multiple apps").tag(0)
                                    Text("For single-app shortcuts").tag(1)
                                    Text("Always (Both of the above)").tag(2)
                                }
                                .labelsHidden().fixedSize()
                            }
                            .padding(.leading, 20)
                        }
                    }
                    .padding(.top, 4)
                }
                
                VStack(spacing: 16) {
                    ForEach($shortcuts) { $shortcut in
                        let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) ?? 0
                        ShortcutRowView(
                            shortcut: $shortcut,
                            availableApps: appListService.availableApps,
                            canMoveUp: index > 0,
                            canMoveDown: index < shortcuts.count - 1,
                            onMoveUp: { if index > 0 { withAnimation { shortcuts.swapAt(index, index - 1) } } },
                            onMoveDown: { if index < shortcuts.count - 1 { withAnimation { shortcuts.swapAt(index, index + 1) } } },
                            onDelete: { withAnimation { shortcuts.removeAll { $0.id == shortcut.id } } }
                        )
                        .onDrag {
                            self.draggedShortcut = shortcut
                            return NSItemProvider(object: shortcut.id.uuidString as NSString)
                        }
                        .onDrop(of: [.text, .plainText], delegate: ShortcutDropDelegate(item: shortcut, items: $shortcuts, draggedItem: $draggedShortcut))
                    }
                }
                
                Button(action: {
                    withAnimation {
                        shortcuts.append(CustomAppShortcut(triggers: [ShortcutTrigger(key: "", modifier: "command")], bundleIDs: [""]))
                    }
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
        .onChange(of: shortcuts) { newValue in saveThrottled(newValue) }
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
        let m1 = UserDefaults.standard.string(forKey: mod1Key) ?? "right control"
        let m2 = UserDefaults.standard.string(forKey: mod2Key) ?? "shift"
        let k = UserDefaults.standard.string(forKey: keyKey) ?? defKey
        return[ShortcutTrigger(key: k, modifier: m1, modifier2: m2 == "none" ? nil : m2)]
    }
    
    private func saveThrottled(_ currentShortcuts: [CustomAppShortcut]) {
        saveTask?.cancel()
        let task = DispatchWorkItem {
            if let encoded = try? JSONEncoder().encode(currentShortcuts) {
                DispatchQueue.main.async { self.shortcutsData = encoded }
            }
        }
        saveTask = task
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}