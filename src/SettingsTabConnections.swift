import SwiftUI

struct ConnectionsSettingsTab: View {
    @AppStorage(AppConfig.Keys.globalShortcutKey) private var globalShortcutKey = "n"
    @AppStorage(AppConfig.Keys.globalShortcutModifier) private var globalShortcutModifier = "command"
    @AppStorage(AppConfig.Keys.globalShortcutAnywhere) private var globalShortcutAnywhere = false
    @AppStorage(AppConfig.Keys.secondActivationToTerminal) private var secondActivationToTerminal = true
    @AppStorage(AppConfig.Keys.thirdActivationToOrigin) private var thirdActivationToOrigin = true
    @AppStorage(AppConfig.Keys.escToTerminal) private var escToTerminal = false
    
    @AppStorage(AppConfig.Keys.enableTerminalToggleShortcut) private var enableTerminalToggleShortcut = true
    @AppStorage(AppConfig.Keys.terminalToggleShortcutKey) private var terminalToggleShortcutKey = "h"
    @AppStorage(AppConfig.Keys.terminalToggleShortcutModifier) private var terminalToggleShortcutModifier = "command"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Main Shortcut:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Picker("", selection: $globalShortcutModifier) {
                            Text("Command").tag("command")
                            Text("Control").tag("control")
                            Text("Option").tag("option")
                        }
                        .frame(width: 100)
                        .labelsHidden()
                        
                        Text("+")
                        
                        TextField("Key", text: $globalShortcutKey)
                            .frame(width: 40)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding(.leading, 10)
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("System-wide (Global)", isOn: $globalShortcutAnywhere)
                    Toggle("Second Activation to Terminal", isOn: $secondActivationToTerminal)
                    
                    if secondActivationToTerminal {
                        Toggle("Third Activation Back to Origin", isOn: $thirdActivationToOrigin)
                            .padding(.leading, 20)
                    }
                    
                    Toggle("Esc to Terminal", isOn: $escToTerminal)
                }
                .padding(.leading, 10)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Enable Terminal Toggle Shortcut", isOn: $enableTerminalToggleShortcut)
                    
                    if enableTerminalToggleShortcut {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Shortcut:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Picker("", selection: $terminalToggleShortcutModifier) {
                                    Text("Command").tag("command")
                                    Text("Control").tag("control")
                                    Text("Option").tag("option")
                                }
                                .frame(width: 100)
                                .labelsHidden()
                                
                                Text("+")
                                
                                TextField("Key", text: $terminalToggleShortcutKey)
                                    .frame(width: 40)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.leading, 10)
            }
            .padding()
        }
    }
}