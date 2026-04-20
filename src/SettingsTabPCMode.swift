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
                        
                        TextField("e.g. func: copy or cmd + c", text: $rule.mappings[mappingIndex].to)
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
                    rule.mappings.append(KeyMap(from: "ctrl + c", to: "func: copy"))
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

struct ModifiersPickerView: View {
    @Binding var selection: String
    
    var body: some View {
        Picker("", selection: $selection) {
            Text("Globe / Fn").tag("globe")
            Text("Control").tag("control")
            Text("Option").tag("option")
            Text("Command").tag("command")
            Text("Caps Lock").tag("capslock")
            
            Divider()
            ForEach(1...24, id: \.self) { i in
                Text("F\(i)").tag("f\(i)")
            }
        }
        .labelsHidden()
        .frame(maxWidth: 160, alignment: .trailing)
    }
}

struct PCModeSettingsTab: View {
    @AppStorage(AppConfig.Keys.pcModeRules) private var pcModeRulesData: Data = AppConfig.pcModeRulesData
    @AppStorage(AppConfig.Keys.pcModeEngine) private var pcModeEngine = 0
    
    @AppStorage(AppConfig.Keys.systemModifierSwapEnabled) private var systemModifierSwapEnabled = false
    @AppStorage(AppConfig.Keys.systemModifierMapFn) private var mapFn = "control"
    @AppStorage(AppConfig.Keys.systemModifierMapCtrl) private var mapCtrl = "globe"
    @AppStorage(AppConfig.Keys.systemModifierMapOpt) private var mapOpt = "command"
    @AppStorage(AppConfig.Keys.systemModifierMapCmd) private var mapCmd = "option"
    @AppStorage(AppConfig.Keys.systemModifierMapCapsLock) private var mapCapsLock = "capslock"
    
    @State private var rules: [PCModeRule] = []
    @StateObject private var appListService = AppListService.shared
    @State private var saveTask: DispatchWorkItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Toggle("System Hardware Modifier Override", isOn: $systemModifierSwapEnabled)
                            .font(.headline)
                            .onChange(of: systemModifierSwapEnabled) { _ in updateModifiers() }
                    }
                    
                    Text("Re-wires hardware keys instantly in-memory. Resets on App Quit. This bypasses System Settings safely.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if systemModifierSwapEnabled {
                        Divider()
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Globe (🌐) key")
                                Spacer()
                                ModifiersPickerView(selection: $mapFn).onChange(of: mapFn) { _ in updateModifiers() }
                            }
                            HStack {
                                Text("Control (⌃) key")
                                Spacer()
                                ModifiersPickerView(selection: $mapCtrl).onChange(of: mapCtrl) { _ in updateModifiers() }
                            }
                            HStack {
                                Text("Option (⌥) key")
                                Spacer()
                                ModifiersPickerView(selection: $mapOpt).onChange(of: mapOpt) { _ in updateModifiers() }
                            }
                            HStack {
                                Text("Command (⌘) key")
                                Spacer()
                                ModifiersPickerView(selection: $mapCmd).onChange(of: mapCmd) { _ in updateModifiers() }
                            }
                            HStack {
                                Text("Caps Lock (⇪) key")
                                Spacer()
                                ModifiersPickerView(selection: $mapCapsLock).onChange(of: mapCapsLock) { _ in updateModifiers() }
                            }
                        }
                        .padding(.vertical, 4)
                        
                        HStack {
                            Spacer()
                            Button("Restore Defaults") {
                                mapFn = "control"
                                mapCtrl = "globe"
                                mapCmd = "option"
                                mapOpt = "command"
                                mapCapsLock = "capslock"
                                systemModifierSwapEnabled = false
                                updateModifiers()
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                
                Divider()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("PC Mode Remapping").font(.headline)
                    Text("Format: 'modifier + key'. Valid Modifiers: cmd, ctrl, opt, shift.\nSequences: Separate multiple actions with commas (e.g. 'ctrl + a, n').\nSpecial Keys: left_arrow, home, delete_or_backspace, spacebar.\nCommands: Use 'shell: open ...', 'func: copy', 'func: type_clipboard', or 'type: text' in the 'to' field.")
                        .font(.caption).foregroundColor(.secondary)
                }
                
                HStack(spacing: 12) {
                    Text("Engine:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        
                    Picker("", selection: $pcModeEngine) {
                        Text("Internal (Fastest)").tag(0)
                        Text("Karabiner (Full)").tag(1)
                        Text("Hybrid (Internal + Karabiner Fallback)").tag(2)
                    }
                    .labelsHidden()
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 400)
                    .onChange(of: pcModeEngine) { _ in syncEngine(); updateModifiers() }
                    
                    Spacer()
                }
                .padding(.vertical, 6)
                
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
                            KeyMap(from: "ctrl + c", to: "func: copy")
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
    
    private func syncEngine() {
        if pcModeEngine == 1 {
            KarabinerExporter.sync(rules: rules, isHybrid: false)
        } else if pcModeEngine == 2 {
            KarabinerExporter.sync(rules: rules, isHybrid: true)
            // Ensure SecureInputMonitor pushes the immediate state
            NotificationCenter.default.post(name: NSNotification.Name("ForceSecureInputSync"), object: nil)
        } else {
            KarabinerExporter.clear()
        }
    }
    
    private func updateModifiers() {
        SystemModifierManager.applyCurrentSettings()
        // Ensure Karabiner gets updated system modifiers if it's running
        if pcModeEngine > 0 {
            syncEngine()
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
                    // Immediately sync with Karabiner if a mode is active
                    if self.pcModeEngine == 1 {
                        KarabinerExporter.sync(rules: currentRules, isHybrid: false)
                    } else if self.pcModeEngine == 2 {
                        KarabinerExporter.sync(rules: currentRules, isHybrid: true)
                    }
                }
            }
        }
        saveTask = task
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: task)
    }
}