import SwiftUI

struct DesignLayersPanel: View {
    @EnvironmentObject var designStore: DesignStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Layers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Layer List
            if let pageIndex = designStore.project.pages.firstIndex(where: { $0.id == designStore.activePageId }) {
                List {
                    // Reversed to show top-most elements at top of list (Z-Index visual logic)
                    // However, SwiftUI List usually maps index 0 to top. 
                    // In ZStack, index 0 is bottom.
                    // So we probably want to display them in reversed order?
                    // But `onMove` needs to map correctly.
                    // Let's keep it direct for now (Bottom is Top of List) or strictly ZStack order?
                    // Standard: Top of list = Front-most element.
                    // So we need to reverse the array for display, but handle move carefully.
                    // For MVP simplicity: Direct mapping. Element 0 (Back) is at Top of List.
                    // Wait, that's unintuitive. 
                    // Let's implement direct binding first. 
                    
                    ForEach($designStore.project.pages[pageIndex].elements) { $element in
                        LayerRow(element: $element, isSelected: designStore.selection.contains(element.id))
                            .onTapGesture {
                                designStore.selection = [element.id]
                            }
                            .listRowInsets(EdgeInsets())
                            .listRowInsets(EdgeInsets())
                            .background(Color.clear) // listRowSeparator not available on v12
                    }
                    .onMove { indices, newOffset in
                        designStore.project.pages[pageIndex].elements.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .listStyle(.plain)
            } else {
                Text("No Active Page")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LayerRow: View {
    @Binding var element: DesignElement
    var isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Visibility Toggle
            Button(action: { element.isVisible.toggle() }) {
                Image(systemName: element.isVisible ? "eye" : "eye.slash")
                    .font(.system(size: 10))
                    .foregroundColor(element.isVisible ? .secondary : .gray)
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
            
            // Icon
            Image(systemName: element.type.icon)
                .font(.system(size: 11))
                .foregroundColor(.accentColor)
                .frame(width: 16)
            
            // Name
            TextField("", text: $element.name)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            
            Spacer()
            
            // Lock Toggle
            Button(action: { element.isLocked.toggle() }) {
                Image(systemName: element.isLocked ? "lock.fill" : "lock.open")
                    .font(.system(size: 9))
                    .foregroundColor(element.isLocked ? .orange : .secondary.opacity(0.3))
                    .frame(width: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
    }
}
