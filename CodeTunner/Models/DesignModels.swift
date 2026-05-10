import Foundation
import SwiftUI
//Tirawat Nantamas | Dotmini Software
// MARK: - Enums

enum DesignElementType: String, Codable, CaseIterable {
    // Containers
    case deviceFrame = "Device Frame"
    case frame = "Frame" // Logic Frame / Group
    case group = "Group"
    
    // Shapes
    case rectangle = "Rectangle"
    case roundedRect = "Rounded Rectangle"
    case ellipse = "Ellipse" // Circle
    case star = "Star"
    case polygon = "Polygon"
    case line = "Line"
    case arrow = "Arrow"
    
    // Content
    case text = "Text"
    case image = "Image"
    
    // GUI Components
    case button = "Button"
    case label = "Label"
    case textField = "TextField" // Input Field
    case checkbox = "Checkbox"
    case switchToggle = "Switch"
    case slider = "Slider"
    case progress = "Progress Bar"
    
    // Advanced Components
    case card = "Card"
    case list = "List"
    case navigationBar = "Navigation Bar"
    case tabBar = "Tab Bar"
    
    // Phase 14 Expansion
    case avatar = "Avatar"
    case badge = "Badge"
    case radioButton = "Radio Button"
    case tooltip = "Tooltip"
    case menu = "Menu"
    case modal = "Modal / Dialog"
    case divider = "Divider"
    
    var icon: String {
        switch self {
        case .deviceFrame: return "iphone"
        case .frame: return "square.dashed"
        case .group: return "square.on.square.dashed"
        case .rectangle: return "rectangle"
        case .roundedRect: return "rectangle.roundedtop"
        case .ellipse: return "circle"
        case .star: return "star"
        case .polygon: return "hexagon"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .text: return "text.cursor"
        case .image: return "photo"
        case .button: return "cursorarrow.click.2"
        case .label: return "text.alignleft"
        case .textField: return "character.cursor.ibeam"
        case .checkbox: return "checkmark.square"
        case .switchToggle: return "switch.2"
        case .slider: return "slider.horizontal.3"
        case .progress: return "chart.bar.fill"
        case .card: return "rectangle.portrait.on.rectangle.portrait"
        case .list: return "list.bullet.rectangle"
        case .navigationBar: return "menubar.rectangle"
        case .tabBar: return "squareshape.split.3x3"
        // Expansion
        case .avatar: return "person.crop.circle"
        case .badge: return "capsule.fill"
        case .radioButton: return "circle.inset.filled"
        case .tooltip: return "message.fill"
        case .menu: return "list.bullet.rectangle"
        case .modal: return "macwindow"
        case .divider: return "minus"
        }
    }
}

enum DesignDeviceType: String, Codable, CaseIterable, Identifiable {
    case iPhone15Pro = "iPhone 15 Pro"
    case iPhone15ProMax = "iPhone 15 Pro Max"
    case iPhone16Pro = "iPhone 16 Pro"
    case iPhone16ProMax = "iPhone 16 Pro Max"
    case iPadAir = "iPad Air"
    case iPadPro11 = "iPad Pro 11"
    case iPadPro12_9 = "iPad Pro 12.9"
    case macBookAir = "MacBook Air"
    case macBookPro16 = "MacBook Pro 16"
    case desktop = "Desktop (1440)"
    case custom = "Custom"
    
    var id: String { rawValue }
    
    var size: CGSize {
        switch self {
        case .iPhone15Pro, .iPhone16Pro: return CGSize(width: 393, height: 852)
        case .iPhone15ProMax, .iPhone16ProMax: return CGSize(width: 440, height: 956)
        case .iPadAir: return CGSize(width: 820, height: 1180)
        case .iPadPro11: return CGSize(width: 834, height: 1194)
        case .iPadPro12_9: return CGSize(width: 1024, height: 1366)
        case .macBookAir: return CGSize(width: 1280, height: 832)
        case .macBookPro16: return CGSize(width: 1728, height: 1117)
        case .desktop: return CGSize(width: 1440, height: 1024)
        case .custom: return CGSize(width: 800, height: 600)
        }
    }
}

enum DesignFramework: String, Codable, CaseIterable {
    case swiftui = "SwiftUI"
    case pyqt = "PyQt6"
    case tkinter = "Tkinter"
}

// MARK: - Style Models

