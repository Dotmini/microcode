//
//  AITrainerView.swift
//  CodeTunner
//
//  AI Model Training - Apple Minimal Design
//  Created by SPU AI CLUB
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import SwiftUI
import Charts

// MARK: - Main AI Trainer View

// MARK: - Main AI Trainer View

struct AITrainerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var trainer = MLTrainer.shared
    @State private var selectedTab: TrainerTab = .dataset
    @State private var showingDatasetPicker = false
    @State private var showingExportSheet = false
    @State private var isHoveringClose = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            ZStack {
                VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                
                navigationSidebar
            }
            .frame(width: 240)
            
            Divider()
                .opacity(0.5)
            
            // Main Content Area
            VStack(spacing: 0) {
                // Toolbar-like Header
                headerView
                    .frame(height: 52)
                    .background(VisualEffectBlur(material: .headerView, blendingMode: .withinWindow))
                
                Divider()
                    .opacity(0.3)
                
                // Content
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .fileImporter(
            isPresented: $showingDatasetPicker,
            allowedContentTypes: [.folder],
            onCompletion: handleDatasetSelection
        )
        .sheet(isPresented: $showingExportSheet) {
            ExportModelSheet(trainer: trainer)
        }
    }
    
    // MARK: - Header (Apple Minimal)
    
    private var headerView: some View {
        HStack(spacing: 16) {
            Text(selectedTab.rawValue)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundColor(.primary)
            
            Spacer()
            
            // Training Status - Minimal Capsule
            if trainer.trainingState.isActive {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                    
                    Text("Training")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("\(Int(trainer.trainingProgress.percentComplete * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.1))
                )
            }
            
            // Close Button - Integrated
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(isHoveringClose ? 0.2 : 0.0))
                    )
            }
            .buttonStyle(.plain)
            .onHover { isHoveringClose = $0 }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Navigation Sidebar
    
    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            // App Identity
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.1))
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    Text("AI Trainer")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Pro Series")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 8)
            
            // Navigation Items
            ScrollView {
                VStack(spacing: 4) {
                    Group {
                        Text("WORKSPACE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                        
                        NavigationTabButton(tab: .dataset, selectedTab: $selectedTab)
                        NavigationTabButton(tab: .models, selectedTab: $selectedTab)
                    }
                    
                    Group {
                        Text("DEVELOPMENT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        
                        NavigationTabButton(tab: .training, selectedTab: $selectedTab)
                        NavigationTabButton(tab: .monitor, selectedTab: $selectedTab)
                        NavigationTabButton(tab: .validation, selectedTab: $selectedTab)
                    }
                    
                    Group {
                        Text("DISTRIBUTION")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                        
                        NavigationTabButton(tab: .export, selectedTab: $selectedTab)
                    }
                }
                .padding(.horizontal, 8)
            }
            
            Spacer()
            
            // Quick Actions Area
            VStack(spacing: 8) {
                Divider()
                
                QuickActionButton(
                    icon: "square.and.arrow.up",
                    title: "Export Model",
                    color: .primary,
                    disabled: trainer.trainingState != .completed
                ) {
                    showingExportSheet = true
                }
                
                QuickActionButton(
                    icon: "folder.badge.plus",
                    title: "Load Dataset",
                    color: .primary
                ) {
                    showingDatasetPicker = true
                }
            }
            .padding(16)
        }
    }
    
    // MARK: - Main Content
    
    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch selectedTab {
            case .dataset:
                DatasetTabView(trainer: trainer, showingPicker: $showingDatasetPicker)
            case .models:
                ModelSelectionTabView(trainer: trainer)
            case .training:
                TrainingConfigTabView(trainer: trainer)
            case .monitor:
                TrainingMonitorTabView(trainer: trainer)
            case .validation:
                ValidationTabView(trainer: trainer)
            case .export:
                ExportTabView(trainer: trainer, showingExportSheet: $showingExportSheet)
            }
        }
    }
    
    private func handleDatasetSelection(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            Task {
                do {
                    _ = try await trainer.loadDataset(url: url)
                } catch {
                    print("Failed to load dataset: \(error)")
                }
            }
        case .failure(let error):
            print("Dataset selection failed: \(error)")
        }
    }
}

// MARK: - Tab Enum

enum TrainerTab: String, CaseIterable {
    case dataset = "Dataset"
    case models = "Model Selection"
    case training = "Configuration"
    case monitor = "Training Monitor"
    case validation = "Validation"
    case export = "Export & Deploy"
    
