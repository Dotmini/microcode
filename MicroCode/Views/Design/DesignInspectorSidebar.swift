import SwiftUI

struct DesignInspectorSidebar: View {
    @ObservedObject var designStore: DesignStore
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Design").font(.headline)
                Spacer()
                Image(systemName: "slider.horizontal.3")
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                if let element = designStore.selectedElement() {
                    VStack(spacing: 20) {
                        
                        // 1. Layout Section
                        InspectorSection(title: "Layout") {
                            HStack {
                                PropertyField(label: "X", value: Binding(get: { element.x }, set: { designStore.updateElement(element.copyWith(x: $0)) }))
                                PropertyField(label: "Y", value: Binding(get: { element.y }, set: { designStore.updateElement(element.copyWith(y: $0)) }))
                            }
                            HStack {
                                PropertyField(label: "W", value: Binding(get: { element.width }, set: { designStore.updateElement(element.copyWith(width: $0)) }))
                                PropertyField(label: "H", value: Binding(get: { element.height }, set: { designStore.updateElement(element.copyWith(height: $0)) }))
                            }
                            // Corner Radius
                            HStack {
                                Text("Radius")
                                Spacer()
                                TextField("0", value: Binding(get: { element.style.cornerRadius }, set: { 
                                    var newStyle = element.style
                                    newStyle.cornerRadius = $0
                                    designStore.updateElement(element.copyWith(style: newStyle))
                                }), formatter: NumberFormatter())
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Text("Rotation")
                                Spacer()
                                TextField("0°", value: Binding(get: { element.rotation }, set: { designStore.updateElement(element.copyWith(rotation: $0)) }), formatter: NumberFormatter())
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        
                        Divider()
                        
                        // 2. Style Section
                        InspectorSection(title: "Layer") {
                            HStack {
                                Text("Opacity")
                                Spacer()
                                Slider(value: Binding(get: { element.style.opacity }, set: { 
                                    var newStyle = element.style
                                    newStyle.opacity = $0
                                    designStore.updateElement(element.copyWith(style: newStyle))
                                }), in: 0...1)
                                    .frame(width: 100)
                                Text("\(Int(element.style.opacity * 100))%")
                                    .font(.caption).monospacedDigit()
                            }
                            
                            // Fill Color
                            ColorPicker("Fill", selection: Binding(get: { element.style.fill?.swiftUIColor ?? .clear }, set: { newColor in
                                var newStyle = element.style
                                if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                                    newStyle.fill = DesignColor(r: nsColor.redComponent, g: nsColor.greenComponent, b: nsColor.blueComponent, a: nsColor.alphaComponent)
                                    designStore.updateElement(element.copyWith(style: newStyle))
                                }
                            }))
                            
                            // Border Section (New)
                            Divider()
                            HStack {
                                Text("Border")
                                Spacer()
                                TextField("0", value: Binding(get: { element.style.strokeWidth }, set: {
                                    var newStyle = element.style
                                    newStyle.strokeWidth = $0
                                    // Auto-enable stroke if width > 0 and no stroke set
                                    if $0 > 0 && newStyle.stroke == nil {
                                         newStyle.stroke = .black
                                    }
                                    designStore.updateElement(element.copyWith(style: newStyle))
                                }), formatter: NumberFormatter())
                                .frame(width: 40)
                                .textFieldStyle(.roundedBorder)
                                
                                ColorPicker("", selection: Binding(get: { element.style.stroke?.swiftUIColor ?? .clear }, set: { newColor in
                                    var newStyle = element.style
                                    if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                                        newStyle.stroke = DesignColor(r: nsColor.redComponent, g: nsColor.greenComponent, b: nsColor.blueComponent, a: nsColor.alphaComponent)
                                        designStore.updateElement(element.copyWith(style: newStyle))
                                    }
                                }))
                                .labelsHidden()
                            }
                        }
                        
                        Divider()
                        
                        // 3. Typography Section
                        if element.type == .text || element.type == .button || element.type == .label {
                            InspectorSection(title: "Typography") {
                                TextField("Content", text: Binding(get: { element.style.textContent }, set: {
                                    var newStyle = element.style
                                    newStyle.textContent = $0
                                    designStore.updateElement(element.copyWith(style: newStyle))
                                }))
                                .textFieldStyle(.roundedBorder)
                                
                                HStack {
                                    Text("Font")
                                    Spacer()
                                    Menu {
                                        Button("Inter") { updateFont(element, "Inter") }
                                        Button("System") { updateFont(element, "System") }
                                        Button("SF Pro") { updateFont(element, "SF Pro Display") }
                                        Button("Helvetica") { updateFont(element, "Helvetica") }
                                        Button("Courier") { updateFont(element, "Courier New") }
                                    } label: {
                                        Text(element.style.fontFamily)
                                            .foregroundColor(.primary)
                                            .frame(width: 80, alignment: .trailing)
                                    }
                                }
                                
                                HStack {
                                    Text("Size")
                                    Spacer()
                                    TextField("16", value: Binding(get: { element.style.fontSize }, set: {
                                        var newStyle = element.style
                                        newStyle.fontSize = $0
                                        designStore.updateElement(element.copyWith(style: newStyle))
                                    }), formatter: NumberFormatter())
                                    .frame(width: 50)
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                        
                    }
                    .padding()
                } else {
                    // Empty State
                    VStack(spacing: 15) {
                        Spacer()
                        Image(systemName: "square.dashed.inset.filled")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Selection")
                            .font(.callout)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(height: 300)
                }
            }
        }
    }
    
    private func updateFont(_ element: DesignElement, _ font: String) {
        var newStyle = element.style
        newStyle.fontFamily = font
        designStore.updateElement(element.copyWith(style: newStyle))
    }
}

// Helpers
struct InspectorSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            content
        }
    }
}

struct PropertyField: View {
    let label: String
    @Binding var value: CGFloat
    
    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary).font(.caption)
            TextField("", value: $value, formatter: NumberFormatter())
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
        }
    }
}

// copyWith moved to DesignModels.swift
