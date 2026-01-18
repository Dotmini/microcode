//
//  CatalogueSidebar.swift
//  CodeTunner
//
//  A sidebar component for code snippets and SAS procedures
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//
//  Tirawat Nantamas | Dotmini Software | SPU AI CLUB
//

import SwiftUI

struct CatalogueItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let code: String
    let category: String
    let description: String
}

struct CatalogueSidebar: View {
    @EnvironmentObject var appState: AppState
    let onSelectItem: (String) -> Void
    
    @State private var selectedTab = 0 // 0: Snippets, 1: Procedures
    @State private var searchText = ""
    @State private var hoveringId: UUID? = nil
    
    let snippets = [
        CatalogueItem(name: "Python HTTP Request", icon: "network", code: "import requests\nresponse = requests.get('https://api.github.com')\nprint(response.json())", category: "Python", description: "Fetch JSON data from API"),
        CatalogueItem(name: "SwiftUI List", icon: "list.bullet", code: "List(0..<10) { i in\n    Text(\"Item \\(i)\")\n}", category: "Swift", description: "Standard Scrollable List"),
        CatalogueItem(name: "Rust File Write", icon: "doc.badge.plus", code: "use std::fs::File;\nuse std::io::prelude::*;\n\nfn main() -> std::io::Result<()> {\n    let mut file = File::create(\"hello.txt\")?;\n    file.write_all(b\"Hello, world!\")?;\n    Ok(())\n}", category: "Rust", description: "Create text file safety"),
        CatalogueItem(name: "React Component", icon: "atom", code: "import React from 'react';\n\nconst MyComponent = () => {\n  return <div>Hello World</div>;\n};\n\nexport default MyComponent;", category: "JS", description: "Functional Component"),
        CatalogueItem(name: "SQL Create Table", icon: "table", code: "CREATE TABLE users (\n    id INTEGER PRIMARY KEY,\n    name TEXT NOT NULL,\n    email TEXT UNIQUE\n);", category: "SQL", description: "User schema definition")
    ]
    
    let procedures = [
        CatalogueItem(name: "Data Cleaning", icon: "wand.and.stars", code: "# Data Cleaning Template\ndf = df.dropna()\ndf = df.drop_duplicates()\nprint('Cleaning complete')", category: "General", description: "Remove nulls & duplicates"),
        CatalogueItem(name: "Feature Engineering", icon: "hammer", code: "# Feature Engineering Template\ndf['new_feature'] = df['a'] * df['b']\nprint('Feature engineered')", category: "ML", description: "Create interaction features"),
        CatalogueItem(name: "Model Training", icon: "cpu", code: "from sklearn.ensemble import RandomForestClassifier\nmodel = RandomForestClassifier()\nmodel.fit(X_train, y_train)\nprint('Model trained')", category: "ML", description: "Random Forest Classifier"),
        CatalogueItem(name: "Visual Analysis", icon: "chart.bar", code: "import matplotlib.pyplot as plt\ndf.plot(kind='bar')\nplt.show()", category: "Viz", description: "Bar chart visualization")
    ]
    
    var filteredItems: [CatalogueItem] {
        let items = selectedTab == 0 ? snippets : procedures
        if searchText.isEmpty {
            return items
        } else {
            return items.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.category.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Catalogue")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    Text("Snippets").tag(0)
                    Text("Procedures").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 140)
            }
            .padding(12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search templates...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
            .padding(10)
            
            // Items List
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        CatalogueCard(item: item, isHovering: hoveringId == item.id) {
                            onSelectItem(item.code)
                        }
                        .onHover { hover in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hoveringId = hover ? item.id : nil
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
        .frame(minWidth: 250, maxWidth: 350)
    }
}

struct CatalogueCard: View {
    let item: CatalogueItem
    let isHovering: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                // Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(accentGradient(for: item.category))
                        .shadow(color: accentColor(for: item.category).opacity(0.3), radius: 4, x: 0, y: 2)
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: item.icon)
                        .foregroundColor(.white)
                        .font(.system(size: 16))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Spacer()
                        if isHovering {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                                .transition(.scale)
                        }
                    }
                    
                    Text(item.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Text(item.category.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isHovering ? accentColor(for: item.category).opacity(0.5) : Color.clear, lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.1 : 0.05), radius: isHovering ? 4 : 2, y: isHovering ? 2 : 1)
            .scaleEffect(isHovering ? 1.01 : 1.0)
        }
        .buttonStyle(.plain)
    }
    
    private func accentColor(for category: String) -> Color {
        switch category {
        case "Python": return .blue
        case "Swift": return .orange
        case "Rust": return .brown
        case "JS": return .yellow
        case "SQL": return .cyan
        case "ML": return .purple
        case "Viz": return .green
        default: return .gray
        }
    }
    
    private func accentGradient(for category: String) -> LinearGradient {
        let color = accentColor(for: category)
        return LinearGradient(colors: [color, color.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
