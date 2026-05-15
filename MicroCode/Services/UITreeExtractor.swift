//
//  UITreeExtractor.swift
//  MicroCode
//
//  Extracts UI tree from SwiftUI views for element selection
//  Maps preview elements back to source code locations
//
//  SPU AI CLUB - Dotmini Software
//

import SwiftUI

// MARK: - UI Tree Node

/// Represents a node in the UI tree
struct UITreeNode: Identifiable, Codable {
    let id: String
    let type: String
    let frame: CGRect
    let properties: [String: String]
    let children: [UITreeNode]
    let sourceLocation: SourceLocation?
    
    struct SourceLocation: Codable {
        let file: String
        let line: Int
        let column: Int
    }
}

// Redundant CGRect: Codable extension removed (CoreGraphics provides it)
// extension CGRect: Codable { ... }


// MARK: - UI Tree Extractor

/// Extracts UI tree from SwiftUI source code
class UITreeExtractor {
    
    /// Parse SwiftUI code and extract UI tree structure
    static func extractTree(from code: String) -> UITreeNode {
        var lineNumber = 0
        let lines = code.components(separatedBy: .newlines)
        
        var rootChildren: [UITreeNode] = []
        
        for (index, line) in lines.enumerated() {
            lineNumber = index + 1
            
            // Detect SwiftUI components
            if let node = parseComponent(line: line, lineNumber: lineNumber) {
                rootChildren.append(node)
            }
        }
        
        return UITreeNode(
            id: "root",
            type: "View",
            frame: CGRect(x: 0, y: 0, width: 393, height: 852),
            properties: [:],
            children: rootChildren,
            sourceLocation: nil
        )
    }
    
    private static func parseComponent(line: String, lineNumber: Int) -> UITreeNode? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        // VStack
        if trimmed.hasPrefix("VStack") {
            return UITreeNode(
                id: "vstack_\(lineNumber)",
                type: "VStack",
                frame: CGRect(x: 0, y: 0, width: 300, height: 100),
                properties: extractProperties(from: trimmed),
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // HStack
        if trimmed.hasPrefix("HStack") {
            return UITreeNode(
                id: "hstack_\(lineNumber)",
                type: "HStack",
                frame: CGRect(x: 0, y: 0, width: 300, height: 44),
                properties: extractProperties(from: trimmed),
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // Text
        if trimmed.hasPrefix("Text(") {
            let textContent = extractStringLiteral(from: trimmed)
            return UITreeNode(
                id: "text_\(lineNumber)",
                type: "Text",
                frame: CGRect(x: 0, y: 0, width: 200, height: 22),
                properties: ["content": textContent ?? ""],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // Button
        if trimmed.hasPrefix("Button(") {
            let label = extractStringLiteral(from: trimmed)
            return UITreeNode(
                id: "button_\(lineNumber)",
                type: "Button",
                frame: CGRect(x: 0, y: 0, width: 100, height: 44),
                properties: ["label": label ?? "Button"],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // Image
        if trimmed.hasPrefix("Image(") {
            return UITreeNode(
                id: "image_\(lineNumber)",
                type: "Image",
                frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                properties: [:],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // TextField
        if trimmed.hasPrefix("TextField(") {
            let placeholder = extractStringLiteral(from: trimmed)
            return UITreeNode(
                id: "textfield_\(lineNumber)",
                type: "TextField",
                frame: CGRect(x: 0, y: 0, width: 280, height: 36),
                properties: ["placeholder": placeholder ?? ""],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // List
        if trimmed.hasPrefix("List") {
            return UITreeNode(
                id: "list_\(lineNumber)",
                type: "List",
                frame: CGRect(x: 0, y: 0, width: 300, height: 400),
                properties: [:],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        // NavigationStack/View
        if trimmed.hasPrefix("NavigationStack") || trimmed.hasPrefix("NavigationView") {
            return UITreeNode(
                id: "navigation_\(lineNumber)",
                type: "NavigationStack",
                frame: CGRect(x: 0, y: 0, width: 393, height: 852),
                properties: [:],
                children: [],
                sourceLocation: .init(file: "", line: lineNumber, column: 1)
            )
        }
        
        return nil
    }
    
    private static func extractProperties(from line: String) -> [String: String] {
        var props: [String: String] = [:]
        
        // Extract spacing
        if let spacingMatch = line.range(of: #"spacing:\s*(\d+)"#, options: .regularExpression) {
            let value = String(line[spacingMatch]).components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? ""
            props["spacing"] = value
        }
        
        // Extract alignment
        if line.contains(".leading") {
            props["alignment"] = "leading"
        } else if line.contains(".trailing") {
            props["alignment"] = "trailing"
        } else if line.contains(".center") {
            props["alignment"] = "center"
        }
        
        return props
    }
    
    private static func extractStringLiteral(from line: String) -> String? {
        // Find content between quotes
        if let start = line.firstIndex(of: "\""),
           let end = line[line.index(after: start)...].firstIndex(of: "\"") {
            return String(line[line.index(after: start)..<end])
        }
        return nil
    }
}

// MARK: - UI Tree Overlay View

/// Overlay view for selecting UI elements in preview
struct UITreeOverlayView: View {
    let tree: UITreeNode
    let scale: CGFloat
    @Binding var selectedNodeId: String?
    var onNodeSelected: ((UITreeNode) -> Void)?
    
    var body: some View {
        ZStack {
            // Render each node as a selectable region
            ForEach(flattenNodes(tree), id: \.id) { node in
                Rectangle()
                    .fill(Color.clear)
                    .frame(
                        width: node.frame.width * scale,
                        height: node.frame.height * scale
                    )
                    .overlay(
                        Rectangle()
                            .stroke(
                                selectedNodeId == node.id ? Color.blue : Color.clear,
                                lineWidth: 2
                            )
                    )
                    .position(
                        x: node.frame.midX * scale,
                        y: node.frame.midY * scale
                    )
                    .onTapGesture {
                        selectedNodeId = node.id
                        onNodeSelected?(node)
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            }
        }
    }
    
    private func flattenNodes(_ node: UITreeNode) -> [UITreeNode] {
        var result = [node]
        for child in node.children {
            result.append(contentsOf: flattenNodes(child))
        }
        return result
    }
}

// MARK: - Element Inspector

struct ElementInspectorView: View {
    let node: UITreeNode?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let node = node {
                HStack {
                    Image(systemName: iconForType(node.type))
                        .foregroundColor(.blue)
                    Text(node.type)
                        .font(.headline)
                }
                
                Divider()
                
                // Properties
                ForEach(Array(node.properties.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(node.properties[key] ?? "")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                
                // Frame
                VStack(alignment: .leading, spacing: 4) {
                    Text("Frame")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(node.frame.width)) × \(Int(node.frame.height))")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                // Source location
                if let loc = node.sourceLocation {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.caption)
                        Text("Line \(loc.line)")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            } else {
                Text("Select an element")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(width: 200)
        .background(Color(nsColor: .windowBackgroundColor))
        .cornerRadius(8)
    }
    
    private func iconForType(_ type: String) -> String {
        switch type {
        case "VStack": return "rectangle.split.1x2"
        case "HStack": return "rectangle.split.2x1"
        case "ZStack": return "square.stack"
        case "Text": return "text.alignleft"
        case "Button": return "button.programmable"
        case "Image": return "photo"
        case "TextField": return "text.cursor"
        case "List": return "list.bullet"
        case "NavigationStack": return "sidebar.left"
        default: return "square"
        }
    }
}
