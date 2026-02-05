import SwiftUI

struct SettingsView: View {
    @AppStorage("copyOnSelect") private var copyOnSelect = true
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick = true
    @AppStorage("debugMode") private var debugMode = false
    
    // Command Injection Settings
    @AppStorage("commandPrefix") private var commandPrefix = "unset HISTFILE ; clear ; "
    @AppStorage("commandSuffix") private var commandSuffix = " && exit"
    @AppStorage("changeTerminalName") private var changeTerminalName = true
    
    // UI Settings
    @AppStorage("hideCommandInList") private var hideCommandInList = true
    @AppStorage("smartFilter") private var smartFilter = true
    
    // Shortcut Settings
    @AppStorage("globalShortcutKey") private var globalShortcutKey = "n"
    @AppStorage("globalShortcutModifier") private var globalShortcutModifier = "command"
    @AppStorage("globalShortcutAnywhere") private var globalShortcutAnywhere = false
    @AppStorage("secondActivationToTerminal") private var secondActivationToTerminal = true
    @AppStorage("escToTerminal") private var escToTerminal = false
    
    // Local State for Run on Startup (File-based, not UserDefaults)
    @State private var runOnStartup: Bool = LaunchAtLoginManager.isEnabled()
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Scrollable Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    
                    // Group 1: Shortcut
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Global Activation Shortcut")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        HStack {
                            Picker("", selection: $globalShortcutModifier) {
                                Text("Command").tag("command")
                                Text("Control").tag("control")
                                Text("Option").tag("option")
                            }
                            .frame(width: 100)
                            
                            Text("+")
                            
                            TextField("Key", text: $globalShortcutKey)
                                .frame(width: 30)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .onChange(of: globalShortcutKey) { newValue in
                                    if newValue.count > 1 {
                                        globalShortcutKey = String(newValue.prefix(1))
                                    }
                                }
                        }
                        
                        Toggle("System-wide (Global)", isOn: $globalShortcutAnywhere)
                            .toggleStyle(.switch)
                            .help("If enabled, the shortcut works from any app, not just Terminal.")
                        
                        Toggle("Second Activation to Terminal", isOn: $secondActivationToTerminal)
                            .toggleStyle(.switch)
                            .help("If enabled, pressing the shortcut again when search is focused will switch to Terminal.")
                            
                        Toggle("Esc to Terminal", isOn: $escToTerminal)
                            .toggleStyle(.switch)
                            .help("If enabled, pressing Esc will switch focus back to Terminal.")
                    }
                    
                    Divider()
                    
                    // Group 2: Command Injection Settings
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Command Execution Wrappers")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Prefix (Pre-pended to command):")
                                .font(.caption)
                            TextField("e.g. unset HISTFILE ; ", text: $commandPrefix)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Suffix (Appended to command):")
                                .font(.caption)
                            TextField("e.g. && exit", text: $commandSuffix)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        
                        Toggle("Set Terminal Tab Name", isOn: $changeTerminalName)
                            .toggleStyle(.switch)
                            .help("Sets the Terminal tab title to the connection name before running the command.")
                    }
                    
                    Divider()
                    
                    // Group 3: UI Preferences
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Hide Command in List", isOn: $hideCommandInList)
                            .toggleStyle(.switch)
                        
                        Toggle("Smart Search (Multi-word)", isOn: $smartFilter)
                            .toggleStyle(.switch)
                            .help("If enabled, 'db prod' matches 'prod db' (AND logic per word).")
                    }
                    
                    // Group 4: Mouse Behavior
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Copy on Select", isOn: $copyOnSelect)
                            .toggleStyle(.switch)
                        
                        Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                            .toggleStyle(.switch)
                    }

                    Divider()

                    // Group 5: System
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Run on Startup", isOn: $runOnStartup)
                            .toggleStyle(.switch)
                            .onChange(of: runOnStartup) { newValue in
                                LaunchAtLoginManager.setEnabled(newValue)
                            }

                        Toggle("Debug Mode", isOn: $debugMode)
                            .toggleStyle(.switch)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .frame(maxWidth: .infinity)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 400, height: 650)
    }
}

