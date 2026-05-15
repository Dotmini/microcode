import Foundation

class DesignCodeGenerator {
    static let shared = DesignCodeGenerator()
    
    func generate(for project: DesignProject) -> String {
        guard let page = project.pages.first else { return "" }
        
        switch project.framework {
        case .swiftui:
            return generateSwiftUI(page: page)
        case .pyqt:
            return generatePyQt(page: page)
        case .tkinter:
            return generateTkinter(page: page)
        }
    }
    
    // MARK: - SwiftUI
    
    private func generateSwiftUI(page: DesignPage) -> String {
        var code = "import SwiftUI\n\nstruct DesignedView: View {\n    var body: some View {\n        ZStack {\n"
        
        // Background
        code += "            Color(red: \(page.backgroundColor.r), green: \(page.backgroundColor.g), blue: \(page.backgroundColor.b)).ignoresSafeArea()\n"
        
        for element in page.elements {
            code += generateSwiftUIElement(element, indent: "            ") + "\n"
        }
        
        code += "        }\n    }\n}"
        return code
    }
    
    private func generateSwiftUIElement(_ element: DesignElement, indent: String) -> String {
        var elCode = ""
        switch element.type {
        case .rectangle:
            elCode = "RoundedRectangle(cornerRadius: \(element.style.cornerRadius))\n\(indent)    .fill(Color(red: \(element.style.fill?.r ?? 0), green: \(element.style.fill?.g ?? 0), blue: \(element.style.fill?.b ?? 0)))"
        case .button:
            elCode = "Button(\"\(element.style.textContent)\") { }"
        case .label, .text:
            elCode = "Text(\"\(element.style.textContent)\")"
        case .image:
            elCode = "Image(systemName: \"photo\").resizable().aspectRatio(contentMode: .fit).foregroundColor(.gray)"
        case .card:
            elCode = "RoundedRectangle(cornerRadius: \(element.style.cornerRadius))\n\(indent)    .fill(Color(white: 0.95))\n\(indent)    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)"
        case .list:
            elCode = "List(0..<5) { i in Text(\"Item \\(i)\") }"
        case .navigationBar:
            elCode = "VStack { HStack { Image(systemName: \"chevron.left\"); Spacer(); Text(\"Title\").font(.headline); Spacer() }; Divider() }.frame(height: 44)"
        case .tabBar:
            elCode = "TabView { Text(\"Home\").tabItem { Label(\"Home\", systemImage: \"house\") }; Text(\"Settings\").tabItem { Label(\"Settings\", systemImage: \"gear\") } }"
        default:
            elCode = "Rectangle() // \(element.name)"
        }
        
        // Frame modifiers (Absolute positioning for now, ideally strictly layout based)
        // SwiftUI ZStack allows absolute offsets
        elCode += "\n\(indent)    .frame(width: \(element.width), height: \(element.height))"
        elCode += "\n\(indent)    .position(x: \(element.x + element.width/2), y: \(element.y + element.height/2))"
        
        return indent + elCode
    }
    
    // MARK: - PyQt6
    
    private func generatePyQt(page: DesignPage) -> String {
        var code = """
import sys
from PyQt6.QtWidgets import QApplication, QMainWindow, QPushButton, QLabel, QWidget
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("\(page.name)")
        self.setGeometry(100, 100, 800, 600)
        
        # Central Widget
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        central_widget.setStyleSheet("background-color: rgb(\(Int(page.backgroundColor.r*255)), \(Int(page.backgroundColor.g*255)), \(Int(page.backgroundColor.b*255)));")
        
"""
        
        for element in page.elements {
            code += generatePyQtElement(element) + "\n"
        }
        
        code += """

app = QApplication(sys.argv)
window = MainWindow()
window.show()
sys.exit(app.exec())
"""
        return code
    }
    
    private func generatePyQtElement(_ element: DesignElement) -> String {
        var code = ""
        let name = "self.el_\(element.id.uuidString.replacingOccurrences(of: "-", with: "_").prefix(8))"
        
        switch element.type {
        case .button:
            code = "        \(name) = QPushButton(\"\(element.style.textContent)\", self)"
        case .label, .text:
            code = "        \(name) = QLabel(\"\(element.style.textContent)\", self)"
        case .image:
            code = "        \(name) = QLabel(\"Image\", self); \(name).setStyleSheet(\"background-color: #eee; border: 1px solid #ccc;\"); \(name).setAlignment(Qt.AlignmentFlag.AlignCenter)"
        case .list:
            code = "        from PyQt6.QtWidgets import QListWidget\n        \(name) = QListWidget(self); \(name).addItems([\"Item 1\", \"Item 2\", \"Item 3\"])"
        case .card:
             code = "        \(name) = QWidget(self); \(name).setStyleSheet(\"background-color: white; border-radius: 10px; border: 1px solid #ddd;\")"
        default:
            // Generic widget for shapes?
            code = "        \(name) = QLabel(\"\(element.type.rawValue)\", self) # Placeholder"
        }
        
        code += "\n        \(name).setGeometry(\(Int(element.x)), \(Int(element.y)), \(Int(element.width)), \(Int(element.height)))"
        code += "\n        \(name).show()"
        return code
    }

    // MARK: - Tkinter
    
    private func generateTkinter(page: DesignPage) -> String {
        var code = """
import tkinter as tk

root = tk.Tk()
root.title("\(page.name)")
root.geometry("800x600")
root.configure(bg="#\(toHex(page.backgroundColor))")

canvas = tk.Canvas(root, width=800, height=600, bg="#\(toHex(page.backgroundColor))", highlightthickness=0)
canvas.pack(fill="both", expand=True)

"""
        for element in page.elements {
            code += generateTkinterElement(element) + "\n"
        }
        
        code += "\nroot.mainloop()"
        return code
    }
    
    private func generateTkinterElement(_ element: DesignElement) -> String {
        // Tkinter absolute positioning usually uses place()
        // Or canvas.create_window for widgets inside canvas
        
        var code = ""
        let name = "el_\(element.id.uuidString.replacingOccurrences(of: "-", with: "_").prefix(8))"

        switch element.type {
        case .button:
            code = """
        \(name) = tk.Button(root, text="\(element.style.textContent)")
        \(name).place(x=\(element.x), y=\(element.y), width=\(element.width), height=\(element.height))
"""
        case .label, .text:
            code = """
        \(name) = tk.Label(root, text="\(element.style.textContent)", bg="#ffffff")
        \(name).place(x=\(element.x), y=\(element.y), width=\(element.width), height=\(element.height))
"""
        case .rectangle:
            code = "canvas.create_rectangle(\(element.x), \(element.y), \(element.x + element.width), \(element.y + element.height), fill=\"#\(toHex(element.style.fill ?? .black))\")"
        case .list:
            code = """
        \(name) = tk.Listbox(root)
        for i in range(5): \(name).insert(tk.END, f"Item {i}")
        \(name).place(x=\(element.x), y=\(element.y), width=\(element.width), height=\(element.height))
"""
        case .image:
            code = """
        \(name) = tk.Label(root, text="[Image]", bg="#eee", relief="sunken")
        \(name).place(x=\(element.x), y=\(element.y), width=\(element.width), height=\(element.height))
"""
        default:
             code = "# Unsupported: \(element.type)"
        }
        
        return code
    }
    
    func toHex(_ color: DesignColor) -> String {
        let r = Int(color.r * 255)
        let g = Int(color.g * 255)
        let b = Int(color.b * 255)
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
