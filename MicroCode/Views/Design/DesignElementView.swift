import SwiftUI

struct DesignElementView: View, Equatable {
    let element: DesignElement
    let isSelected: Bool
    
    static func == (lhs: DesignElementView, rhs: DesignElementView) -> Bool {
        lhs.element == rhs.element && lhs.isSelected == rhs.isSelected
    }
    
    var body: some View {
        ZStack {
            if isComplexComponent {
                renderComplexComponent()
            } else if isControlComponent {
                renderControlComponent()
            } else {
                // Main Shape Render
                renderStyledShape()
            }
            
            // Text Content (for simple shapes/buttons)
            if shouldRenderText {
                Text(element.style.textContent)
                    .font(.custom(element.style.fontFamily, size: element.style.fontSize))
                    .fontWeight(fontWeight(from: element.style.fontWeight))
                    .foregroundColor(textColor)
                    .multilineTextAlignment(textAlignment(from: element.style.textAlignment))
                    .allowsHitTesting(false)
            }
            
            // Children (Recursion for Frames)
            if !element.children.isEmpty {
                ForEach(element.children) { child in
                    DesignElementView(element: child, isSelected: false)
                        .position(x: child.x + child.width/2, y: child.y + child.height/2)
                }
            }
        }
        .frame(width: element.width, height: element.height)
        .background(element.type == .deviceFrame ? Color.white : Color.clear)
        .cornerRadius(element.style.cornerRadius)
        .shadow(
            color: element.style.shadow.isEnabled ? element.style.shadow.color.swiftUIColor : .clear,
            radius: element.style.shadow.blur,
            x: element.style.shadow.x,
            y: element.style.shadow.y
        )
        // Opacity applied at view level
        .opacity(element.style.opacity)
    }
    
    private var isComplexComponent: Bool {
        switch element.type {
        case .image, .list, .navigationBar, .tabBar, .menu, .modal, .tooltip: return true
        default: return false
        }
    }
    
    private var isControlComponent: Bool {
        switch element.type {
        case .textField, .checkbox, .switchToggle, .slider, .progress, .radioButton, .avatar, .badge, .divider: return true
        default: return false
        }
    }
    
    private var shouldRenderText: Bool {
        switch element.type {
        case .text, .label, .button, .badge: return true
        case .tooltip: return true // handled in complex
        default: return false
        }
    }
    
    private var textColor: Color {
        if element.type == .button || element.type == .badge { return .white }
        return element.style.stroke?.swiftUIColor ?? .black
    }
    
    // MARK: - Renderers
    
