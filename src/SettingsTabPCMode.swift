import SwiftUI
import Cocoa

struct PCModeRuleRowView: View {
    @Binding var rule: PCModeRule
    let availableApps: [EditorApp]
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Toggle("", isOn: $rule.isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                
                TextField("Rule Group Name", text: $rule.name)
                    .font(.headline)
                    .textFieldStyle(PlainTextFieldStyle())
                
                Spacer()
                
                Button(action: onDelete) {
                    Image(systemName: "trash").foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<rule.mappings.count, id: \.self) { mappingIndex in
                    HStack(spacing: 8) {
                        Text("Map").font(.caption).foregroundColor(.secondary).frame(width: 25, alignment: .leading)
                        
                        TextField("e.g. ctrl + c", text: $rule.mappings[mappingIndex].from)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                        
                        Text("to").font(.caption).foregroundColor(.secondary)
                        
                        TextField("e.g. cmd + c or shell: ...", text: $rule.mappings[mappingIndex].to)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(maxWidth: .infinity)
                            
                        Button(action: { rule.mappings.remove(at: mappingIndex) }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                }
                
                Button(action: {
                    rule.mappings.append(KeyMap(from: "ctrl + c", to: "cmd + c"))
                }) {
                    Text("+ Add Key Mapping").font(.caption)
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 6)
            
            Divider()
            
            HStack {
                Picker("App Filter:", selection: $rule.appFilterMode) {
                    ForEach(AppFilterMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 200)
                
                Spacer()
            }
            
            if rule.appFilterMode != .none {
                VStack(spacing: 4) {
                    ForEach(0..<rule.appBundleIDs.count, id: \.self) { index in
                        HStack {
                            NativeAppPicker(
                                selection: Binding(
                                    get: { index < rule.appBundleIDs.count ? rule.appBundleIDs[index] : "" },
                                    set: { val in if index < rule.appBundleIDs.count { rule.appBundleIDs[index] = val } }
                                ),
                                apps: availableApps
                            )
                            .frame(height: 24)
                            
                            Button(action: { rule.appBundleIDs.remove(at: index) }) {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    Button(action: { rule.appBundleIDs.append("") }) {
                        Text("Add App").font(.caption)
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 10)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .opacity(rule.isEnabled ? 1.0 : 0.6)
    }
}

struct PCModeSettingsTab: View {
    @AppStorage(AppConfig.Keys.pcModeRules) private var pcModeRulesData: Data = AppConfig.pcModeRulesData
    @State private var rules: [PCModeRule] = []
    @StateObject private var appListService = AppListService.shared
    @State private var saveTask: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PC Mode Remapping").font(.headline)
                    Text("Format: 'modifier + key'. Valid Modifiers: cmd, ctrl, opt, shift.\nSpecial Keys: left_arrow, home, delete_or_backspace, spacebar.\nCommands: Use 'shell: open ...' in the 'to' field to execute terminal commands.")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                HStack {
                    Button("Enable All") {
                        for i in 0..<rules.count { rules[i].isEnabled = true }
                    }
                    Button("Disable All") {
                        for i in 0..<rules.count { rules[i].isEnabled = false }
                    }
                    Spacer()
                    Button("Restore Defaults") {
                        rules = AppConfig.defaultPCRules
                    }
                }
                .padding(.bottom, 8)
                
                VStack(spacing: 16) {
                    ForEach($rules) { $rule in
                        PCModeRuleRowView(
                            rule: $rule,
                            availableApps: appListService.availableApps,
                            onDelete: {
                                withAnimation { rules.removeAll { $0.id == rule.id } }
                            }
                        )
                    }
                }
                
                Button(action: {
                    withAnimation {
                        let emptyRule = PCModeRule(name: "New Group", isEnabled: true, mappings: [
                            KeyMap(from: "ctrl + c", to: "cmd + c")
                        ])
                        rules.append(emptyRule)
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Add New Rule Group")
                    }
                }
                .padding(.top, 10)
            }
            .padding()
        }
        .onAppear {
            load()
            appListService.loadApps(forceReload: false)
        }
        .onChange(of: rules) { newValue in
            saveThrottled(newValue)
        }
    }
    
    private func load() {
        if let decoded = try? JSONDecoder().decode([PCModeRule].self, from: pcModeRulesData) {
            rules = decoded
        } else {
            rules = AppConfig.defaultPCRules
        }
    }
    
    private func saveThrottled(_ currentRules: [PCModeRule]) {
        saveTask?.cancel()
        let task = DispatchWorkItem {
            if let encoded = try? JSONEncoder().encode(currentRules) {
                DispatchQueue.main.async {
                    self.pcModeRulesData = encoded
                }
            }
        }
        saveTask = task
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}