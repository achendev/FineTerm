import SwiftUI

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    var onClose: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.history) { item in
                        ClipboardRow(item: item) {
                            store.copyToClipboard(item: item)
                            onClose()
                        }
                        Divider()
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Native SwiftUI handler for Esc key
        .onExitCommand(perform: onClose)
    }
}

struct ClipboardRow: View {
    let item: ClipboardItem
    let action: () -> Void
    
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var maxLines = 2
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(alignment: .top) {
            Text(item.content)
                .font(.system(.body, design: .monospaced))
                .lineLimit(maxLines)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        .contentShape(Rectangle())
        .background(isHovering ? AppColors.activeHighlight.opacity(0.1) : Color.clear)
        .onTapGesture {
            action()
        }
        .onHover { hovering in
            isHovering = hovering
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
    }
}

