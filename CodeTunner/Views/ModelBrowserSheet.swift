import SwiftUI

// MARK: - Model Browser Sheet (LM Studio-style)

struct ModelBrowserSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject private var llm = LocalLLMService.shared
    @State private var searchText = ""
    @State private var selectedModel: DownloadableModel?
    @State private var filterProvider = "All"
    
    private let providers = ["All", "Google", "Meta", "Alibaba", "DeepSeek", "Mistral AI", "Microsoft", "NVIDIA"]
    
    private var filteredModels: [DownloadableModel] {
        llm.modelCatalog.filter { m in
            (filterProvider == "All" || m.provider == filterProvider) &&
            (searchText.isEmpty || m.name.localizedCaseInsensitiveContains(searchText) || m.provider.localizedCaseInsensitiveContains(searchText))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Image(systemName: "square.grid.2x2.fill").foregroundColor(.purple)
                Text("Model Browser").font(.headline)
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 18)).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Left: Model List
                VStack(spacing: 0) {
                    // Search
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Search models...", text: $searchText)
                            .textFieldStyle(.plain)
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
                    
                    // Filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(providers, id: \.self) { p in
                                Button(action: { filterProvider = p }) {
                                    Text(p)
                                        .font(.system(size: 10, weight: filterProvider == p ? .bold : .regular))
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                        .background(filterProvider == p ? Color.purple.opacity(0.15) : Color.primary.opacity(0.04))
                                        .foregroundColor(filterProvider == p ? .purple : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                    }
                    
                    Divider()
                    
                    // Model list
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(filteredModels) { model in
                                modelListRow(model)
                            }
                        }
                        .padding(6)
                    }
                }
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                
                // Right: Model Detail
                if let model = selectedModel {
                    modelDetailView(model)
                } else {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "cube.box").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.3))
                        Text("Select a model").foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(width: 780, height: 520)
    }
    
    // MARK: - Model List Row
    
    private func modelListRow(_ model: DownloadableModel) -> some View {
        let isSelected = selectedModel?.id == model.id
        let isInstalled = llm.availableModels.contains(where: { $0.id.contains(model.ollamaTag.components(separatedBy: ":").first ?? model.ollamaTag) })
        let isDownloading = llm.downloadingModels[model.id] != nil
        
        return Button(action: { selectedModel = model }) {
            HStack(spacing: 10) {
                // Provider icon
                providerIcon(model.provider)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(model.name)
                            .font(.system(size: 12, weight: .semibold))
                        if isInstalled {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                        }
                    }
                    Text("\(model.provider) · \(model.params) · \(model.sizeLabel)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Capability badges
                HStack(spacing: 3) {
                    ForEach(model.capabilities.prefix(2), id: \.self) { cap in
                        capabilityBadge(cap)
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(isSelected ? Color.purple.opacity(0.1) : Color.clear)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Model Detail View
    
    private func modelDetailView(_ model: DownloadableModel) -> some View {
        let isInstalled = llm.availableModels.contains(where: { $0.id.contains(model.ollamaTag.components(separatedBy: ":").first ?? model.ollamaTag) })
        let progress = llm.downloadingModels[model.id]
        let isDownloading = progress != nil
        
        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                providerIcon(model.provider, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name).font(.title3).fontWeight(.bold)
                    Text(model.provider).font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Description
                    Text(model.description)
                        .font(.system(size: 13))
                        .foregroundColor(.primary.opacity(0.8))
                    
                    // Specs
                    HStack(spacing: 12) {
                        specBadge("Params", model.params)
                        specBadge("Size", model.sizeLabel)
                        specBadge("Format", "GGUF")
                    }
                    
                    // Capabilities
                    HStack(spacing: 6) {
                        Text("Capabilities:").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                        ForEach(model.capabilities, id: \.self) { cap in
                            capabilityBadge(cap)
                        }
                    }
                    
                    Divider()
                    
                    // Download section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Download").font(.system(size: 12, weight: .bold))
                        
                        HStack {
                            HStack(spacing: 4) {
                                Text("GGUF").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Color.purple).cornerRadius(3)
                                Text(model.ollamaTag).font(.system(size: 11, design: .monospaced))
                            }
                            
                            Spacer()
                            
                            Text(model.sizeLabel).font(.system(size: 11)).foregroundColor(.secondary)
                            
                            if isInstalled {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                                    Text("Installed").font(.system(size: 11, weight: .medium)).foregroundColor(.green)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(6)
                            } else if isDownloading {
                                HStack(spacing: 6) {
                                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                                    Text("Downloading \(Int((progress ?? 0) * 100))%")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.blue)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(6)
                            } else {
                                Button(action: { Task { await llm.downloadModel(model) } }) {
                                    Label("Download", systemImage: "arrow.down.circle.fill")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.purple)
                                .controlSize(.small)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                        
                        if isDownloading, let p = progress {
                            ProgressView(value: p)
                                .tint(.purple)
                        }
                        
                        // GPU info
                        if model.sizeGB < 8 {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill").foregroundColor(.green).font(.system(size: 9))
                                Text("Full GPU Offload Possible")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                    
                    if !llm.detectedServers.contains(where: { $0.type == .ollama && $0.isOnline }) {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.system(size: 11))
                            Text("Ollama must be running to download models. Install from ollama.com")
                                .font(.system(size: 11)).foregroundColor(.orange)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(6)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func providerIcon(_ provider: String, size: CGFloat = 26) -> some View {
        let (icon, color) = providerStyle(provider)
        return ZStack {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(color.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: icon)
                .font(.system(size: size * 0.45))
                .foregroundColor(color)
        }
    }
    
    private func providerStyle(_ provider: String) -> (String, Color) {
        switch provider {
        case "Google": return ("sparkle", .blue)
        case "Meta": return ("brain.head.profile", .indigo)
        case "Alibaba": return ("cloud.fill", .purple)
        case "DeepSeek": return ("water.waves", .cyan)
        case "Mistral AI": return ("wind", .orange)
        case "Microsoft": return ("square.grid.3x3.fill", .blue)
        case "NVIDIA": return ("bolt.fill", .green)
        default: return ("cube.box", .secondary)
        }
    }
    
    private func capabilityBadge(_ cap: String) -> some View {
        let color: Color = cap == "Code" ? .blue : cap == "Reasoning" ? .orange : cap == "Vision" ? .purple : cap == "Tool Use" ? .green : .secondary
        return Text(cap)
            .font(.system(size: 8, weight: .bold))
            .foregroundColor(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(color.opacity(0.12))
            .cornerRadius(3)
    }
    
    private func specBadge(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundColor(.secondary)
            Text(value).font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(6)
    }
}
