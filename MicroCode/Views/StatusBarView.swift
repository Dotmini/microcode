//
//  StatusBarView.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 16) {
            // Language
            if let file = appState.currentFile {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 10))
                    Text(file.language.capitalized)
                        .font(.system(size: 11))
                }
                
                Divider()
                    .frame(height: 12)
                
                // Line & Column (placeholder)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 10))
                    Text("Ln 1, Col 1")
                        .font(.system(size: 11))
                }
                
                Divider()
                    .frame(height: 12)
                
                // Encoding
                Text("UTF-8")
                    .font(.system(size: 11))
                
                Divider()
                    .frame(height: 12)
                
                // Line ending
                Text("LF")
                    .font(.system(size: 11))
            }
            
            Spacer()
            
            // Execution status
            if !appState.consoleOutput.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 10))
                    Text("Ready")
                        .font(.system(size: 11))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(Color(nsColor: .windowBackgroundColor))
        .foregroundColor(.secondary)
    }
}
