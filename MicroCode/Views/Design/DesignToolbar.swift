import SwiftUI

struct DesignToolbar: View {
    @EnvironmentObject var designStore: DesignStore
    @State private var showingPreview = false
    
    // Popover States
    @State private var showingDevices = false
    @State private var showingShapes = false
    @State private var showingComponents = false
    
    var body: some View {
        HStack(spacing: 4) {
            // General Tools
            ToolButton(icon: "cursorarrow", tool: .select, current: designStore.currentTool) { designStore.currentTool = .select }
            ToolButton(icon: "hand.raised", tool: .hand, current: designStore.currentTool) { designStore.currentTool = .hand }
            
            Divider().frame(height: 20)
            
            // Frame / Device
            PopoverToolButton(icon: "iphone", active: designStore.currentTool == .frame, isPresented: $showingDevices) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Frames").font(.caption).foregroundColor(.secondary)
                    ForEach(DesignDeviceType.allCases) { device in
                        Button(action: {
                            addDeviceFrame(device)
                            showingDevices = false
                        }) {
                            Label(device.rawValue, systemImage: "iphone")
                        }
                        .buttonStyle(.plain)
                        .padding(4)
                    }
                }
                .padding(8)
                .frame(width: 200)
            }
            
            // Shapes
            PopoverToolButton(icon: "square.dashed", active: isShapeTool(designStore.currentTool), isPresented: $showingShapes) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Shapes").font(.caption).foregroundColor(.secondary)
                    Group {
                        ToolMenuItem(icon: "rectangle", title: "Rectangle", tool: .rectangle) { setTool(.rectangle) }
                        ToolMenuItem(icon: "rectangle.roundedtop", title: "Rounded Rect", tool: .roundedRect) { setTool(.roundedRect) }
                        ToolMenuItem(icon: "circle", title: "Ellipse", tool: .ellipse) { setTool(.ellipse) }
                        ToolMenuItem(icon: "line.diagonal", title: "Line", tool: .line) { setTool(.line) }
                        ToolMenuItem(icon: "arrow.up.right", title: "Arrow", tool: .arrow) { setTool(.arrow) }
                        ToolMenuItem(icon: "star", title: "Star", tool: .star) { setTool(.star) }
                        ToolMenuItem(icon: "hexagon", title: "Polygon", tool: .polygon) { setTool(.polygon) }
                    }
                }
                .padding(8)
                .frame(width: 150)
            }
            
            // Text / Image
            ToolButton(icon: "text.cursor", tool: .text, current: designStore.currentTool) { designStore.currentTool = .text }
            ToolButton(icon: "photo", tool: .image, current: designStore.currentTool) { designStore.currentTool = .image }
            
            Divider().frame(height: 20)
            
            // Components
            PopoverToolButton(icon: "cube.box", active: isComponentTool(designStore.currentTool), isPresented: $showingComponents) {
                 VStack(alignment: .leading, spacing: 5) {
                    Text("Components").font(.caption).foregroundColor(.secondary)
                    Group {
                        ToolMenuItem(icon: "cursorarrow.click.2", title: "Button", tool: .button) { setTool(.button) }
                        ToolMenuItem(icon: "text.alignleft", title: "Label", tool: .label) { setTool(.label) }
                        ToolMenuItem(icon: "character.cursor.ibeam", title: "Input Field", tool: .textfield) { setTool(.textfield) }
                        ToolMenuItem(icon: "checkmark.square", title: "Checkbox", tool: .checkbox) { setTool(.checkbox) }
                        ToolMenuItem(icon: "switch.2", title: "Switch", tool: .switchToggle) { setTool(.switchToggle) }
                        ToolMenuItem(icon: "slider.horizontal.3", title: "Slider", tool: .slider) { setTool(.slider) }
                        ToolMenuItem(icon: "chart.bar.fill", title: "Progress", tool: .progress) { setTool(.progress) }
                        
                        Divider()
                        
                        ToolMenuItem(icon: "rectangle.portrait.on.rectangle.portrait", title: "Card", tool: .card) { setTool(.card) }
                        ToolMenuItem(icon: "list.bullet.rectangle", title: "List", tool: .list) { setTool(.list) }
                        ToolMenuItem(icon: "menubar.rectangle", title: "Navigation Bar", tool: .navigationBar) { setTool(.navigationBar) }
                        ToolMenuItem(icon: "squareshape.split.3x3", title: "Tab Bar", tool: .tabBar) { setTool(.tabBar) }
                    }
                }
                .padding(8)
                .frame(width: 150)
            }
            
            Spacer()
            
            // Framework Selector
            Picker("", selection: $designStore.project.framework) {
                ForEach(DesignFramework.allCases, id: \.self) { fw in
                    Text(fw.rawValue).tag(fw)
                }
            }
            .frame(width: 100)
            .labelsHidden()
            
            // Actions
            Button(action: { designStore.deleteSelection() }) {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .disabled(designStore.selection.isEmpty)
        }
        .padding(8)
        .background(Material.ultraThinMaterial)
        .cornerRadius(10)
        .shadow(radius: 2)
    }
    
    // MARK: - Helpers
    
    func setTool(_ tool: DesignStore.DesignTool) {
        designStore.currentTool = tool
        showingShapes = false
        showingComponents = false
    }
    
    func addDeviceFrame(_ device: DesignDeviceType) {
        // Create frame immediately
        // Center on screen logic? Need access to canvas offset/zoom
        // For MVP, add at (100, 100) + offset
        let element = DesignElement(
            name: device.rawValue,
            type: .deviceFrame,
            x: 100 - designStore.panOffset.width/designStore.zoomLevel,
            y: 100 - designStore.panOffset.height/designStore.zoomLevel,
            width: device.size.width,
            height: device.size.height,
            style: DesignStyle(fill: DesignColor.white, stroke: DesignColor(gray: 0.9))
        )
        designStore.addElement(element)
        designStore.currentTool = .select
    }
    
    func isShapeTool(_ tool: DesignStore.DesignTool) -> Bool {
        switch tool {
        case .rectangle, .roundedRect, .ellipse, .star, .polygon, .line, .arrow: return true
        default: return false
        }
    }
    
    func isComponentTool(_ tool: DesignStore.DesignTool) -> Bool {
        switch tool {
        case .button, .label, .textfield, .checkbox, .switchToggle, .slider, .progress, .card, .list, .navigationBar, .tabBar: return true
        default: return false
        }
    }
}

// MARK: - Components

struct ToolButton: View {
    let icon: String
    let tool: DesignStore.DesignTool
    let current: DesignStore.DesignTool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(current == tool ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(current == tool ? Color.blue : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .help(String(describing: tool))
        .onDrag {
            let typeString = String(describing: tool)
            return NSItemProvider(object: typeString as NSString)
        }
    }
}

struct PopoverToolButton<Content: View>: View {
    let icon: String
    let active: Bool
    @Binding var isPresented: Bool
    let content: () -> Content
    
    var body: some View {
        Button(action: { isPresented.toggle() }) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(active ? .white : .primary)
                .frame(width: 32, height: 32)
                .background(active ? Color.blue : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            content()
        }
    }
}

struct ToolMenuItem: View {
    let icon: String
    let title: String
    let tool: DesignStore.DesignTool?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(4)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag {
            if let tool = tool {
                let typeString = String(describing: tool)
                return NSItemProvider(object: typeString as NSString)
            }
            return NSItemProvider()
        }
    }
}

extension DesignColor {
    init(gray: Double) {
        self.init(r: gray, g: gray, b: gray, a: 1.0)
    }
}
