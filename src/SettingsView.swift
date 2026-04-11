import SwiftUI
import Cocoa

enum SettingsTab: String, CaseIterable {
    case connections = "Connections"
    case apps = "Apps"
    case clipboard = "Clipboard"
    case terminal = "Terminal"
    case advanced = "Advanced"
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