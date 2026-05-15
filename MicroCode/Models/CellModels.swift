//
//  CellModels.swift
//  MicroCode
//
//  Shared cell data models for Notebook and Playground
//  Copyright © 2025 Dotmini Software. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Software | SPU AI CLUB
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
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .localCPU: return "cpu"
        case .localMLX: return "applelogo"
        case .localNvidia: return "memorychip"
        case .cloudPremium: return "cloud.fill"
        case .customHPC: return "server.rack"
        }
    }
    
    var isPremium: Bool {
        return self == .cloudPremium
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
        case .none: return Color(nsColor: .textBackgroundColor)
        case .blue: return .blue.opacity(0.12)
        case .green: return .green.opacity(0.12)
        case .purple: return .purple.opacity(0.12)
        case .orange: return .orange.opacity(0.12)
        case .pink: return .pink.opacity(0.12)
        case .yellow: return .yellow.opacity(0.12)
        case .red: return .red.opacity(0.12)
        case .cyan: return .cyan.opacity(0.12)
        case .teal: return .teal.opacity(0.12)
        case .indigo: return .indigo.opacity(0.12)
        case .mint: return .mint.opacity(0.12)
        case .brown: return .brown.opacity(0.12)
        case .gray: return .gray.opacity(0.12)
        }
    }
    
    var borderColor: Color {
        switch self {
        case .none: return .gray.opacity(0.3)
        case .blue: return .blue.opacity(0.5)
        case .green: return .green.opacity(0.5)
        case .purple: return .purple.opacity(0.5)
        case .orange: return .orange.opacity(0.5)
        case .pink: return .pink.opacity(0.5)
        case .yellow: return .yellow.opacity(0.5)
        case .red: return .red.opacity(0.5)
        case .cyan: return .cyan.opacity(0.5)
        case .teal: return .teal.opacity(0.5)
        case .indigo: return .indigo.opacity(0.5)
        case .mint: return .mint.opacity(0.5)
        case .brown: return .brown.opacity(0.5)
        case .gray: return .gray.opacity(0.5)
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
    let id = UUID()
    @Published var code: String
    @Published var output: String = ""
    @Published var colorTheme: CellColorTheme
    @Published var isExecuting: Bool = false
    @Published var executionTime: Double = 0.0
    
    init(code: String, colorTheme: CellColorTheme = .none) {
        self.code = code
        self.colorTheme = colorTheme
    }
}