    @ViewBuilder
    private func renderControlComponent() -> some View {
        switch element.type {
        case .textField:
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: element.style.cornerRadius)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: element.style.cornerRadius)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                Text(element.style.textContent.isEmpty ? element.style.placeholder : element.style.textContent)
                    .foregroundColor(element.style.textContent.isEmpty ? .gray : .black)
                    .padding(.horizontal, 8)
                    .font(.system(size: element.style.fontSize))
            }
            
        case .checkbox:
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(element.style.isOn ? Color.blue : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(element.style.isOn ? Color.blue : Color.gray, lineWidth: 1.5)
                    )
                if element.style.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: element.width * 0.7, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            
        case .radioButton:
            ZStack {
                Circle()
                    .stroke(element.style.isOn ? Color.blue : Color.gray, lineWidth: 1.5)
                if element.style.isOn {
                    Circle()
                        .fill(Color.blue)
                        .padding(5)
                }
            }
            
        case .switchToggle:
            ZStack(alignment: element.style.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(element.style.isOn ? Color.green : Color.gray.opacity(0.3))
                Circle()
                    .fill(.white)
                    .padding(2)
                    .shadow(radius: 1)
            }
            
        case .slider:
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
                    .offset(x: 30) // Hardcoded visual for now
            }
            
        case .progress:
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.gray.opacity(0.1))
                Capsule()
                    .fill(Color.blue)
                    .frame(width: element.width * 0.6) // 60% progress
            }
            
        case .avatar:
            Circle()
                .fill(Color.gray.opacity(0.2))
                .overlay(
                    Image(systemName: "person.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: element.width * 0.5))
                )
            
        case .badge:
            Capsule()
                .fill(element.style.fill?.swiftUIColor ?? .red)
            // Text rendered by main body
            
        case .divider:
            Rectangle()
                .fill(Color.gray.opacity(0.2))
            
        default:
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func renderComplexComponent() -> some View {
        switch element.type {
        case .image:
            Rectangle()
                .fill(Color(white: 0.9))
                .overlay(Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.gray))
                .cornerRadius(element.style.cornerRadius)
                
        case .tooltip:
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.8))
                Text(element.style.textContent)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            // Tail simulation (simple overlay for now)
            .overlay(
                Image(systemName: "triangle.fill")
                    .foregroundColor(.black.opacity(0.8))
                    .rotationEffect(.degrees(180))
                    .font(.caption)
                    .offset(y: element.height/2 + 4),
                alignment: .bottom
            )
            
        case .menu:
            VStack(spacing: 0) {
                ForEach(["Item 1", "Item 2", "Item 3"], id: \.self) { item in
                    Text(item)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.white)
                    Divider()
                }
            }
            .background(Color.white)
            .cornerRadius(element.style.cornerRadius)
            .shadow(radius: 5)
            
        case .modal:
            VStack(spacing: 0) {
                HStack {
                    Text("Dialog").font(.headline)
                    Spacer()
                    Image(systemName: "xmark").foregroundColor(.gray)
                }
                .padding()
                .background(Color(white: 0.98))
                
                Divider()
                Spacer()
                Button("Action") {}
                    .buttonStyle(.borderedProminent)
                    .padding()
            }
            .background(Color.white)
            .cornerRadius(element.style.cornerRadius)
            .shadow(radius: 10)
            
        case .list:
            VStack(spacing: 0) {
                ForEach(0..<4) { _ in
                    HStack {
                        Circle().frame(width: 24, height: 24).foregroundColor(.gray.opacity(0.3))
                        RoundedRectangle(cornerRadius: 2).frame(height: 8).foregroundColor(.black.opacity(0.1))
                        Spacer()
                    }
                    .padding(8)
                    Divider()
                }
                Spacer()
            }
            .background(Color.white)
            .cornerRadius(element.style.cornerRadius)
            .overlay(RoundedRectangle(cornerRadius: element.style.cornerRadius).stroke(Color.gray.opacity(0.2)))

        case .navigationBar:
            VStack {
                HStack {
                    Image(systemName: "chevron.left")
                    Spacer()
                    Text("Title").font(.headline)
                    Spacer()
                }
                .padding()
                .background(Color(white: 0.98))
                Divider()
                Spacer()
            }
            
        case .tabBar:
             VStack {
                 Spacer()
                 Divider()
                 HStack {
                     Spacer()
                     Image(systemName: "house.fill").foregroundColor(.blue)
                     Spacer()
                     Image(systemName: "magnifyingglass").foregroundColor(.gray)
                     Spacer()
                     Image(systemName: "person").foregroundColor(.gray)
                     Spacer()
                 }
                 .padding(.vertical, 10)
                 .background(Color(white: 0.98))
             }
            
        default: EmptyView()
        }
    }
    
    // MARK: - Shape Renderer
    
    @ViewBuilder
    private func renderStyledShape() -> some View {
        switch element.type {
        case .card: // Render Card as a Shape (RoundedRect with Shadow)
            applyStyle(to: RoundedRectangle(cornerRadius: element.style.cornerRadius))
        case .rectangle, .frame, .deviceFrame, .text, .label, .group:
            applyStyle(to: RoundedRectangle(cornerRadius: element.style.cornerRadius))
        case .roundedRect:
            applyStyle(to: RoundedRectangle(cornerRadius: element.style.cornerRadius))
        case .ellipse:
            applyStyle(to: Ellipse())
        case .button:
            applyStyle(to: RoundedRectangle(cornerRadius: element.style.cornerRadius))
        case .star:
            applyStyle(to: StarShape(points: 5, innerRatio: 0.5))
        case .polygon:
            applyStyle(to: PolygonShape(sides: 6))
        case .line:
            applyStyle(to: Rectangle())
        case .arrow:
            applyStyle(to: ArrowShape())
        default:
            applyStyle(to: Rectangle())
        }
    }
    
    private func applyStyle<S: Shape>(to shape: S) -> some View {
        shape
            .fill(element.style.fill?.swiftUIColor ?? .clear)
            .overlay(
                shape
                    .stroke(element.style.stroke?.swiftUIColor ?? .clear, lineWidth: element.style.strokeWidth)
            )
    }
    
    // MARK: - Helpers
    
    private func fontWeight(from string: String) -> Font.Weight {
        switch string.lowercased() {
        case "bold": return .bold
        case "semibold": return .semibold
        case "medium": return .medium
        case "light": return .light
        case "thin": return .thin
        default: return .regular
        }
    }
    
    private func textAlignment(from string: String) -> TextAlignment {
        switch string.lowercased() {
        case "center": return .center
        case "right": return .trailing
        default: return .leading
        }
    }
}

// MARK: - Custom Shapes (Unchanged)
struct StarShape: Shape {
    let points: Int
    let innerRatio: Double
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let angle = .pi / Double(points)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        for i in 0..<points * 2 {
            let radius = (i % 2 == 0) ? outerRadius : innerRadius
            let x = center.x + radius * cos(Double(i) * angle - .pi / 2)
            let y = center.y + radius * sin(Double(i) * angle - .pi / 2)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath(); return path
    }
}
struct PolygonShape: Shape {
    let sides: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.width / 2, y: rect.height / 2)
        let radius = min(rect.width, rect.height) / 2
        let angle = 2 * .pi / Double(sides)
        for i in 0..<sides {
            let x = center.x + radius * cos(Double(i) * angle - .pi / 2)
            let y = center.y + radius * sin(Double(i) * angle - .pi / 2)
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath(); return path
    }
}
struct ArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height / 2))
        path.addLine(to: CGPoint(x: rect.width * 2/3, y: rect.height / 2))
        path.addLine(to: CGPoint(x: rect.width * 2/3, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height / 2))
        path.addLine(to: CGPoint(x: rect.width * 2/3, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 2/3, y: rect.height / 2))
        path.closeSubpath(); return path
    }
}