    var icon: String {
        switch self {
        case .dataset: return "folder"
        case .models: return "cube"
        case .training: return "slider.horizontal.3"
        case .monitor: return "chart.xyaxis.line"
        case .validation: return "checkmark.shield"
        case .export: return "shippingbox"
        }
    }
    
    var color: Color {
        switch self {
        default: return .blue
        }
    }
}

// MARK: - Navigation Tab Button

struct NavigationTabButton: View {
    let tab: TrainerTab
    @Binding var selectedTab: TrainerTab
    @State private var isHovering = false
    
    private var isSelected: Bool {
        selectedTab == tab
    }
    
    var body: some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? tab.icon + ".fill" : tab.icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : .primary)
                    .frame(width: 20)
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.blue : (isHovering ? Color.secondary.opacity(0.1) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Quick Action Button

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    var disabled: Bool = false
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(disabled ? .secondary : color)
                
                Text(title)
                    .font(.system(size: 12))
                    .foregroundColor(disabled ? .secondary : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovering && !disabled ? Color.secondary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Dataset Tab View

struct DatasetTabView: View {
    @ObservedObject var trainer: MLTrainer
    @Binding var showingPicker: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Card
                SectionCard(title: "Dataset Management", icon: "folder.badge.gearshape", color: .blue) {
                    if let dataset = trainer.currentDataset {
                        DatasetLoadedView(dataset: dataset)
                    } else {
                        DatasetEmptyView(showingPicker: $showingPicker)
                    }
                }
                
                if trainer.currentDataset != nil {
                    // Dataset Statistics
                    SectionCard(title: "Statistics", icon: "chart.bar.fill", color: .blue) {
                        DatasetStatsView(dataset: trainer.currentDataset!)
                    }
                    
                    // Class Distribution
                    SectionCard(title: "Class Distribution", icon: "square.grid.3x3.fill", color: .blue) {
                        ClassDistributionView(dataset: trainer.currentDataset!)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct DatasetEmptyView: View {
    @Binding var showingPicker: Bool
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
            }
            
            Text("No Dataset Loaded")
                .font(.title2.bold())
            
            Text("Drag a folder here or click Browse to select your training dataset.\nOrganize images in subdirectories by class name.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button {
                showingPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                    Text("Browse Dataset Folder")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isDragging ? Color.blue : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [10])
                )
        )
        .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
            // Handle drop
            return true
        }
    }
}

struct DatasetLoadedView: View {
    let dataset: MLDataset
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.green)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(dataset.name)
                    .font(.system(size: 16, weight: .semibold))
                
                Text("\(dataset.totalImages) images • \(dataset.classes.count) classes")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct DatasetStatsView: View {
    let dataset: MLDataset
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            StatCard(title: "Total Images", value: "\(dataset.totalImages)", icon: "photo.stack", color: .blue)
            StatCard(title: "Classes", value: "\(dataset.classes.count)", icon: "tag", color: .purple)
            StatCard(title: "Avg per Class", value: "\(dataset.totalImages / max(dataset.classes.count, 1))", icon: "divide", color: .orange)
        }
        .padding()
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
                Spacer()
            }
            
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

struct ClassDistributionView: View {
    let dataset: MLDataset
    
    var body: some View {
        VStack(spacing: 12) {
            ForEach(dataset.classes.sorted(), id: \.self) { className in
                HStack {
                    Text(className)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 150, alignment: .leading)
                    
                    GeometryReader { geo in
                        let count = dataset.imageCount[className] ?? 0
                        let maxCount = dataset.imageCount.values.max() ?? 1
                        let width = geo.size.width * CGFloat(count) / CGFloat(maxCount)
                        
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: width)
                        }
                    }
                    .frame(height: 24)
                    
                    Text("\(dataset.imageCount[className] ?? 0)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
        .padding()
    }
}

// MARK: - Section Card

struct SectionCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }
            
            content
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Model Selection Tab View

