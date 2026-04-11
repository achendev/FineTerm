import SwiftUI

struct TerminalSettingsTab: View {
    @AppStorage(AppConfig.Keys.targetTerminalBundleID) private var targetTerminalBundleID = "com.apple.Terminal"
    @AppStorage(AppConfig.Keys.commandPrefix) private var commandPrefix = ""
    @AppStorage(AppConfig.Keys.commandSuffix) private var commandSuffix = ""
    @AppStorage(AppConfig.Keys.changeTerminalName) private var changeTerminalName = true
    @AppStorage(AppConfig.Keys.terminalTabNameCommand) private var terminalTabNameCommand = "( ( sleep 2 ; printf '\\e]1;%s\\a' '$PROFILE_NAME' ) 2>/dev/null & ) 2>/dev/null ; clear ; "
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Target Terminal:")
                        .font(.caption)
                    Picker("", selection: $targetTerminalBundleID) {
                        Text("Apple Terminal").tag("com.apple.Terminal")
                        Text("iTerm2").tag("com.googlecode.iterm2")
                        Text("Ghostty").tag("com.mitchellh.ghostty")
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Prefix:")
                            .font(.caption)
                        TextField("e.g. unset HISTFILE", text: $commandPrefix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Suffix:")
                            .font(.caption)
                        TextField("e.g. && exit", text: $commandSuffix)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Set Terminal Tab Name Globally", isOn: $changeTerminalName)
                    
                    if changeTerminalName {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tab Name Command:")
                                .font(.caption)
                            TextField("e.g. printf '\\e]1;%s\\a' '$PROFILE_NAME'", text: $terminalTabNameCommand)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                        .padding(.leading, 20)
                    }
                }
            }
            .padding()
        }
    }
}