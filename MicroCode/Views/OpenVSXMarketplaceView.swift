//
//  OpenVSXMarketplaceView.swift
//  MicroCode
//
//  Authentic Open VSX Registry Marketplace & Direct Installer
//  https://open-vsx.org
//
//  Tirawat Nantamas | Dotmini Company Limited
//

import SwiftUI
import AppKit

struct OpenVSXMarketplaceView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var openVSX = OpenVSXService.shared
    @StateObject private var extensionManager = ExtensionManager.shared
    
    var onSelectInstalled: ((String) -> Void)? = nil
    
    @State private var query: String = ""
    @State private var selectedCategory: String = "All"
    @State private var selectedExtension: OpenVSXExtension? = nil
    @State private var selectedDetailTab: Int = 0 // 0: README, 1: Package Info
    @State private var readmeContent: String? = nil
    @State private var isLoadingReadme: Bool = false
    @State private var errorMessage: String? = nil
    @State private var searchTask: Task<Void, Never>? = nil
    
    // Theme helpers
    private var isDark: Bool { appState.appTheme.isDark }
    private var bg: Color { isDark ? Color(white: 0.04) : Color(white: 0.98) }
    private var sidebarBg: Color { isDark ? Color(white: 0.06) : Color(white: 0.95) }
    private var cardBg: Color { isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03) }
    private var cardBorderColor: Color { isDark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
    private var dividerLineColor: Color { isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.08) }
    
    private let categories = [
        "All",
        "🔥 Popular",
        "🎨 Themes",
        "📁 Icons",
        "⚡ Languages",
        "🛠️ Linters",
        "🤖 AI & Tools",
        "📦 Snippets"
    ]
    
    private var displayExtensions: [OpenVSXExtension] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty || selectedCategory != "All" {
            return openVSX.searchResults
        }
        return openVSX.popularExtensions
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Left Column: Catalog & Search List
            VStack(spacing: 0) {
                searchAndFilterBar
                
                Rectangle()
                    .fill(dividerLineColor)
                    .frame(height: 1)
                
                categoryFilterBar
                
                Rectangle()
                    .fill(dividerLineColor)
                    .frame(height: 1)
                
                extensionList
            }
            .frame(width: 380)
            .background(sidebarBg)
            
            Rectangle()
                .fill(dividerLineColor)
                .frame(width: 1)
            
            // Right Column: Detail & Installer Canvas
            ZStack {
                bg.ignoresSafeArea()
                
                if let ext = selectedExtension {
                    extensionDetailView(for: ext)
                } else {
                    emptySelectionState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            if openVSX.popularExtensions.isEmpty {
                let pop = await openVSX.fetchPopular(size: 30)
                if selectedExtension == nil {
                    selectedExtension = pop.first
                    if let first = pop.first {
                        loadReadme(for: first)
                    }
                }
            } else if selectedExtension == nil {
                selectedExtension = openVSX.popularExtensions.first
                if let first = selectedExtension {
                    loadReadme(for: first)
                }
            }
        }
    }
    
    // MARK: - Search & Filter Bar
    private var searchAndFilterBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                TextField("Search 50,000+ extensions from Open VSX...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        triggerSearch()
                    }
                    .onChange(of: query) { newQuery in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            if !Task.isCancelled {
                                triggerSearch()
                            }
                        }
                    }
                
                if openVSX.isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 14, height: 14)
                } else if !query.isEmpty {
                    Button(action: {
                        query = ""
                        triggerSearch()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
        }
        .padding(10)
    }
    
    // MARK: - Category Filter Bar
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(categories, id: \.self) { cat in
                    let isSelected = selectedCategory == cat
                    Button(action: {
                        selectedCategory = cat
                        triggerSearch()
                    }) {
                        Text(cat)
                            .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(isSelected ? (isDark ? Color.white : Color.black) : cardBg)
                            .foregroundColor(isSelected ? (isDark ? Color.black : Color.white) : .primary)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(isSelected ? Color.clear : cardBorderColor, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Extension List
    private var extensionList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if displayExtensions.isEmpty {
                    if openVSX.isSearching {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Searching Open VSX Registry...")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 24))
                                .foregroundColor(.secondary)
                            Text("No extensions found")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Try another search term or category")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 180)
                    }
                } else {
                    ForEach(displayExtensions) { ext in
                        extensionRow(ext)
                    }
                }
            }
            .padding(8)
        }
    }
    
    // MARK: - Extension Row
    private func extensionRow(_ ext: OpenVSXExtension) -> some View {
        let isSelected = selectedExtension?.id == ext.id
        let isInstalled = extensionManager.isExtensionInstalled(ext.id)
        let isDownloading = openVSX.downloadingIds.contains(ext.id)
        let progress = openVSX.downloadProgress[ext.id] ?? 0.0
        
        return Button(action: {
            selectedExtension = ext
            loadReadme(for: ext)
        }) {
            HStack(alignment: .top, spacing: 10) {
                // Extension Icon
                remoteIcon(for: ext, size: 36)
                
                // Info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(ext.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        
                        if ext.verified == true {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text(ext.author)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let desc = ext.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    // Metrics & Action Row
                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 8))
                            Text(ext.formattedDownloads)
                                .font(.system(size: 9, design: .monospaced))
                        }
                        .foregroundColor(.secondary)
                        
                        if !ext.formattedRating.isEmpty {
                            Text(ext.formattedRating)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // Inline install button / status
                        if isInstalled {
                            Text("✓ Installed")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(cardBg)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        } else if isDownloading {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 10, height: 10)
                                Text("\(Int(progress * 100))%")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        } else {
                            Button(action: {
                                installExtension(ext)
                            }) {
                                Text("Install")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(isDark ? Color.white : Color.black)
                                    .foregroundColor(isDark ? Color.black : Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? cardBg.opacity(2.0) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? (isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.3)) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Extension Detail View
    private func extensionDetailView(for ext: OpenVSXExtension) -> some View {
        let isInstalled = extensionManager.isExtensionInstalled(ext.id)
        let isDownloading = openVSX.downloadingIds.contains(ext.id)
        let progress = openVSX.downloadProgress[ext.id] ?? 0.0
        
        return VStack(spacing: 0) {
            // Header Banner
            HStack(alignment: .top, spacing: 16) {
                remoteIcon(for: ext, size: 54)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(ext.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("v\(ext.version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        
                        if ext.verified == true {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("VERIFIED")
                            }
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text("Publisher:")
                            .foregroundColor(.secondary)
                        Text(ext.author)
                            .foregroundColor(.primary)
                            .fontWeight(.semibold)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("Open VSX Registry")
                            .foregroundColor(.secondary)
                    }
                    .font(.system(size: 11, design: .monospaced))
                    
                    if let desc = ext.description, !desc.isEmpty {
                        Text(desc)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                
                Spacer()
                
                // Actions & Install Button
                VStack(alignment: .trailing, spacing: 8) {
                    if isInstalled {
                        HStack(spacing: 8) {
                            Text("✓ INSTALLED")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(cardBg)
                                .foregroundColor(.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
                            
                            if let onSelectInstalled = onSelectInstalled {
                                Button(action: {
                                    onSelectInstalled(ext.id)
                                }) {
                                    Text("Open in Studio")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isDark ? Color.white : Color.black)
                                        .foregroundColor(isDark ? Color.black : Color.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else if isDownloading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Downloading \(Int(progress * 100))%...")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Button(action: {
                            installExtension(ext)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Install Extension")
                            }
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(isDark ? Color.white : Color.black)
                            .foregroundColor(isDark ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Web Link Button
                    Button(action: {
                        if let url = URL(string: "https://open-vsx.org/extension/\(ext.namespace)/\(ext.name)") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("View on open-vsx.org")
                        }
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(cardBg)
            
            Rectangle()
                .fill(dividerLineColor)
                .frame(height: 1)
            
            // Metrics bar
            HStack(spacing: 24) {
                metricItem(icon: "arrow.down.circle", label: "Downloads", value: ext.formattedDownloads)
                if !ext.formattedRating.isEmpty {
                    metricItem(icon: "star.fill", label: "Rating", value: ext.formattedRating)
                }
                metricItem(icon: "tag", label: "Version", value: ext.version)
                if let ts = ext.timestamp {
                    metricItem(icon: "clock", label: "Published", value: String(ts.prefix(10)))
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.02))
            
            Rectangle()
                .fill(dividerLineColor)
                .frame(height: 1)
            
            // Sub-tabs: README / Package Info
            HStack(spacing: 4) {
                detailTabButton(title: "README", tag: 0)
                detailTabButton(title: "Package Info", tag: 1)
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if selectedDetailTab == 0 {
                        if isLoadingReadme {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("Loading README from Open VSX...")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 160)
                        } else if let readme = readmeContent, !readme.isEmpty {
                            Text(readme)
                                .font(.system(size: 12, design: .monospaced))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("No README provided by this extension.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 120)
                        }
                    } else {
                        packageInfoView(for: ext)
                    }
                }
                .padding(18)
            }
        }
    }
    
    // MARK: - Package Info Tab
    private func packageInfoView(for ext: OpenVSXExtension) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow(label: "Extension ID", value: ext.id)
            infoRow(label: "Namespace", value: ext.namespace)
            infoRow(label: "Package Name", value: ext.name)
            infoRow(label: "Version", value: ext.version)
            if let tags = ext.tags, !tags.isEmpty {
                infoRow(label: "Tags", value: tags.joined(separator: ", "))
            }
            if let categories = ext.categories, !categories.isEmpty {
                infoRow(label: "Categories", value: categories.joined(separator: ", "))
            }
            if let dl = ext.downloadURL?.absoluteString {
                infoRow(label: "VSIX Package URL", value: dl)
            }
        }
        .font(.system(size: 11.5, design: .monospaced))
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label + ":")
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Metric Item Helper
    private func metricItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
            }
        }
    }
    
    private func detailTabButton(title: String, tag: Int) -> some View {
        let isSelected = selectedDetailTab == tag
        return Button(action: { selectedDetailTab = tag }) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Rectangle()
                    .fill(isSelected ? (isDark ? Color.white : Color.black) : Color.clear)
                    .frame(height: 2)
            }
            .padding(.horizontal, 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Remote Icon with Fallback
    private func remoteIcon(for ext: OpenVSXExtension, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cardBg)
                .frame(width: size, height: size)
            
            if let iconURL = ext.iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: size - 4, height: size - 4)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    default:
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: size * 0.45))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: size * 0.45))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(cardBorderColor, lineWidth: 1))
    }
    
    // MARK: - Empty Selection State
    private var emptySelectionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe.badge.chevron.backward")
                .font(.system(size: 38))
                .foregroundColor(.secondary)
            Text("Open VSX Registry Marketplace")
                .font(.system(size: 16, weight: .bold))
            Text("Browse and search tens of thousands of community & official VS Code extensions.\nSelect any extension to inspect README and install directly into MicroCode.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Search Trigger
    private func triggerSearch() {
        Task {
            let catParam: String? = {
                switch selectedCategory {
                case "🎨 Themes": return "Themes"
                case "⚡ Languages": return "Programming Languages"
                case "🛠️ Linters": return "Linters"
                case "📦 Snippets": return "Snippets"
                default: return nil
                }
            }()
            
            var searchQuery = query
            if selectedCategory == "📁 Icons" && query.isEmpty {
                searchQuery = "icon"
            } else if selectedCategory == "🤖 AI & Tools" && query.isEmpty {
                searchQuery = "ai"
            }
            
            let res = await openVSX.search(query: searchQuery, category: catParam)
            if selectedExtension == nil || !res.contains(where: { $0.id == selectedExtension?.id }) {
                selectedExtension = res.first
                if let first = res.first {
                    loadReadme(for: first)
                }
            }
        }
    }
    
    // MARK: - README Loader
    private func loadReadme(for ext: OpenVSXExtension) {
        isLoadingReadme = true
        readmeContent = nil
        Task {
            let md = await openVSX.fetchReadme(for: ext)
            await MainActor.run {
                self.readmeContent = md
                self.isLoadingReadme = false
            }
        }
    }
    
    // MARK: - Install Extension
    private func installExtension(_ ext: OpenVSXExtension) {
        Task {
            do {
                _ = try await openVSX.downloadAndInstall(extension: ext)
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to install \(ext.title): \(error.localizedDescription)"
                }
            }
        }
    }
}
