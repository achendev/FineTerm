import SwiftUI

struct ShortcutDropDelegate: DropDelegate {
    let item: CustomAppShortcut
    @Binding var items: [CustomAppShortcut]
    @Binding var draggedItem: CustomAppShortcut?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem,
              dragged.id != item.id,
              let from = items.firstIndex(where: { $0.id == dragged.id }),
              let to = items.firstIndex(where: { $0.id == item.id }) else { return }

        if from != to {
            withAnimation(.default) {
                items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItem = nil
        return true
    }
}

struct ShortcutRowView: View {
    @Binding var shortcut: CustomAppShortcut
    let availableApps: [EditorApp]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<shortcut.triggers.count, id: \.self) { index in
                        HStack(spacing: 6) {
                            if index == 0 {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                                    .frame(width: 16)
                                    .onHover { hovering in
                                        if hovering { NSCursor.openHand.push() } else { NSCursor.pop() }
                                    }
                                
                                Toggle("", isOn: $shortcut.isEnabled)
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.mini)
                                    .frame(width: 38, alignment: .leading)
                                    
                                Button(action: { shortcut.triggers.append(ShortcutTrigger(key: "", modifier: "command")) }) {
                                    Image(systemName: "plus.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.accentColor)
                                .frame(width: 16)
                            } else {
                                Spacer().frame(width: 16 + 6 + 38)
                                
                                Button(action: { shortcut.triggers.remove(at: index) }) {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.borderless)
                                .foregroundColor(.red)
                                .frame(width: 16)
                            }
                            
                            Picker("", selection: $shortcut.triggers[index].modifier) {
                                ModifierPickerContent()
                            }
                            .frame(width: 120).labelsHidden()
                            
                            Text("+")
                            
                            Picker("", selection: Binding(
                                get: { shortcut.triggers[index].modifier2 ?? "none" },
                                set: { val in shortcut.triggers[index].modifier2 = (val == "none" ? nil : val) }
                            )) {
                                ModifierPickerContent(includeNone: true, includeKeys: true)
                            }
                            .frame(width: 120).labelsHidden()

                            Text("+")
                            
                            TextField("Key", text: Binding(
                                get: { shortcut.triggers[index].key },
                                set: { val in shortcut.triggers[index].key = String(val.prefix(10)).lowercased() }
                            ))
                            .frame(width: 50).textFieldStyle(RoundedBorderTextFieldStyle())
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                                .buttonStyle(.borderless)
                                .disabled(!canMoveUp)
                                .opacity(canMoveUp ? 1.0 : 0.3)
                            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                                .buttonStyle(.borderless)
                                .disabled(!canMoveDown)
                                .opacity(canMoveDown ? 1.0 : 0.3)
                        }
                        
                        Button(action: { shortcut.bundleIDs.append("") }) {
                            Image(systemName: "plus.app").foregroundColor(.accentColor)
                        }
                        .buttonStyle(.borderless)
                        
                        Button(action: onDelete) {
                            Image(systemName: "trash").foregroundColor(.red)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            
            VStack(spacing: 6) {
                ForEach(0..<shortcut.bundleIDs.count, id: \.self) { index in
                    HStack {
                        NativeAppPicker(
                            selection: Binding(
                                get: { index < shortcut.bundleIDs.count ? shortcut.bundleIDs[index] : "" },
                                set: { val in if index < shortcut.bundleIDs.count { shortcut.bundleIDs[index] = val } }
                            ),
                            apps: availableApps
                        )
                        .frame(height: 24)
                        
                        if shortcut.bundleIDs.count > 1 {
                            Button(action: { shortcut.bundleIDs.remove(at: index) }) {
                                Image(systemName: "minus.circle").foregroundColor(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))
        .opacity(shortcut.isEnabled ? 1.0 : 0.6)
    }
}