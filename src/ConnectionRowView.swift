import SwiftUI
import UniformTypeIdentifiers

struct ConnectionRowView: View {
    let connection: Connection
    let isHighlighted: Bool
    let isEditing: Bool
    let hideCommand: Bool
    let searchText: String
    
    // Callbacks
    let onTap: () -> Void
    let onConnect: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Interactive Row Area
                Button(action: onTap) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(connection.name)
                                .font(.headline)
                                .foregroundColor(isHighlighted ? .white : (isEditing ? .accentColor : .primary))
                            
                            if !hideCommand || !searchText.isEmpty {
                                Text(connection.command)
                                    .font(.caption)
                                    .foregroundColor(isHighlighted ? .white.opacity(0.8) : .gray)
                            }
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() }
                    else { NSCursor.pop() }
                }
                
                // Connect Button
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent)
                    .tint(isHighlighted ? Color.white.opacity(0.2) : nil)
                    .padding(.leading, 8)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHighlighted ? AppColors.activeHighlight : Color.clear)
                    .padding(.horizontal, 4)
            )
            // DRAG SOURCE
            .onDrag {
                NSItemProvider(object: connection.id.uuidString as NSString)
            }
            
            Divider()
        }
        .id(connection.id)
    }
}
