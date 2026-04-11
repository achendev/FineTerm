import SwiftUI
import Cocoa

enum SettingsTab: String, CaseIterable {
    case connections = "Connections"
    case apps = "Apps"
    case clipboard = "Clipboard"
    case terminal = "Terminal"
    case advanced = "Advanced"
}

struct ModifierPickerContent: View {
    var includeNone: Bool = false
    var includeKeys: Bool = false
    
    var body: some View {
        if includeNone { Text("None").tag("none") }
        
        Text("Command").tag("command")
        Text("Control").tag("control")
        Text("Option").tag("option")
        Text("Shift").tag("shift")
        Text("Caps Lock").tag("capslock")
        
        Divider()
        
        Text("Left Command").tag("left command")
        Text("Left Control").tag("left control")
        Text("Left Option").tag("left option")
        Text("Left Shift").tag("left shift")
        
        Divider()
        
        Text("Right Command").tag("right command")
        Text("Right Control").tag("right control")
        Text("Right Option").tag("right option")
        Text("Right Shift").tag("right shift")
        
        if includeKeys {
            Divider()
            Text("Esc").tag("esc")
            Text("Tab").tag("tab")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var clipboardStore: ClipboardStore
    @State private var selectedTab: SettingsTab = .connections

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                Text("Connections").tag(SettingsTab.connections)
                Text("Apps").tag(SettingsTab.apps)
                Text("Clipboard").tag(SettingsTab.clipboard)
                Text("Terminal").tag(SettingsTab.terminal)
                Text("Advanced").tag(SettingsTab.advanced)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .onChange(of: selectedTab) { tab in
                if tab == .apps {
                    AppListService.shared.loadApps(forceReload: true)
                }
            }
            
            Divider()
            
            Group {
                switch selectedTab {
                case .connections:
                    ConnectionsSettingsTab()
                case .apps:
                    AppShortcutsSettingsTab()
                case .clipboard:
                    ClipboardSettingsTab(clipboardStore: clipboardStore)
                case .terminal:
                    TerminalSettingsTab()
                case .advanced:
                    AdvancedSettingsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 550, minHeight: 450)
    }
}