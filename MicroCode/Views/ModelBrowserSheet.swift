//
//  ModelBrowserSheet.swift
//  MicroCode
//
//  Live Apple HIG Monochrome Model Hub — Fetches real-time catalogs & exact
//  variant sizes from Hugging Face (Apple MLX & GGUF) and Ollama Library,
//  streams downloads with byte-level progress, auto-starts local runtimes,
//  and connects directly into MicroCode Chat.
//

import SwiftUI
import AppKit

struct ModelBrowserSheet: View {
    @Binding var isPresented: Bool
    var onActivateModel: ((String) -> Void)? = nil

    @ObservedObject private var llm = LocalLLMService.shared

    @State private var selectedSource: ModelHubSource = .ollama
    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var selectedModelID: String? = nil
    @State private var selectedVariantID: String? = nil
    @State private var copiedRepoID: Bool = false

    private let categories = ["All", "Code", "Tools", "Reasoning", "Vision"]

    private var selectedItem: HubModelItem? {
        if let id = selectedModelID, let found = llm.hubModels.first(where: { $0.id == id }) {
            return found
        }
        return llm.hubModels.first
    }

    private var selectedVariant: HubModelVariant? {
        guard let item = selectedItem else { return nil }
        if let vid = selectedVariantID, let found = item.variants.first(where: { $0.id == vid }) {
            return found
        }
        return item.variants.first
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().opacity(0.6)

            HStack(spacing: 0) {
                leftCatalogSidebar
                    .frame(width: 325)

                Divider().opacity(0.6)

                rightDetailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 860, height: 575)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Default to Apple MLX on Apple Silicon when mlx_lm.server is installed, otherwise Ollama
            if llm.ollamaBinaryPath == nil && llm.mlxServerBinaryPath != nil {
                selectedSource = .mlx
            }
        }
        .task(id: "\(selectedSource.rawValue)|\(selectedCategory)|\(searchText)") {
            if !searchText.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                if Task.isCancelled { return }
            }
            await llm.fetchHubModels(source: selectedSource, query: searchText, category: selectedCategory)
            ensureValidSelectionAndLoadDetails()
        }
        .onChange(of: selectedModelID) { newID in
            guard let newID else { return }
            if let item = llm.hubModels.first(where: { $0.id == newID }) {
                selectedVariantID = item.variants.first?.id
                Task {
                    await llm.fetchHubModelDetails(itemID: newID)
                    if let updated = llm.hubModels.first(where: { $0.id == newID }),
                       selectedVariantID == nil || !updated.variants.contains(where: { $0.id == selectedVariantID }) {
                        selectedVariantID = updated.variants.first?.id
                    }
                }
            }
        }
    }

    // MARK: - Top Header Bar (Clean Apple HIG Monochrome)

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Text("Model Browser")
                    .font(.system(size: 13.5, weight: .semibold))

                Text("\(llm.hardwareChipName) · \(llm.physicalMemoryGBLabel)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(5)
            }

            Spacer()

            // Monochrome Segmented Source Tabs
            HStack(spacing: 3) {
                ForEach(ModelHubSource.allCases) { src in
                    let isSelected = (selectedSource == src)
                    Button(action: {
                        selectedSource = src
                        selectedModelID = nil
                        selectedVariantID = nil
                        llm.hubErrorMessage = nil
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: src.iconName)
                                .font(.system(size: 10.5, weight: .medium))
                            Text(src.rawValue)
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        }
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isSelected ? Color.primary.opacity(0.10) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )

            Spacer()

            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        await llm.fetchHubModels(source: selectedSource, query: searchText, category: selectedCategory)
                        ensureValidSelectionAndLoadDetails()
                    }
                }) {
                    if llm.isFetchingHub {
                        ProgressView()
                            .scaleEffect(0.55)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Refresh live catalog")

                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.02))
    }

    // MARK: - Left Sidebar (Live Search + Clean List)

    private var leftCatalogSidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                // Search field
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                    TextField(searchPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6.5)
                .background(Color.primary.opacity(0.045))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Monochrome category filters (hidden on Installed tab)
                if selectedSource != .installed {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(categories, id: \.self) { cat in
                                let active = (selectedCategory == cat)
                                Button(action: { selectedCategory = cat }) {
                                    Text(cat)
                                        .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                                        .foregroundColor(active ? .primary : .secondary)
                                        .padding(.horizontal, 8.5)
                                        .padding(.vertical, 3.5)
                                        .background(active ? Color.primary.opacity(0.11) : Color.primary.opacity(0.03))
                                        .cornerRadius(5)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 5)
                                                .stroke(active ? Color.primary.opacity(0.20) : Color.clear, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(10)

            Divider().opacity(0.5)

            if llm.isFetchingHub && llm.hubModels.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Fetching live models from \(upstreamDomainLabel)...")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if llm.hubModels.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: selectedSource == .installed ? "tray" : "magnifyingglass")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(selectedSource == .installed ? "No local models installed yet" : "No models matched your search")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    if selectedSource == .installed {
                        Button("Browse Ollama Library") {
                            selectedSource = .ollama
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else if !searchText.isEmpty || selectedCategory != "All" {
                        Button("Reset Filters") {
                            searchText = ""
                            selectedCategory = "All"
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(llm.hubModels) { item in
                            hubListRow(item)
                        }
                    }
                    .padding(8)
                }
            }

            Divider().opacity(0.5)

            // Subtle live footer
            HStack {
                Text(selectedSource.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(String(llm.hubModels.count)) models")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.015))
        }
    }

    private func hubListRow(_ item: HubModelItem) -> some View {
        let isSelected = (selectedItem?.id == item.id)
        let isReady = item.source == .installed || item.variants.contains(where: { $0.isDownloadedOnDisk })
        let isDownloadingThis = (llm.activeHubDownload?.modelID == item.id)

        return Button(action: {
            selectedModelID = item.id
        }) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(isSelected ? 0.10 : 0.045))
                        .frame(width: 28, height: 28)

                    if isDownloadingThis {
                        ProgressView()
                            .scaleEffect(0.5)
                    } else {
                        Image(systemName: item.source.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? .primary : .secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 2.5) {
                    HStack(spacing: 5) {
                        Text(item.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        if isReady {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                                .help("Ready on disk or server")
                        }
                    }

                    HStack(spacing: 5) {
                        Text(item.author)
                            .lineLimit(1)

                        if let firstParam = item.parameterSizes.first {
                            Text("· \(firstParam)")
                        }

                        if let dl = item.formattedDownloads {
                            Text("· ↓ \(dl)")
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let firstCap = item.capabilities.first {
                    Text(firstCap)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? Color.primary.opacity(0.075) : Color.clear)
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Right Detail Pane

    @ViewBuilder
    private var rightDetailPane: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(item)
                Divider().opacity(0.5)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let activeDL = llm.activeHubDownload {
                            liveDownloadBanner(activeDL)
                        }

                        if let err = llm.hubErrorMessage, !err.isEmpty {
                            feedbackBanner(icon: "exclamationmark.triangle.fill", color: .orange, text: err)
                        } else if let msg = llm.hubActionMessage, !msg.isEmpty {
                            feedbackBanner(icon: "checkmark.circle.fill", color: .green, text: msg)
                        }

                        // Summary
                        Text(item.summary)
                            .font(.system(size: 12.5))
                            .foregroundColor(.primary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)

                        // Metadata & Hardware Compatibility Row
                        metadataGrid(item)

                        Divider().opacity(0.5)

                        // Variants & Quantizations Picker + Primary Connect Action
                        variantsSection(item)
                    }
                    .padding(18)
                }
            }
        } else {
            VStack(spacing: 10) {
                Spacer()
                if llm.isFetchingHub {
                    ProgressView()
                    Text("Loading live catalog...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "cpu")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("Select a model to inspect live quantizations and connect")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ item: HubModelItem) -> some View {
        let variant = selectedVariant
        let isBusy = (llm.activeHubDownload != nil)

        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 38, height: 38)
                Image(systemName: item.source.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.repoOrSlug)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(item.repoOrSlug, forType: .string)
                        copiedRepoID = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedRepoID = false }
                    }) {
                        Image(systemName: copiedRepoID ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy model ID")

                    if let url = item.webURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            HStack(spacing: 2) {
                                Text("Source")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()

            // Secondary LM Studio button for GGUF repos when LM Studio is installed
            if item.source == .gguf && llm.hasLMStudioInstalled {
                Button(action: {
                    llm.openInLMStudio(repoID: item.repoOrSlug, filename: variant?.primaryFilename)
                }) {
                    Text("Open in LM Studio")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            // Primary Real Action Button
            Button(action: {
                llm.installAndConnectHubModel(item: item, variant: variant) { activatedModelID in
                    onActivateModel?(activatedModelID)
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: primaryButtonIcon(item: item, variant: variant))
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(primaryButtonTitle(item: item, variant: variant))
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary)
            .foregroundColor(Color(nsColor: .windowBackgroundColor))
            .controlSize(.regular)
            .disabled(isBusy)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.primary.opacity(0.015))
    }

    private func metadataGrid(_ item: HubModelItem) -> some View {
        let variant = selectedVariant
        let fit = variant?.ramFit(totalRAMBytes: llm.physicalMemoryBytes) ?? .unknown

        return HStack(spacing: 8) {
            metricBox(title: "Runtime", value: runtimeLabel(for: item.source))

            if let variant, variant.sizeBytes > 0 {
                metricBox(title: "Download Size", value: variant.sizeLabel)
            } else if let firstParam = item.parameterSizes.first {
                metricBox(title: "Parameters", value: firstParam)
            }

            if let dl = item.formattedDownloads {
                metricBox(title: "Downloads", value: dl)
            } else if !item.updatedLabel.isEmpty {
                metricBox(title: "Status", value: item.updatedLabel)
            }

            // Hardware RAM Fit Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(ramFitColor(fit))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Memory Check")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    Text(ramFitLabel(fit))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )

            Spacer(minLength: 0)
        }
    }

    private func variantsSection(_ item: HubModelItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.source == .ollama ? "Available Tags" : (item.source == .gguf ? "Quantization Files (.gguf)" : "Model Weights"))
                    .font(.system(size: 12, weight: .semibold))

                if llm.isFetchingHubDetail && !item.detailsLoaded {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.5).frame(width: 12, height: 12)
                        Text("Fetching exact file sizes...")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !item.capabilities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.capabilities, id: \.self) { cap in
                            Text(cap)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05))
                                .cornerRadius(4)
                        }
                    }
                }
            }

            VStack(spacing: 5) {
                ForEach(item.variants) { variant in
                    variantRow(item: item, variant: variant)
                }
            }
        }
    }

    private func variantRow(item: HubModelItem, variant: HubModelVariant) -> some View {
        let isChosen = (selectedVariant?.id == variant.id)
        let fit = variant.ramFit(totalRAMBytes: llm.physicalMemoryBytes)
        let isActiveModel = (llm.selectedModelId.lowercased() == variant.id.lowercased())

        return Button(action: {
            selectedVariantID = variant.id
        }) {
            HStack(spacing: 10) {
                Image(systemName: isChosen ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 12.5))
                    .foregroundColor(isChosen ? .primary : .secondary)

                Text(variant.label)
                    .font(.system(size: 11.5, weight: isChosen ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let q = variant.quantization, !variant.label.uppercased().contains(q.uppercased()) {
                    Text(q)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                }

                if let ctx = variant.contextWindow {
                    Text("\(ctx) ctx")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isActiveModel {
                    Text("Active in Chat")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.10))
                        .cornerRadius(4)
                } else if variant.isDownloadedOnDisk {
                    Text("Ready")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(4)
                }

                if variant.sizeBytes > 0 {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ramFitColor(fit))
                            .frame(width: 5.5, height: 5.5)
                        Text(variant.sizeLabel)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8.5)
            .background(isChosen ? Color.primary.opacity(0.065) : Color.primary.opacity(0.02))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isChosen ? Color.primary.opacity(0.22) : Color.primary.opacity(0.06), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Live Progress & Status Banners

    private func liveDownloadBanner(_ dl: ActiveModelDownloadState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 7) {
                    ProgressView()
                        .scaleEffect(0.55)
                        .frame(width: 14, height: 14)
                    Text(dl.title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }

                Spacer()

                if !dl.isIndeterminate {
                    Text("\(String(Int(dl.fractionCompleted * 100)))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Button("Cancel") {
                    llm.cancelActiveHubDownload()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if !dl.isIndeterminate {
                ProgressView(value: dl.fractionCompleted)
                    .tint(.primary)
            }

            HStack {
                Text(dl.statusText)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                if dl.totalBytes > 0 {
                    Text(dl.progressSummary)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func feedbackBanner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func metricBox(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private func ensureValidSelectionAndLoadDetails() {
        guard !llm.hubModels.isEmpty else {
            selectedModelID = nil
            selectedVariantID = nil
            return
        }
        if let cur = selectedModelID, llm.hubModels.contains(where: { $0.id == cur }) {
            return
        }
        let first = llm.hubModels[0]
        selectedModelID = first.id
        selectedVariantID = first.variants.first?.id
        Task {
            await llm.fetchHubModelDetails(itemID: first.id)
            if let refreshed = llm.hubModels.first(where: { $0.id == first.id }) {
                selectedVariantID = refreshed.variants.first?.id
            }
        }
    }

    private var searchPlaceholder: String {
        switch selectedSource {
        case .mlx: return "Search Hugging Face MLX (e.g. qwen3, gemma)..."
        case .ollama: return "Search Ollama Library (e.g. qwen3, deepseek)..."
        case .gguf: return "Search Hugging Face GGUF (e.g. coder, llama)..."
        case .installed: return "Filter installed models..."
        }
    }

    private var upstreamDomainLabel: String {
        switch selectedSource {
        case .ollama: return "ollama.com"
        case .mlx, .gguf: return "huggingface.co"
        case .installed: return "This Mac & LAN"
        }
    }

    private func runtimeLabel(for source: ModelHubSource) -> String {
        switch source {
        case .mlx: return llm.mlxServerBinaryPath != nil ? "MLX Metal Ready" : "MLX (Python)"
        case .ollama: return llm.ollamaBinaryPath != nil ? "Ollama Ready" : "Ollama"
        case .gguf: return llm.ollamaBinaryPath != nil ? "Ollama / LM Studio" : "GGUF"
        case .installed: return "Local / LAN"
        }
    }

    private func primaryButtonTitle(item: HubModelItem, variant: HubModelVariant?) -> String {
        let onDisk = variant?.isDownloadedOnDisk ?? false
        switch item.source {
        case .installed:
            return item.installedServerEndpoint != nil ? "Use in Chat" : "Start & Use"
        case .mlx:
            return onDisk ? "Start MLX & Use" : "Download & Start MLX"
        case .ollama:
            return onDisk ? "Use in Chat" : "Pull & Connect"
        case .gguf:
            return onDisk ? "Run & Connect" : "Download & Run"
        }
    }

    private func primaryButtonIcon(item: HubModelItem, variant: HubModelVariant?) -> String {
        let onDisk = variant?.isDownloadedOnDisk ?? false
        if item.source == .installed || onDisk {
            return "bolt.fill"
        }
        return "arrow.down.circle.fill"
    }

    private func ramFitColor(_ fit: ModelRAMFitStatus) -> Color {
        switch fit {
        case .fits: return .green
        case .tight: return .orange
        case .tooLarge: return .red.opacity(0.8)
        case .unknown: return .secondary
        }
    }

    private func ramFitLabel(_ fit: ModelRAMFitStatus) -> String {
        switch fit {
        case .fits: return "Fits in \(llm.physicalMemoryGBLabel)"
        case .tight: return "Tight (\(llm.physicalMemoryGBLabel))"
        case .tooLarge: return "Exceeds \(llm.physicalMemoryGBLabel)"
        case .unknown: return "\(llm.physicalMemoryGBLabel) RAM"
        }
    }
}
