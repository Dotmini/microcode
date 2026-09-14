//
//  CellModels.swift
//  MicroCode
//
//  Shared cell data models for Notebook and Playground
//  Copyright © 2025 Dotmini Software. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Company Limited
//

import SwiftUI

import SwiftUI

// MARK: - Compute Target (Cell Execution)

enum ComputeTarget: String, CaseIterable, Identifiable, Codable {
    case localCPU = "Local CPU"
    case localMLX = "Apple Silicon (NPU/Metal)"
    case localNvidia = "Nvidia GPU (CUDA/eGPU)"
    case cloudPremium = "Microrent Cloud (Serverless)"
    case customHPC = "Custom Cloud GPU (RunPod/Vast.ai/Akamai)"
    case yourCloud = "Your Cloud (SSH)"

    var id: String { rawValue }

    // Human-facing label. rawValue is kept for Codable / legacy notebooks;
    // UI must use this instead of rawValue so we can rebrand without
    // breaking saved files.
    var displayName: String {
        switch self {
        case .localCPU:      return "Local CPU"
        case .localMLX:      return "Apple Silicon"
        case .localNvidia:   return "Local Nvidia GPU"
        case .cloudPremium:  return "MicroCode Cloud (Premium)"
        case .customHPC:     return "MicroCode Cloud"
        case .yourCloud:     return "Your Cloud (SSH)"
        }
    }

    // Targets that should appear in the user-facing compute-engine menu.
    // cloudPremium is legacy (separate stub kernel) — all premium GPUs now
    // ship through the customHPC / Jupyter path managed by CloudGPUService.
    static var userSelectable: [ComputeTarget] {
        [.localCPU, .localMLX, .localNvidia, .customHPC, .yourCloud]
    }

    var icon: String {
        switch self {
        case .localCPU: return "cpu"
        case .localMLX: return "applelogo"
        case .localNvidia: return "memorychip"
        case .cloudPremium: return "cloud.fill"
        case .customHPC: return "cloud.fill"
        case .yourCloud: return "server.rack"
        }
    }

    var isPremium: Bool {
        return self == .cloudPremium || self == .customHPC
    }
}

// MARK: - Cell Color Theme

enum CellColorTheme: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case blue = "Blue"
    case green = "Green"
    case purple = "Purple"
    case orange = "Orange"
    case pink = "Pink"
    case yellow = "Yellow"
    case red = "Red"
    case cyan = "Cyan"
    case teal = "Teal"
    case indigo = "Indigo"
    case mint = "Mint"
    case brown = "Brown"
    case gray = "Gray"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .none: return Color.clear
        case .blue: return .blue.opacity(0.15)
        case .green: return .green.opacity(0.15)
        case .purple: return .purple.opacity(0.15)
        case .orange: return .orange.opacity(0.15)
        case .pink: return .pink.opacity(0.15)
        case .yellow: return .yellow.opacity(0.15)
        case .red: return .red.opacity(0.15)
        case .cyan: return .cyan.opacity(0.15)
        case .teal: return .teal.opacity(0.15)
        case .indigo: return .indigo.opacity(0.15)
        case .mint: return .mint.opacity(0.15)
        case .brown: return .brown.opacity(0.15)
        case .gray: return .gray.opacity(0.15)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .none: return Color.secondary.opacity(0.25)
        case .blue: return .blue.opacity(0.6)
        case .green: return .green.opacity(0.6)
        case .purple: return .purple.opacity(0.6)
        case .orange: return .orange.opacity(0.6)
        case .pink: return .pink.opacity(0.6)
        case .yellow: return .yellow.opacity(0.6)
        case .red: return .red.opacity(0.6)
        case .cyan: return .cyan.opacity(0.6)
        case .teal: return .teal.opacity(0.6)
        case .indigo: return .indigo.opacity(0.6)
        case .mint: return .mint.opacity(0.6)
        case .brown: return .brown.opacity(0.6)
        case .gray: return .gray.opacity(0.6)
        }
    }
    
    var iconColor: Color {
        switch self {
        case .none: return .primary
        case .blue: return .blue
        case .green: return .green
        case .purple: return .purple
        case .orange: return .orange
        case .pink: return .pink
        case .yellow: return .yellow
        case .red: return .red
        case .cyan: return .cyan
        case .teal: return .teal
        case .indigo: return .indigo
        case .mint: return .mint
        case .brown: return .brown
        case .gray: return .gray
        }
    }
}

// MARK: - Custom Cell Color

struct CustomCellColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double
    
    init(red: Double = 0.3, green: Double = 0.5, blue: Double = 0.8, opacity: Double = 0.15) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }
    
    init(color: Color) {
        // Default values
        self.red = 0.3
        self.green = 0.5
        self.blue = 0.8
        self.opacity = 0.15
    }
    
    var color: Color {
        Color(red: red, green: green, blue: blue).opacity(opacity)
    }
    
    var borderColor: Color {
        Color(red: red, green: green, blue: blue).opacity(min(opacity * 3, 1.0))
    }
    
    var nsColor: NSColor {
        NSColor(red: red, green: green, blue: blue, alpha: opacity)
    }
}

// MARK: - Playground Cell Model

final class PlaygroundCellModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var code: String
    @Published var output: String = ""
    @Published var colorTheme: CellColorTheme
    @Published var isExecuting: Bool = false
    @Published var executionTime: Double = 0.0
    
    init(id: UUID = UUID(), code: String, output: String = "", colorTheme: CellColorTheme = .none) {
        self.id = id
        self.code = code
        self.output = output
        self.colorTheme = colorTheme
    }
}

// MARK: - .microplay Document Format Support

public struct MicroplayCellData: Codable, Identifiable {
    public var id: String
    public var type: String // "code"
    public var language: String
    public var content: String
    public var output: String?
    public var colorTheme: String?
    public var isCollapsed: Bool?
    public var generatedCode: String?
    
    public init(id: String = UUID().uuidString, type: String = "code", language: String, content: String, output: String? = nil, colorTheme: String? = nil, isCollapsed: Bool? = false, generatedCode: String? = nil) {
        self.id = id
        self.type = type
        self.language = language
        self.content = content
        self.output = output
        self.colorTheme = colorTheme
        self.isCollapsed = isCollapsed
        self.generatedCode = generatedCode
    }
}

public struct MicroplayDocument: Codable {
    public var version: Int
    public var id: String
    public var name: String
    public var createdAt: String
    public var modifiedAt: String
    public var mode: String // "playground"
    public var cells: [MicroplayCellData]
    
    public init(id: String = UUID().uuidString, name: String = "Playground.microplay", mode: String = "playground", cells: [MicroplayCellData]) {
        self.version = 1
        self.id = id
        self.name = name
        let isoFormatter = ISO8601DateFormatter()
        let now = isoFormatter.string(from: Date())
        self.createdAt = now
        self.modifiedAt = now
        self.mode = mode
        self.cells = cells
    }
}
