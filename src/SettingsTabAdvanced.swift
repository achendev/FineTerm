import SwiftUI

struct AdvancedSettingsTab: View {
    @AppStorage(AppConfig.Keys.hideCommandInList) private var hideCommandInList = true
    @AppStorage(AppConfig.Keys.smartFilter) private var smartFilter = true
    @AppStorage(AppConfig.Keys.snapToTerminal) private var snapToTerminal = false
    @AppStorage(AppConfig.Keys.copyOnSelect) private var copyOnSelect = true
    @AppStorage(AppConfig.Keys.pasteOnRightClick) private var pasteOnRightClick = true
    @AppStorage(AppConfig.Keys.debugMode) private var debugMode = false
    
    @State private var runOnStartup: Bool = LaunchAtLoginManager.isEnabled()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Behavior")
                        .font(.headline)
                    
                    Toggle("Hide Command in List", isOn: $hideCommandInList)
                    Toggle("Smart Search (Multi-word)", isOn: $smartFilter)
                    Toggle("Snap to Terminal (Left Side)", isOn: $snapToTerminal)
                        .onChange(of: snapToTerminal) { newValue in
                            NSApp.sendAction(#selector(AppDelegate.refreshTerminalObserverState), to: nil, from: nil)
                        }
                    Toggle("Copy on Select", isOn: $copyOnSelect)
                    Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("System")
                        .font(.headline)
                    
                    Toggle("Run on Startup", isOn: $runOnStartup)
                        .onChange(of: runOnStartup) { newValue in 
                            LaunchAtLoginManager.setEnabled(newValue) 
                        }
                    
                    Toggle("Debug Mode", isOn: $debugMode)
                }
            }
            .padding()
        }
    }
}