struct ModelSelectionTabView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SectionCard(title: "Select Base Model", icon: "cube.fill", color: .purple) {
                    Text("Choose a pretrained model to fine-tune on your dataset")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 20) {
                    ForEach(PretrainedModel.availableModels) { model in
                        EnterpriseModelCard(
                            model: model,
                            isSelected: trainer.selectedModel?.id == model.id
                        ) {
                            trainer.selectedModel = model
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

struct EnterpriseModelCard: View {
    let model: PretrainedModel
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing).opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: model.icon)
                            .font(.system(size: 20))
                            .foregroundColor(.purple)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.name)
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text(model.architecture)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Text(model.description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(height: 32, alignment: .top)
                
                Divider()
                
                HStack {
                    Label("\(Int(model.inputSize.width))", systemImage: "square.resize")
                    Spacer()
                    Label("\(model.parameterCount / 1_000_000)M", systemImage: "cpu")
                }
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.primary.opacity(isHovering ? 0.1 : 0.05), lineWidth: isSelected ? 2 : 1)
            )
            .shadow(color: Color.black.opacity(isHovering ? 0.05 : 0), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .scaleEffect(isHovering ? 1.01 : 1)
        .animation(.spring(response: 0.3), value: isHovering)
    }
}

// MARK: - Training Config Tab View

struct TrainingConfigTabView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hyperparameters
                SectionCard(title: "Hyperparameters", icon: "slider.horizontal.3", color: .blue) {
                    VStack(spacing: 20) {
                        // Learning Rate
                        ConfigSlider(
                            title: "Learning Rate",
                            value: $trainer.trainingConfig.learningRate,
                            range: 0.0001...0.1,
                            format: "%.4f"
                        )
                        
                        // Batch Size
                        ConfigPicker(title: "Batch Size", selection: $trainer.trainingConfig.batchSize) {
                            ForEach([8, 16, 32, 64, 128], id: \.self) { size in
                                Text("\(size)").tag(size)
                            }
                        }
                        
                        // Epochs
                        ConfigStepper(
                            title: "Epochs",
                            value: $trainer.trainingConfig.epochs,
                            range: 1...100
                        )
                        
                        // Optimizer
                        ConfigPicker(title: "Optimizer", selection: $trainer.trainingConfig.optimizer) {
                            ForEach(Optimizer.allCases, id: \.self) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                        
                        // Learning Rate Scheduler
                        ConfigPicker(title: "LR Scheduler", selection: $trainer.trainingConfig.scheduler) {
                            ForEach(LRScheduler.allCases, id: \.self) { sched in
                                Text(sched.rawValue).tag(sched)
                            }
                        }
                    }
                }
                
                // Data Augmentation
                SectionCard(title: "Data Augmentation", icon: "wand.and.stars", color: .blue) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AugmentationToggle(title: "Random Rotation", isOn: $trainer.trainingConfig.augmentation.randomRotation, icon: "rotate.right")
                        AugmentationToggle(title: "Random Flip", isOn: $trainer.trainingConfig.augmentation.randomFlip, icon: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                        AugmentationToggle(title: "Random Crop", isOn: $trainer.trainingConfig.augmentation.randomCrop, icon: "crop")
                        AugmentationToggle(title: "Color Jitter", isOn: $trainer.trainingConfig.augmentation.colorJitter, icon: "paintpalette")
                    }
                }
                
                // Advanced Settings
                SectionCard(title: "Advanced Settings", icon: "gearshape.2.fill", color: .blue) {
                    VStack(spacing: 16) {
                        Toggle("Transfer Learning (Freeze Base Layers)", isOn: $trainer.trainingConfig.transferLearning)
                        
                        ConfigStepper(
                            title: "Early Stopping Patience",
                            value: $trainer.trainingConfig.earlyStoppingPatience,
                            range: 1...20
                        )
                        
                        // Regularization
                        ConfigPicker(title: "Regularization", selection: $trainer.trainingConfig.regularization) {
                            ForEach(RegularizationType.allCases, id: \.self) { reg in
                                Text(reg.rawValue).tag(reg)
                            }
                        }
                        
                        Toggle("Gradient Clipping", isOn: $trainer.trainingConfig.gradientClipping)
                        Toggle("Mixed Precision Training", isOn: $trainer.trainingConfig.mixedPrecision)
                    }
                }
                
                // Save Config Button
                Button(action: saveConfiguration) {
                    HStack {
                        Image(systemName: "square.and.arrow.down")
                        Text("Save Configuration")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(24)
        }
    }
    
    private func saveConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "training_config.json"
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(trainer.trainingConfig)
                try data.write(to: url)
            } catch {
                print("Failed to save config: \(error)")
            }
        }
    }
}

struct ConfigSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .leading)
            
            Slider(value: $value, in: range)
                .frame(maxWidth: 250)
            
            Text(String(format: format, value))
                .font(.system(.body, design: .monospaced))
                .frame(width: 80, alignment: .trailing)
        }
    }
}

