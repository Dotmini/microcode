//
//  Kernel/ThemeEngine.swift
//  MicroCode
//
//  User Space: Dynamic Theme Engine
//  Securely manages UI appearance and personalization.
//

import SwiftUI

class ThemeEngine: ObservableObject {
    static let shared = ThemeEngine()
    
    @Published var currentTheme: Theme = .default
    
    struct Theme: Identifiable {
        let id = UUID()
        let name: String
        let background: Color
        let accent: Color
        let text: Color
        
        static let `default` = Theme(
            name: "Default Dark",
            background: Color(red: 0.12, green: 0.12, blue: 0.12),
            accent: .blue,
            text: .white
        )
    }
    
    func applyTheme(_ theme: Theme) {
        withAnimation {
            currentTheme = theme
        }
        // Notify Kernel to persist preference
    }
}
// Color extension removed to avoid conflicts
