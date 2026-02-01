import SwiftUI

struct SettingsView: View {
    @AppStorage("copyOnSelect") private var copyOnSelect = true
    @AppStorage("pasteOnRightClick") private var pasteOnRightClick = true
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
            
            Divider()
            
            Toggle("Copy on Select", isOn: $copyOnSelect)
                .toggleStyle(.switch)
            Text("Automatically copies text when selected via mouse drag or double/triple click.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()

            Toggle("Paste on Right Click", isOn: $pasteOnRightClick)
                .toggleStyle(.switch)
            Text("Simulates Cmd+V when right-clicking in Terminal.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button("Done") {
                presentationMode.wrappedValue.dismiss()
            }
            .frame(maxWidth: .infinity)
            .padding(.top)
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}
