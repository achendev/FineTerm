import SwiftUI

struct SettingsView: View {
    @AppStorage("copyOnSelect") private var copyOnSelect = true
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick = true
    @AppStorage("debugMode") private var debugMode = false
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Settings")
                .font(.headline)
            
            Divider()
            
            // Group 1: Copy on Select
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Copy on Select", isOn: $copyOnSelect)
                    .toggleStyle(.switch)
                
                Text("Automatically copies text when selected via mouse drag or double/triple click.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true) // Allow text to wrap
            }
            
            // Group 2: Paste on Right Click
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                    .toggleStyle(.switch)
                
                Text("Simulates Cmd+V when right-clicking in Terminal.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Group 3: Debug Mode
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Debug Mode", isOn: $debugMode)
                    .toggleStyle(.switch)
                
                Text("Enable verbose logging to standard output for troubleshooting.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        // Increased frame size to fit new option and prevent clipping
        .frame(width: 350, height: 380)
    }
}
