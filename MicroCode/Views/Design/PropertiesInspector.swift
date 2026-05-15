import SwiftUI

struct PropertiesInspector: View {
    @EnvironmentObject var designStore: DesignStore
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Design")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                if let element = designStore.selectedElement() {
                    // 1. Layout
                    PropertySection(title: "Layout") {
                        HStack {
                            NumberField(label: "X", value: Binding(get: { element.x }, set: { v in update(element) { $0.x = v } }))
                            NumberField(label: "Y", value: Binding(get: { element.y }, set: { v in update(element) { $0.y = v } }))
                        }
                        HStack {
                            NumberField(label: "W", value: Binding(get: { element.width }, set: { v in update(element) { $0.width = v } }))
                            NumberField(label: "H", value: Binding(get: { element.height }, set: { v in update(element) { $0.height = v } }))
                        }
                        HStack {
                            NumberField(label: "deg", value: Binding(get: { CGFloat(element.rotation) }, set: { v in update(element) { $0.rotation = Double(v) } }))
                            NumberField(label: "R", value: Binding(get: { element.style.cornerRadius }, set: { v in update(element) { $0.style.cornerRadius = v } }))
                        }
                    }
                    
                    // 2. Layer (Opacitiy, Visibility)
                    PropertySection(title: "Layer") {
                        HStack {
                            Text("Opacity").font(.caption).foregroundColor(.secondary)
                            Slider(value: Binding(get: { element.style.opacity }, set: { v in update(element) { $0.style.opacity = v } }), in: 0...1)
                            Text("\(Int(element.style.opacity * 100))%")
                                .font(.caption)
                                .frame(width: 30)
                        }
                    }
                    
                    Divider()
                    
                    // 3. Fill
                    PropertySection(title: "Fill") {
                        HStack {
                            ColorPicker("Color", selection: colorBinding(for: element, keyPath: \.style.fill))
                                .labelsHidden()
                            Spacer()
                            Text(hexString(for: element.style.fill))
                                .font(.system(.caption, design: .monospaced))
                                .padding(4)
                                .background(Color.black.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                    
                    // 4. Stroke
                    PropertySection(title: "Stroke") {
                        VStack(spacing: 8) {
                            HStack {
                                Toggle("", isOn: Binding(get: { element.style.stroke != nil }, set: { on in
                                    update(element) { $0.style.stroke = on ? .black : nil }
                                }))
                                .labelsHidden()
                                
                                if element.style.stroke != nil {
                                    ColorPicker("", selection: colorBinding(for: element, keyPath: \.style.stroke))
                                        .labelsHidden()
                                    Spacer()
                                    NumberField(label: "", value: Binding(get: { element.style.strokeWidth }, set: { v in update(element) { $0.style.strokeWidth = v } }))
                                        .frame(width: 60)
                                } else {
                                    Text("None").foregroundColor(.secondary).font(.caption)
                                    Spacer()
                                }
                            }
                        }
                    }
                    
                    // 5. Typography (if text)
                    if isText(element) {
                        Divider()
                        PropertySection(title: "Typography") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Content", text: Binding(get: { element.style.textContent }, set: { v in update(element) { $0.style.textContent = v } }))
                                    .textFieldStyle(.roundedBorder)
                                
                                HStack {
                                    Picker("", selection: Binding(get: { element.style.fontFamily }, set: { v in update(element) { $0.style.fontFamily = v } })) {
                                        Text("Inter").tag("Inter")
                                        Text("SF Pro").tag("SF Pro Text")
                                        Text("Helvetica").tag("Helvetica Neue")
                                        Text("Times").tag("Times New Roman")
                                        Text("Courier").tag("Courier New")
                                    }
                                    .labelsHidden()
                                    
                                    NumberField(label: "", value: Binding(get: { element.style.fontSize }, set: { v in update(element) { $0.style.fontSize = v } }))
                                        .frame(width: 50)
                                }
                                
                                Picker("Weight", selection: Binding(get: { element.style.fontWeight }, set: { v in update(element) { $0.style.fontWeight = v } })) {
                                    Text("Regular").tag("Regular")
                                    Text("Bold").tag("Bold")
                                    Text("Light").tag("Light")
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                    }
                    
                    Divider()
                    
                    // 6. Effects (Shadow)
                    PropertySection(title: "Effects") {
                        HStack {
                            Toggle("Shadow", isOn: Binding(get: { element.style.shadow.isEnabled }, set: { v in update(element) { $0.style.shadow.isEnabled = v } }))
                                .font(.caption)
                            Spacer()
                        }
                        if element.style.shadow.isEnabled {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text("X").font(.caption)
                                    NumberField(label: "", value: Binding(get: { element.style.shadow.x }, set: { v in update(element) { $0.style.shadow.x = v } }))
                                    Text("Y").font(.caption)
                                    NumberField(label: "", value: Binding(get: { element.style.shadow.y }, set: { v in update(element) { $0.style.shadow.y = v } }))
                                }
                                HStack {
                                    Text("Blur").font(.caption)
                                    NumberField(label: "", value: Binding(get: { element.style.shadow.blur }, set: { v in update(element) { $0.style.shadow.blur = v } }))
                                }
                            }
                        }
                    }
                    
                } else {
                    Text("No Selection")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
                Spacer()
            }
            .padding()
        }
        .frame(width: 250)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(Rectangle().frame(width: 1).foregroundColor(Color(nsColor: .separatorColor)), alignment: .leading)
    }
    
    // MARK: - Helpers
    
    func update(_ element: DesignElement, _ transform: (inout DesignElement) -> Void) {
        var newElement = element
        transform(&newElement)
        designStore.updateElement(newElement)
    }
    
    func isText(_ element: DesignElement) -> Bool {
        return element.type == .text || element.type == .label || element.type == .button
    }
    
    func colorBinding(for element: DesignElement, keyPath: WritableKeyPath<DesignElement, DesignColor?>) -> Binding<Color> {
        Binding(
            get: {
                element[keyPath: keyPath]?.swiftUIColor ?? .clear
            },
            set: { newColor in
                if let nsColor = NSColor(newColor).usingColorSpace(.sRGB) {
                     let designColor = DesignColor(
                        r: nsColor.redComponent,
                        g: nsColor.greenComponent,
                        b: nsColor.blueComponent,
                        a: nsColor.alphaComponent
                     )
                     update(element) {
                         $0[keyPath: keyPath] = designColor
                     }
                }
            }
        )
    }
    
    func hexString(for color: DesignColor?) -> String {
        guard let color = color else { return "Transparent" }
        let r = Int(color.r * 255)
        let g = Int(color.g * 255)
        let b = Int(color.b * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Components

struct PropertySection<Content: View>: View {
    let title: String
    let content: () -> Content
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
            content()
        }
    }
}

struct NumberField: View {
    let label: String
    @Binding var value: CGFloat
    
    var body: some View {
        HStack(spacing: 4) {
            if !label.isEmpty {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            TextField("", value: $value, formatter: NumberFormatter.design)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .multilineTextAlignment(.trailing)
        }
    }
}

extension NumberFormatter {
    static var design: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f
    }
}
