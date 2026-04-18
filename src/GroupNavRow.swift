import SwiftUI

struct GroupNavRow: View {
    let title: String
    @Binding var isEnabled: Bool
    @Binding var triggers: [ShortcutTrigger]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<triggers.count, id: \.self) { index in
                HStack(spacing: 6) {
                    if index == 0 {
                        Toggle("", isOn: $isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .frame(width: 38, alignment: .leading)
                            .help("Enable this global group navigation shortcut")
                        
                        Button(action: { triggers.append(ShortcutTrigger(key: "", modifier: "command")) }) {
                            Image(systemName: "plus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.accentColor)
                        .frame(width: 16)
                        
                        Text(title)
                            .frame(width: 85, alignment: .leading)
                            .font(.caption)
                    } else {
                        Spacer().frame(width: 38)
                        
                        Button(action: { triggers.remove(at: index) }) {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.red)
                        .frame(width: 16)
                        
                        Text("")
                            .frame(width: 85, alignment: .leading)
                    }
                    
                    Picker("", selection: $triggers[index].modifier) {
                        ModifierPickerContent()
                    }
                    .frame(width: 120).labelsHidden()
                    
                    Text("+")
                    
                    Picker("", selection: Binding(
                        get: { triggers[index].modifier2 ?? "none" },
                        set: { val in triggers[index].modifier2 = (val == "none" ? nil : val) }
                    )) {
                        ModifierPickerContent(includeNone: true, includeKeys: true)
                    }
                    .frame(width: 120).labelsHidden()

                    Text("+")
                    
                    TextField("Key", text: Binding(
                        get: { triggers[index].key },
                        set: { val in triggers[index].key = String(val.prefix(10)).lowercased() }
                    ))
                    .frame(width: 60)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                }
            }
        }
    }
}