struct DesignColor: Codable, Equatable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double // Opacity 0-1
    
    static let white = DesignColor(r: 1, g: 1, b: 1, a: 1)
    static let black = DesignColor(r: 0, g: 0, b: 0, a: 1)
    static let gray = DesignColor(r: 0.5, g: 0.5, b: 0.5, a: 1)
    static let clear = DesignColor(r: 0, g: 0, b: 0, a: 0)
    static let red = DesignColor(r: 1, g: 0, b: 0, a: 1)
    static let blue = DesignColor(r: 0, g: 0, b: 1, a: 1)
    
    var swiftUIColor: Color {
        Color(red: r, green: g, blue: b, opacity: a)
    }
    
    // Hex helper
    init(hex: String) {
        let r, g, b, a: Double
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b, a) = (Double((int >> 8) * 17) / 255.0, Double((int >> 4 & 0xF) * 17) / 255.0, Double((int & 0xF) * 17) / 255.0, 1.0)
        case 6: // RGB (24-bit)
            (r, g, b, a) = (Double((int >> 16) & 0xFF) / 255.0, Double((int >> 8) & 0xFF) / 255.0, Double(int & 0xFF) / 255.0, 1.0)
        default: // ARGB (32-bit)
            (r, g, b, a) = (Double((int >> 16) & 0xFF) / 255.0, Double((int >> 8) & 0xFF) / 255.0, Double(int & 0xFF) / 255.0, Double((int >> 24) & 0xFF) / 255.0)
        }
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    
    init(r: Double, g: Double, b: Double, a: Double) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
}

struct DesignShadow: Codable, Equatable {
    var color: DesignColor = DesignColor(r: 0, g: 0, b: 0, a: 0.25)
    var x: CGFloat = 0
    var y: CGFloat = 4
    var blur: CGFloat = 4
    var spread: CGFloat = 0
    var isEnabled: Bool = false
}

struct DesignGradient: Codable, Equatable {
    // Basic linear gradient for now
    var colors: [DesignColor] = [.white, .black]
    var startPoint: UnitPointWrapper = .top
    var endPoint: UnitPointWrapper = .bottom
    var isEnabled: Bool = false
}

// Wrapper for UnitPoint codability
struct UnitPointWrapper: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    
    static let top = UnitPointWrapper(x: 0.5, y: 0)
    static let bottom = UnitPointWrapper(x: 0.5, y: 1)
    static let leading = UnitPointWrapper(x: 0, y: 0.5)
    static let trailing = UnitPointWrapper(x: 1, y: 0.5)
}

struct DesignStyle: Codable, Equatable {
    // Fill
    var fill: DesignColor? = .white
    var gradient: DesignGradient? = nil
    
    // Stroke/Border
    var stroke: DesignColor? = nil // nil = no stroke
    var strokeWidth: CGFloat = 1
    
    // Layout / Shape
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1.0
    
    // Effects
    var shadow: DesignShadow = DesignShadow()
    
    // Typography
    var fontSize: CGFloat = 16
    var fontFamily: String = "Inter" // Modern default
    var fontWeight: String = "Regular"
    var textAlignment: String = "left" // left, center, right
    var textContent: String = "Text"
    var isEditable: Bool = false
    
    // Component Specific
    var placeholder: String = "Enter text..."
    var isOn: Bool = true
}

// MARK: - Core Element