struct ConfigPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    @Binding var selection: SelectionValue
    @ViewBuilder let content: Content
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .leading)
            
            Picker("", selection: $selection) {
                content
            }
            .frame(maxWidth: 250)
        }
    }
}

struct ConfigStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    
    var body: some View {
        HStack {
            Text(title)
                .frame(width: 150, alignment: .leading)
            
            Stepper("\(value)", value: $value, in: range)
        }
    }
}

struct AugmentationToggle: View {
    let title: String
    @Binding var isOn: Bool
    let icon: String
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(isOn ? .cyan : .secondary)
                Text(title)
                    .font(.callout)
            }
        }
        .toggleStyle(.switch)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isOn ? Color.cyan.opacity(0.1) : Color.clear)
        )
    }
}

// MARK: - Training Monitor Tab View

struct TrainingMonitorTabView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress Header
            if trainer.trainingState.isActive || trainer.trainingState == .completed {
                TrainingProgressHeader(trainer: trainer)
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    if trainer.epochMetrics.isEmpty && !trainer.trainingState.isActive {
                        EmptyMonitorView(trainer: trainer)
                    } else {
                        // Live Metrics
                        if trainer.trainingState.isActive {
                            LiveMetricsView(trainer: trainer)
                        }
                        
                        // Charts
                        if !trainer.epochMetrics.isEmpty {
                            VStack(spacing: 24) {
                                if #available(macOS 13.0, *) {
                                    SectionCard(title: "Training Loss", icon: "chart.xyaxis.line", color: .blue) {
                                        LossChart(metrics: trainer.epochMetrics)
                                            .frame(height: 250)
                                    }
                                    
                                    SectionCard(title: "Accuracy", icon: "chart.line.uptrend.xyaxis", color: .green) {
                                        AccuracyChart(metrics: trainer.epochMetrics)
                                            .frame(height: 250)
                                    }
                                } else {
                                    SectionCard(title: "Training Loss & Accuracy", icon: "chart.xyaxis.line", color: .blue) {
                                        VStack(spacing: 12) {
                                            Image(systemName: "chart.xyaxis.line")
                                                .font(.largeTitle)
                                            Text("Charts are available on macOS 13.0+")
                                                .foregroundColor(.secondary)
                                            
                                            // Simple List Fallback
                                            if let last = trainer.epochMetrics.last {
                                                HStack(spacing: 20) {
                                                    VStack {
                                                        Text("Loss")
                                                        Text(String(format: "%.4f", last.trainingLoss))
                                                            .bold()
                                                    }
                                                    VStack {
                                                        Text("Accuracy")
                                                        Text("\(Int(last.trainingAccuracy * 100))%")
                                                            .bold()
                                                    }
                                                }
                                                .padding()
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(8)
                                            }
                                        }
                                        .frame(height: 150)
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}

struct TrainingProgressHeader: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Epoch \(trainer.trainingProgress.currentEpoch) of \(trainer.trainingProgress.totalEpochs)")
                        .font(.headline)
                    Text("ETA: \(formatTime(trainer.trainingProgress.eta))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(trainer.trainingProgress.percentComplete * 100))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.green)
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                    
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * trainer.trainingProgress.percentComplete)
                }
            }
            .frame(height: 12)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct EmptyMonitorView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Ready to Train")
                .font(.title2.bold())
            
            Text("Configure your training parameters and click Start Training")
                .font(.callout)
                .foregroundColor(.secondary)
            
            if trainer.currentDataset != nil && trainer.selectedModel != nil {
                Button {
                    Task {
                        try? await trainer.startTraining()
                    }
                } label: {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Start Training")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Text("Please load a dataset and select a model first")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct LiveMetricsView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            TrainingMetricCard(title: "Train Loss", value: String(format: "%.4f", trainer.trainingProgress.trainingLoss), color: .red)
            TrainingMetricCard(title: "Train Acc", value: String(format: "%.1f%%", trainer.trainingProgress.trainingAccuracy * 100), color: .blue)
            TrainingMetricCard(title: "Val Loss", value: String(format: "%.4f", trainer.trainingProgress.validationLoss), color: .orange)
            TrainingMetricCard(title: "Val Acc", value: String(format: "%.1f%%", trainer.trainingProgress.validationAccuracy * 100), color: .green)
        }
    }
}

struct TrainingMetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

@available(macOS 13.0, *)
struct LossChart: View {
    let metrics: [EpochMetrics]
    
    var body: some View {
        Chart {
            ForEach(metrics) { metric in
                LineMark(
                    x: .value("Epoch", metric.epoch),
                    y: .value("Loss", metric.trainingLoss)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
                
                LineMark(
                    x: .value("Epoch", metric.epoch),
                    y: .value("Val Loss", metric.validationLoss)
                )
                .foregroundStyle(.orange)
                .symbol(.square)
            }
        }
        .chartLegend(position: .top)
        .padding()
    }
}

@available(macOS 13.0, *)
struct AccuracyChart: View {
    let metrics: [EpochMetrics]
    
    var body: some View {
        Chart {
            ForEach(metrics) { metric in
                LineMark(
                    x: .value("Epoch", metric.epoch),
                    y: .value("Accuracy", metric.trainingAccuracy)
                )
                .foregroundStyle(.blue)
                .symbol(.circle)
                
                LineMark(
                    x: .value("Epoch", metric.epoch),
                    y: .value("Val Acc", metric.validationAccuracy)
                )
                .foregroundStyle(.green)
                .symbol(.square)
            }
        }
        .chartLegend(position: .top)
        .padding()
    }
}

// MARK: - Validation Tab View

struct ValidationTabView: View {
    @ObservedObject var trainer: MLTrainer
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SectionCard(title: "Model Validation", icon: "checkmark.shield.fill", color: .cyan) {
                    if trainer.trainingState == .completed {
                        VStack(spacing: 20) {
                            HStack(spacing: 40) {
                                ValidationMetric(title: "Final Accuracy", value: "\(Int(trainer.trainingProgress.validationAccuracy * 100))%", color: .green)
                                ValidationMetric(title: "Final Loss", value: String(format: "%.4f", trainer.trainingProgress.validationLoss), color: .orange)
                                ValidationMetric(title: "Epochs Trained", value: "\(trainer.trainingProgress.currentEpoch)", color: .blue)
                            }
                        }
                    } else {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("Complete training to view validation results")
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(40)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct ValidationMetric: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Export Tab View

struct ExportTabView: View {
    @ObservedObject var trainer: MLTrainer
    @Binding var showingExportSheet: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if trainer.trainingState == .completed {
                    // Export Ready
                    SectionCard(title: "Export Your Model", icon: "square.and.arrow.up.fill", color: .pink) {
                        VStack(spacing: 20) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(.green)
                                
                                VStack(alignment: .leading) {
                                    Text("Model Ready for Export")
                                        .font(.title2.bold())
                                    Text("Choose your preferred format and export your trained model")
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                            }
                            
                            Divider()
                            
                            Text("Available Export Formats")
                                .font(.headline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                                ForEach(ExportFormat.allCases, id: \.self) { format in
                                    ExportFormatCard(format: format)
                                }
                            }
                            
                            Button {
                                showingExportSheet = true
                            } label: {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Export Model")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }
                    }
                } else {
                    // Not Ready
                    VStack(spacing: 20) {
                        Image(systemName: "cube.box")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No Model to Export")
                            .font(.title2.bold())
                        
                        Text("Complete training to export your model")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(60)
                }
            }
            .padding(24)
        }
    }
}

struct ExportFormatCard: View {
    let format: ExportFormat
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: format.icon)
                .font(.system(size: 20))
                .foregroundColor(format.color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(format.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(".\(format.fileExtension)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? format.color.opacity(0.1) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovering ? format.color.opacity(0.3) : Color.primary.opacity(0.05), lineWidth: 1)
        )
        .onHover { isHovering = $0 }
    }
}

// MARK: - Export Model Sheet

struct ExportModelSheet: View {
    @ObservedObject var trainer: MLTrainer
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .mlmodel
    @State private var isExporting = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Text("Export Model")
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Format Selection
            VStack(alignment: .leading, spacing: 12) {
                Text("Select Format")
                    .font(.headline)
                
                Picker("Format", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Label(format.displayName, systemImage: format.icon).tag(format)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            
            Spacer()
            
            // Export Button
            Button {
                exportModel()
            } label: {
                HStack {
                    if isExporting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isExporting ? "Exporting..." : "Export")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isExporting)
        }
        .padding(24)
        .frame(width: 400, height: 350)
    }
    
    private func exportModel() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "model.\(selectedFormat.fileExtension)"
        panel.allowedContentTypes = [.data]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                isExporting = true
                Task {
                    try? await trainer.exportModel(format: selectedFormat, to: url)
                    await MainActor.run {
                        isExporting = false
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Preview
