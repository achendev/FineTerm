import SwiftUI
import Combine

class ClipboardViewModel: ObservableObject {
    @Published var searchText = ""
    @Published var filteredItems: [ClipboardItem] = []
    
    // We track selection by ID for stable rendering in LazyVStack
    @Published var selectedItemID: UUID? = nil
    
    private var store: ClipboardStore
    private var cancellables = Set<AnyCancellable>()
    
    init(store: ClipboardStore) {
        self.store = store
        
        // OPTIMIZATION: Filter on a background queue to prevent UI stutter with 10k items
        Publishers.CombineLatest($searchText, store.$history)
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main) // Slight debounce for rapid typing
            .receive(on: DispatchQueue.global(qos: .userInitiated))
            .map { (text, history) -> [ClipboardItem] in
                return SearchService.smartFilter(history, query: text) { $0.content }
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] items in
                guard let self = self else { return }
                self.filteredItems = items
                
                // Auto-select first item on search change if selection is lost
                if let first = items.first, self.selectedItemID == nil || !items.contains(where: { $0.id == self.selectedItemID }) {
                    self.selectedItemID = first.id
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Navigation Logic
    func moveSelection(_ direction: Int) {
        guard !filteredItems.isEmpty else { return }
        
        let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let newIndex = max(0, min(filteredItems.count - 1, currentIndex + direction))
        
        selectedItemID = filteredItems[newIndex].id
    }
    
    func getSelectedItem() -> ClipboardItem? {
        return filteredItems.first(where: { $0.id == selectedItemID })
    }
}

// Helper for detecting Modifier Keys (Shift)
class FlagsMonitor: ObservableObject {
    @Published var isShiftDown = false
    private var monitor: Any?
    
    init() {
        self.isShiftDown = NSEvent.modifierFlags.contains(.shift)
    }
    
    func start() {
        if monitor != nil { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            DispatchQueue.main.async {
                self?.isShiftDown = event.modifierFlags.contains(.shift)
            }
            return event
        }
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
    
    deinit { stop() }
}

struct ClipboardHistoryView: View {
    @ObservedObject var store: ClipboardStore
    var onClose: () -> Void
    
    @StateObject private var viewModel: ClipboardViewModel
    @FocusState private var isSearchFocused: Bool
    @StateObject private var keyHandler = ClipboardKeyHandler()
    @StateObject private var flagsMonitor = FlagsMonitor()
    
    init(store: ClipboardStore, onClose: @escaping () -> Void) {
        self.store = store
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: ClipboardViewModel(store: store))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search clipboard...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
            }
            
            // Results List
            ScrollViewReader { proxy in
                ScrollView {
                    // PERFORMANCE: LazyVStack is mandatory for large lists (10k items).
                    LazyVStack(spacing: 0) {
                        if viewModel.filteredItems.isEmpty {
                            Text("No results found")
                                .foregroundColor(.secondary)
                                .padding(.top, 20)
                        } else {
                            // Direct iteration over items (no enumerated() to avoid array copying)
                            ForEach(viewModel.filteredItems) { item in
                                ClipboardRow(
                                    item: item,
                                    isHighlighted: item.id == viewModel.selectedItemID,
                                    isShiftDown: flagsMonitor.isShiftDown,
                                    action: { select(item) },
                                    onDelete: { delete(item) }
                                )
                                .id(item.id) // Stable Identity for ScrollViewReader
                                
                                Divider()
                            }
                        }
                    }
                }
                // Scroll to the selected ID, not index. This is much more stable in LazyStacks.
                .onChange(of: viewModel.selectedItemID) { id in
                    if let id = id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            // Focus Input
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isSearchFocused = true
            }
            
            // Start Monitoring Modifiers
            flagsMonitor.start()
            
            // Keyboard Handling
            keyHandler.start { event in
                // SECURITY: Ensure we only intercept keys if the event belongs to the ClipboardWindow.
                // This prevents swallowing keys meant for the Main Window when this view is technically
                // still "mounted" but the window is hidden/inactive.
                guard let window = event.window, window is ClipboardWindow else { return false }
                
                switch event.keyCode {
                case 126: // Up Arrow
                    viewModel.moveSelection(-1)
                    return true
                case 125: // Down Arrow
                    viewModel.moveSelection(1)
                    return true
                case 36: // Enter
                    if let item = viewModel.getSelectedItem() {
                        select(item)
                    }
                    return true
                default:
                    return false
                }
            }
        }
        .onDisappear {
            keyHandler.stop()
            flagsMonitor.stop()
        }
    }
    
    func select(_ item: ClipboardItem) {
        store.copyToClipboard(item: item)
        onClose()
    }
    
    func delete(_ item: ClipboardItem) {
        store.delete(id: item.id)
    }
}

// Helper for Keyboard Interception
class ClipboardKeyHandler: ObservableObject {
    private var monitor: Any?
    
    func start(onKeyDown: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if onKeyDown(event) { return nil }
            return event
        }
    }
    
    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

// Static Date Formatter for Row Performance
private let rowDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm dd/MM/yyyy"
    return formatter
}()

struct ClipboardRow: View {
    let item: ClipboardItem
    let isHighlighted: Bool
    var isShiftDown: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    @AppStorage(AppConfig.Keys.clipboardMaxLines) private var maxLines = 2
    @State private var isHovering = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Content
            Text(item.content)
                .font(.system(.body, design: .monospaced))
                .lineLimit(maxLines > 0 ? maxLines : nil)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isHighlighted ? .white : .primary)
                // Reserve space on the right for Timestamp/Trash so text doesn't flow under it
                .padding(.trailing, 20)
            
            // Top Right: Either Timestamp or Trash
            if isShiftDown {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption) // Matches session manager size
                        .foregroundColor(isHighlighted ? .white : .gray) // Matches session manager color
                }
                .buttonStyle(.borderless)
                .help("Delete item")
            } else {
                Text(rowDateFormatter.string(from: item.timestamp))
                    .font(.system(size: 9, weight: .regular, design: .default))
                    .foregroundColor(isHighlighted ? .white.opacity(0.6) : .secondary.opacity(0.6))
                    .padding(.top, -7.2)
                    .padding(.trailing, -7.2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .background(
            isHighlighted ? AppColors.activeHighlight : (isHovering ? AppColors.activeHighlight.opacity(0.1) : Color.clear)
        )
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