struct DesignElement: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var type: DesignElementType
    
    // Frame
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
    var rotation: Double = 0
    
    // Hierarchy
    var children: [DesignElement] = []
    var parentId: UUID?
    
    // Metadata
    var isLocked: Bool = false
    var isVisible: Bool = true
    var isExpanded: Bool = true // For layer list
    
    // Look & Feel
    var style: DesignStyle = DesignStyle()
    
    // Convenience
    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.size.width
            height = newValue.size.height
        }
    }
    
    // Factory
    static func create(type: DesignElementType, x: CGFloat, y: CGFloat) -> DesignElement {
        var width: CGFloat = 100
        var height: CGFloat = 100
        var style = DesignStyle()
        
        switch type {
        case .deviceFrame:
            width = 393; height = 852 // iPhone 15 Pro default
            style.fill = .white
            style.stroke = DesignColor(r: 0.9, g: 0.9, b: 0.9, a: 1)
        case .rectangle:
            style.fill = DesignColor(r: 0.85, g: 0.85, b: 0.85, a: 1)
        case .roundedRect:
            style.fill = DesignColor(r: 0.85, g: 0.85, b: 0.85, a: 1)
            style.cornerRadius = 16
        case .ellipse:
            style.fill = DesignColor(r: 0.85, g: 0.85, b: 0.85, a: 1)
            style.cornerRadius = 50 // Circle-ish
        case .text:
            width = 120; height = 40
            style.fill = .black
            style.textContent = "Hello World"
            style.fontSize = 24
        case .button:
            width = 120; height = 44
            style.fill = DesignColor(r: 0, g: 0.478, b: 1, a: 1) // System Blue
            style.cornerRadius = 8
            style.textContent = "Button"
            style.stroke = nil
        case .label:
            width = 100; height = 30
            style.fill = .black
            style.textContent = "Label"
            style.fontSize = 14
        case .star:
            width = 100; height = 100
            style.fill = DesignColor(r: 1, g: 0.8, b: 0, a: 1) // Gold
            height = 2
            style.fill = .black
        case .image:
            width = 200; height = 150
            style.fill = DesignColor(r: 0.9, g: 0.9, b: 0.9, a: 1)
            style.textAlignment = "center" // For placeholder text
        case .card:
            width = 300; height = 200
            style.fill = .white
            style.cornerRadius = 12
            style.shadow = DesignShadow(color: DesignColor(r: 0, g: 0, b: 0, a: 0.1), x: 0, y: 4, blur: 10, spread: 0, isEnabled: true)
        case .list:
            width = 300; height = 400
            style.fill = .white
            style.stroke = DesignColor(r: 0.9, g: 0.9, b: 0.9, a: 1)
        case .navigationBar:
            width = 393; height = 88 // Standard iOS Nav Bar height (approx)
            style.fill = DesignColor(r: 0.98, g: 0.98, b: 0.98, a: 1)
            style.stroke = DesignColor(r: 0.8, g: 0.8, b: 0.8, a: 1) // Bottom border simulated
        case .tabBar:
            width = 393; height = 83 // Standard iOS Tab Bar height
            style.fill = DesignColor(r: 0.98, g: 0.98, b: 0.98, a: 1)
            style.stroke = DesignColor(r: 0.8, g: 0.8, b: 0.8, a: 1) // Top border simulated
            
        // Phase 14 Expansion
        case .avatar:
            width = 60; height = 60
            style.cornerRadius = 30
            style.fill = DesignColor(r: 0.8, g: 0.8, b: 0.8, a: 1)
        case .badge:
            width = 60; height = 24
            style.cornerRadius = 12
            style.fill = DesignColor(r: 1, g: 0.23, b: 0.18, a: 1) // Red
            style.textContent = "New"
            style.fontSize = 12
            style.fill = .red // Helper needed but using literal for now
        case .radioButton:
            width = 20; height = 20
            style.cornerRadius = 10
            style.stroke = DesignColor(r: 0, g: 0.47, b: 1, a: 1)
            style.strokeWidth = 2
            style.fill = .clear
        case .tooltip:
            width = 100; height = 40
            style.fill = DesignColor(r: 0.2, g: 0.2, b: 0.2, a: 0.9)
            style.textContent = "Tooltip"
            style.cornerRadius = 4
        case .menu:
            width = 200; height = 150
            style.fill = .white
            style.shadow = DesignShadow(color: DesignColor(r: 0, g: 0, b: 0, a: 0.2), x: 0, y: 4, blur: 10, spread: 0, isEnabled: true)
            style.cornerRadius = 8
        case .modal:
            width = 400; height = 300
            style.fill = .white
            style.cornerRadius = 16
            style.shadow = DesignShadow(color: DesignColor(r: 0, g: 0, b: 0, a: 0.3), x: 0, y: 10, blur: 20, spread: 0, isEnabled: true)
        case .divider:
            width = 200; height = 1
            style.fill = DesignColor(r: 0.9, g: 0.9, b: 0.9, a: 1)
        default:
            break
        }
        
        return DesignElement(
            name: "\(type.rawValue) \(Int.random(in: 1...100))",
            type: type,
            x: x,
            y: y,
            width: width,
            height: height,
            style: style
        )
    }
    
    static func createFrame(type: DesignDeviceType) -> DesignElement {
        var element = create(type: .deviceFrame, x: 100, y: 100)
        element.name = type.rawValue
        element.width = type.size.width
        element.height = type.size.height
        return element
    }
}

// MARK: - Project Structure

struct DesignPage: Identifiable, Codable {
    var id = UUID()
    var name: String
    var elements: [DesignElement] = []
    var backgroundColor: DesignColor = DesignColor(r: 0.96, g: 0.96, b: 0.96, a: 1) // Figma canvas gray
    var guides: [CGFloat] = [] // Future: Guide lines
}

struct DesignProject: Identifiable, Codable {
    var id = UUID()
    var name: String
    var pages: [DesignPage] = []
    var activePageId: UUID?
    var framework: DesignFramework = .swiftui
}

extension DesignElement {
    func copyWith(x: CGFloat? = nil, y: CGFloat? = nil, width: CGFloat? = nil, height: CGFloat? = nil, rotation: Double? = nil, style: DesignStyle? = nil) -> DesignElement {
        var copy = self
        if let x = x { copy.x = x }
        if let y = y { copy.y = y }
        if let width = width { copy.width = width }
        if let height = height { copy.height = height }
        if let rotation = rotation { copy.rotation = rotation }
        if let style = style { copy.style = style }
        return copy
    }
}
