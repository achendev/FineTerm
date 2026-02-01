import SwiftUI

struct SettingsView: View {
    @AppStorage("copyOnSelect") private var copyOnSelect = true
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick = true
    @AppStorage("debugMode") private var debugMode = false
    
    // Command Injection Settings
    @AppStorage("commandPrefix") private var commandPrefix = "unset HISTFILE ; clear ; "
    @AppStorage("commandSuffix") private var commandSuffix = " && exit"
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.headline)
            
            Divider()
            
            // Group 1: Command Wrappers (New)
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
            }
            
            Divider()
            
            // Group 2: Mouse Behavior
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Copy on Select", isOn: $copyOnSelect)
                    .toggleStyle(.switch)
                
                Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                    .toggleStyle(.switch)
            }

            Divider()

            // Group 3: Debug Mode
            Toggle("Debug Mode", isOn: $debugMode)
                .toggleStyle(.switch)
            
            Spacer()
            
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        // Increased frame size to fit new fields
        .frame(width: 350, height: 500)
    }
}
