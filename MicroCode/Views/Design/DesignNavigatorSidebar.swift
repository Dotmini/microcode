import SwiftUI

struct DesignNavigatorSidebar: View {
    @ObservedObject var designStore: DesignStore
    @State private var selectedTab = 0 // 0: Layers, 1: Assets
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Image(systemName: "square.3.layers.3d").tag(0)
                Image(systemName: "shippingbox").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(10)
            
            Divider()
            
            if selectedTab == 0 {
                // Layers List
                List {
                    Section("Page 1") {
                        if let pageIndex = designStore.project.pages.firstIndex(where: { $0.id == designStore.activePageId }) {
                            ForEach(designStore.project.pages[pageIndex].elements.reversed()) { element in
                                LayerRow(element: element, isSelected: designStore.selection.contains(element.id))
                                    .onTapGesture {
                                        designStore.selection = [element.id]
                                    }
                            }
                            .onDelete { indices in
                                designStore.project.pages[pageIndex].elements.remove(atOffsets: indices)
                            }
                            .onMove { indices, newOffset in
                                designStore.project.pages[pageIndex].elements.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                // Assets / Components Library (Grid)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                        AssetItem(name: "Label", icon: "text.alignleft") { designStore.currentTool = .label }
                        AssetItem(name: "Button", icon: "cursorarrow.click.2") { designStore.currentTool = .button }
                        AssetItem(name: "Input", icon: "character.cursor.ibeam") { designStore.currentTool = .textfield }
                        AssetItem(name: "Checkbox", icon: "checkmark.square") { designStore.currentTool = .checkbox }
                        AssetItem(name: "Toggle", icon: "switch.2") { designStore.currentTool = .switchToggle }
                        AssetItem(name: "Card", icon: "creditcard") { designStore.currentTool = .card }
                        AssetItem(name: "Nav", icon: "menubar.rectangle") { designStore.currentTool = .navigationBar }
                        // Expansion
                        AssetItem(name: "Avatar", icon: "person.crop.circle") { designStore.currentTool = .avatar }
                        AssetItem(name: "Badge", icon: "capsule.fill") { designStore.currentTool = .badge }
                        AssetItem(name: "Radio", icon: "circle.circle") { designStore.currentTool = .radioButton }
                        AssetItem(name: "Tooltip", icon: "message.fill") { designStore.currentTool = .tooltip }
                        AssetItem(name: "Menu", icon: "list.bullet.rectangle") { designStore.currentTool = .menu }
                        AssetItem(name: "Modal", icon: "macwindow") { designStore.currentTool = .modal }
                        AssetItem(name: "Divider", icon: "minus") { designStore.currentTool = .divider }
                    }
                    .padding()
                }
            }
        }
    }
}

struct LayerRow: View {
    let element: DesignElement
    let isSelected: Bool
    
    var body: some View {
        HStack {
            Image(systemName: iconForType(element.type))
                .foregroundColor(.secondary)
            Text(element.type.rawValue.capitalized) // Should use a proper name field
                .font(.system(size: 13))
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .listRowBackground(isSelected ? Color.blue.opacity(0.1) : Color.clear)
    }
    
    func iconForType(_ type: DesignElementType) -> String {
        switch type {
        case .text: return "textformat"
        case .button: return "cursorarrow.click.2"
        case .image: return "photo"
        case .card: return "creditcard"
        default: return "square"
        }
    }
}

struct AssetItem: View {
    let name: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .frame(height: 40)
                Text(name).font(.caption)
            }
            .frame(width: 80, height: 70)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            .shadow(radius: 1)
        }
        .buttonStyle(.plain)
    }
}
