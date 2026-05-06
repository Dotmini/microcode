import SwiftUI

struct DesignFloatingToolbar: View {
    @EnvironmentObject var designStore: DesignStore
    
    var body: some View {
        HStack(spacing: 4) {
            // Move / Select
            ToolIcon(active: designStore.currentTool == .select, icon: "cursorarrow", tooltip: "Move (V)") {
                designStore.currentTool = .select
            }
            
            ToolIcon(active: designStore.currentTool == .hand, icon: "hand.raised", tooltip: "Hand (H)") {
                designStore.currentTool = .hand
            }
            
            toolDivider
            
            // Frame Menu
            Menu {
                Section("iPhone") {
                    Button("iPhone 16 Pro") { addFrame(.iPhone16Pro) }
                    Button("iPhone 16 Pro Max") { addFrame(.iPhone16ProMax) }
                    Button("iPhone 15 Pro") { addFrame(.iPhone15Pro) }
                }
                Section("iPad") {
                    Button("iPad Air") { addFrame(.iPadAir) }
                    Button("iPad Pro 11\"") { addFrame(.iPadPro11) }
                    Button("iPad Pro 12.9\"") { addFrame(.iPadPro12_9) }
                }
                Section("Desktop") {
                    Button("MacBook Air") { addFrame(.macBookAir) }
                    Button("MacBook Pro 16\"") { addFrame(.macBookPro16) }
                    Button("Desktop (1440)") { addFrame(.desktop) }
                }
            } label: {
                Image(systemName: "number")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(designStore.currentTool == .frame ? .blue : .primary)
                    .frame(width: 32, height: 32)
                    .background(designStore.currentTool == .frame ? Color.blue.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            
            toolDivider
            
            // Shapes
            ToolIcon(active: designStore.currentTool == .rectangle, icon: "square", tooltip: "Rectangle (R)") {
                designStore.currentTool = .rectangle
            }
            
            ToolIcon(active: designStore.currentTool == .ellipse, icon: "circle", tooltip: "Ellipse (O)") {
                designStore.currentTool = .ellipse
            }
            
            // More Shapes Menu
            Menu {
                Button(action: { designStore.currentTool = .roundedRect }) {
                    Label("Rounded Rectangle", systemImage: "rectangle.roundedtop")
                }
                Button(action: { designStore.currentTool = .star }) {
                    Label("Star", systemImage: "star")
                }
                Button(action: { designStore.currentTool = .polygon }) {
                    Label("Polygon", systemImage: "hexagon")
                }
                Divider()
                Button(action: { designStore.currentTool = .arrow }) {
                    Label("Arrow", systemImage: "arrow.up.right")
                }
            } label: {
                Image(systemName: "square.on.circle")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            toolDivider
            
            // Line
            ToolIcon(active: designStore.currentTool == .line, icon: "line.diagonal", tooltip: "Line (L)") {
                designStore.currentTool = .line
            }
            
            // Text
            ToolIcon(active: designStore.currentTool == .text, icon: "textformat", tooltip: "Text (T)") {
                designStore.currentTool = .text
            }
            
            // Image
            ToolIcon(active: designStore.currentTool == .image, icon: "photo", tooltip: "Image") {
                designStore.currentTool = .image
            }
            
            toolDivider
            
            // Components Menu
            Menu {
                Section("Basic") {
                    Button(action: { addComponent(.button) }) {
                        Label("Button", systemImage: "cursorarrow.click.2")
                    }
                    Button(action: { addComponent(.textField) }) {
                        Label("Text Field", systemImage: "character.cursor.ibeam")
                    }
                    Button(action: { addComponent(.label) }) {
                        Label("Label", systemImage: "text.alignleft")
                    }
                }
                Section("Controls") {
                    Button(action: { addComponent(.checkbox) }) {
                        Label("Checkbox", systemImage: "checkmark.square")
                    }
                    Button(action: { addComponent(.switchToggle) }) {
                        Label("Switch", systemImage: "switch.2")
                    }
                    Button(action: { addComponent(.slider) }) {
                        Label("Slider", systemImage: "slider.horizontal.3")
                    }
                    Button(action: { addComponent(.progress) }) {
                        Label("Progress Bar", systemImage: "chart.bar.fill")
                    }
                }
                Section("Layout") {
                    Button(action: { addComponent(.card) }) {
                        Label("Card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                    Button(action: { addComponent(.list) }) {
                        Label("List", systemImage: "list.bullet.rectangle")
                    }
                    Button(action: { addComponent(.navigationBar) }) {
                        Label("Navigation Bar", systemImage: "menubar.rectangle")
                    }
                    Button(action: { addComponent(.tabBar) }) {
                        Label("Tab Bar", systemImage: "dock.rectangle")
                    }
                    Button(action: { addComponent(.divider) }) {
                        Label("Divider", systemImage: "minus")
                    }
                }
                Section("Advanced") {
                    Button(action: { addComponent(.avatar) }) {
                        Label("Avatar", systemImage: "person.crop.circle")
                    }
                    Button(action: { addComponent(.badge) }) {
                        Label("Badge", systemImage: "capsule.fill")
                    }
                    Button(action: { addComponent(.modal) }) {
                        Label("Modal", systemImage: "macwindow")
                    }
                }
            } label: {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 14))
                    .foregroundColor(.primary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            
            toolDivider
            
            // Delete
            Button(action: { designStore.deleteSelection() }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(designStore.selection.isEmpty ? .secondary : .red)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .disabled(designStore.selection.isEmpty)
            .help("Delete Selection")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .overlay(
            Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    private var toolDivider: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 2)
    }
    
    private func addFrame(_ type: DesignDeviceType) {
        let frame = DesignElement.createFrame(type: type)
        designStore.addElement(frame)
        designStore.currentTool = .select
    }
    
    private func addComponent(_ type: DesignElementType) {
        let element = DesignElement.create(type: type, x: 100, y: 100)
        designStore.addElement(element)
        designStore.currentTool = .select
    }
}

struct ToolIcon: View {
    var active: Bool
    var icon: String
    var tooltip: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(active ? .blue : .primary)
                .frame(width: 32, height: 32)
                .background(active ? Color.blue.opacity(0.15) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}
