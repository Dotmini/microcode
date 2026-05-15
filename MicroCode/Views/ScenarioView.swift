//
//  ScenarioView.swift
//  MicroCode
//
//  n8n-Style Visual Automation Workflow Builder
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Scenario View (n8n Style)

struct ScenarioView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var manager = ScenarioManager.shared
    
    // Node selection state
    @State private var selectedPaletteNode: ScenarioNodeType? = nil
    @State private var selectedCanvasNode: ScenarioNode? = nil
    @State private var nodeCounter: Int = 0
    
    // Canvas pan/zoom state for seamless scrolling
    @State private var canvasOffset: CGSize = .zero
    @State private var canvasScale: CGFloat = 1.0
    @State private var lastDragOffset: CGSize = .zero
    @State private var isPanning: Bool = false
    
    // UI state
    @State private var showLogs = true
    @State private var showNodeSettings = true
    @State private var isAddingConnection = false
    @State private var connectionSourceNode: ScenarioNode?
    
    // New features
    @State private var isEditingName = false
    @State private var editingName = ""
    @State private var showScheduleSheet = false
    @State private var scheduleMinutes = 5
    @State private var isPresentMode = false
    @State private var showNewScenarioSheet = false
    @State private var newScenarioName = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            scenarioToolbar
            
            Divider()
            
            // Main Content
            HStack(spacing: 0) {
                // Left: Node Palette
                nodePalette
                    .frame(width: 220)
                
                Divider()
                
                // Center: Canvas
                workflowCanvas
                
                Divider()
                
                // Right: Node Settings + Logs
                if showNodeSettings || showLogs {
                    rightPanel
                        .frame(width: 320)
                }
            }
        }
        .background(appState.appTheme == .transparent || appState.appTheme == .extraClear ? Color.clear : Color.compat(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Toolbar
    
    private var scenarioToolbar: some View {
        HStack(spacing: 12) {
            // Scenario Switcher
            Menu {
                ForEach(manager.scenarios, id: \.id) { scenario in
                    Button(action: { manager.activeScenario = scenario }) {
                        HStack {
                            Text(scenario.name)
                            if scenario.id == manager.activeScenario?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("New Scenario...") {
                    newScenarioName = ""
                    showNewScenarioSheet = true
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "flowchart.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.orange)
                    
                    if isEditingName {
                        TextField("Name", text: $editingName, onCommit: {
                            manager.activeScenario?.name = editingName
                            isEditingName = false
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 160)
                    } else {
                        Text(manager.activeScenario?.name ?? "Untitled")
                            .font(.system(size: 14, weight: .semibold))
                            .onTapGesture(count: 2) {
                                editingName = manager.activeScenario?.name ?? ""
                                isEditingName = true
                            }
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .menuStyle(.borderlessButton)
            
            // Node count + run count
            if let scenario = manager.activeScenario {
                if !scenario.nodes.isEmpty {
                    Text("\(scenario.nodes.count) nodes")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(10)
                }
                if scenario.runCount > 0 {
                    Text("×\(scenario.runCount)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.green)
                }
            }
            
            Spacer()
            
            // Selected node indicator
            if let node = selectedPaletteNode {
                HStack(spacing: 6) {
                    Image(systemName: node.icon)
                        .foregroundColor(node.color)
                    Text("Click canvas to place: \(node.rawValue)")
                        .font(.system(size: 11))
                    Button("Cancel") { selectedPaletteNode = nil }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(node.color.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
            
            // Schedule indicator
            if manager.isScheduled {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text("Every \(manager.scheduleIntervalSeconds)s")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1))
                .cornerRadius(6)
            }
            
            // Save
            Button(action: { manager.saveScenario() }) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .help("Save Scenario")
            
            // Schedule
            Button(action: { showScheduleSheet.toggle() }) {
                Image(systemName: manager.isScheduled ? "clock.fill" : "clock")
                    .font(.system(size: 13))
                    .foregroundColor(manager.isScheduled ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Schedule")
            .popover(isPresented: $showScheduleSheet) {
                schedulePopover
            }
            
            // Panel toggles
            Button(action: { showNodeSettings.toggle() }) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundColor(showNodeSettings ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Node Settings")
            
            Button(action: { showLogs.toggle() }) {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(showLogs ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Logs")
            
            Divider().frame(height: 18)
            
            // Present Mode
            Button(action: { isPresentMode.toggle() }) {
                Image(systemName: isPresentMode ? "rectangle.inset.filled" : "rectangle.expand.vertical")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Present Mode")
            
            // Run button
            Button(action: {
                if manager.isRunning {
                    manager.isRunning = false
                } else {
                    Task { await manager.runScenario() }
                }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                    Text(manager.isRunning ? "Stop" : "Run")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(manager.activeScenario?.nodes.isEmpty ?? true)
            
            // Clear
            Button(action: clearCanvas) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .help("Clear Canvas")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showNewScenarioSheet) {
            VStack(spacing: 16) {
                Text("New Scenario")
                    .font(.headline)
                TextField("Scenario Name", text: $newScenarioName)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") { showNewScenarioSheet = false }
                    Spacer()
                    Button("Create") {
                        if !newScenarioName.isEmpty {
                            let s = manager.createScenario(name: newScenarioName)
                            manager.activeScenario = s
                            showNewScenarioSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newScenarioName.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 350)
        }
    }
    
    // MARK: - Schedule Popover
    
    private var schedulePopover: some View {
        VStack(spacing: 14) {
            Text("⏱ Schedule")
                .font(.system(size: 13, weight: .semibold))
            
            Picker("Interval", selection: $scheduleMinutes) {
                Text("30 sec").tag(1) // 30s mapped as 1 for simplicity
                Text("1 min").tag(1)
                Text("5 min").tag(5)
                Text("15 min").tag(15)
                Text("30 min").tag(30)
                Text("1 hour").tag(60)
            }
            .pickerStyle(.segmented)
            
            if manager.isScheduled {
                Button("Stop Schedule") {
                    manager.stopSchedule()
                    showScheduleSheet = false
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Start Schedule") {
                    manager.startSchedule(interval: scheduleMinutes * 60)
                    showScheduleSheet = false
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
    
    // MARK: - Node Palette (n8n style)
    
    private var nodePalette: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("NODES")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            // Scrollable node list
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(NodeCategory.allCases, id: \.self) { category in
                        if let nodes = ScenarioNodeType.byCategory[category], !nodes.isEmpty {
                            categorySection(category, nodes: nodes)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color.compat(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private func categorySection(_ category: NodeCategory, nodes: [ScenarioNodeType]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category header
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 10))
                Text(category.rawValue.uppercased())
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(.secondary)
            
            // Node buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(nodes) { nodeType in
                    paletteNodeButton(nodeType)
                }
            }
        }
    }
    
    private func paletteNodeButton(_ type: ScenarioNodeType) -> some View {
        Button(action: {
            // Select this node type for placement
            selectedPaletteNode = type
        }) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(type.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: type.icon)
                        .font(.system(size: 18))
                        .foregroundColor(type.color)
                }
                
                Text(type.rawValue)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selectedPaletteNode == type ? type.color.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selectedPaletteNode == type ? type.color : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Workflow Canvas (n8n style)
    
    private var workflowCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                // Grid background
                canvasGrid
                
                // Connection lines
                connectionLines
                
                // Nodes on canvas
                ForEach(manager.activeScenario?.nodes ?? []) { node in
                    canvasNodeView(node)
                }
                
                // Empty state
                if manager.activeScenario?.nodes.isEmpty ?? true {
                    emptyCanvasView
                }
            }
            .scaleEffect(canvasScale)
            .offset(canvasOffset)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: canvasOffset)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: canvasScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.compat(nsColor: .textBackgroundColor))
            .clipped()
            .contentShape(Rectangle())
            // Tap to place node or deselect (macOS 12 compatible)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let location = value.location
                        let adjustedLocation = CGPoint(
                            x: (location.x - canvasOffset.width) / canvasScale,
                            y: (location.y - canvasOffset.height) / canvasScale
                        )
                        
                        if let nodeType = selectedPaletteNode {
                            placeNode(type: nodeType, at: adjustedLocation)
                            selectedPaletteNode = nil
                        } else {
                            if !isPanning { // Avoid deselecting if we just panned
                                selectedCanvasNode = nil
                            }
                        }
                    }
            )
            // Pan gesture (drag with Option key or two-finger)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isPanning {
                            isPanning = true
                            lastDragOffset = canvasOffset
                        }
                        canvasOffset = CGSize(
                            width: lastDragOffset.width + value.translation.width,
                            height: lastDragOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        isPanning = false
                    }
            )
            // Zoom gesture
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = max(0.5, min(2.0, value))
                        canvasScale = newScale
                    }
            )
            // Scroll wheel zoom
            // Zoom controls overlay
            .overlay(alignment: .bottomTrailing) {
                HStack(spacing: 8) {
                    Button(action: { withAnimation { canvasScale = max(0.5, canvasScale - 0.1) } }) {
                        Image(systemName: "minus.magnifyingglass")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(Int(canvasScale * 100))%")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 40)
                    
                    Button(action: { withAnimation { canvasScale = min(2.0, canvasScale + 0.1) } }) {
                        Image(systemName: "plus.magnifyingglass")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    
                    Divider().frame(height: 16)
                    
                    Button(action: { withAnimation { canvasScale = 1.0; canvasOffset = .zero } }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Reset View")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial)
                .cornerRadius(8)
                .padding(12)
            }
        }
    }
    
    private var canvasGrid: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let gridSize: CGFloat = 25
                let dotColor = Color.secondary.opacity(0.2)
                
                for x in stride(from: 0, to: size.width, by: gridSize) {
                    for y in stride(from: 0, to: size.height, by: gridSize) {
                        let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                    }
                }
            }
        }
    }
    
    private var connectionLines: some View {
        ForEach(manager.activeScenario?.connections ?? []) { connection in
            if let source = manager.activeScenario?.nodes.first(where: { $0.id == connection.sourceNodeId }),
               let target = manager.activeScenario?.nodes.first(where: { $0.id == connection.targetNodeId }) {
                Path { path in
                    let startX = source.position.x + 80
                    let startY = source.position.y
                    let endX = target.position.x - 80
                    let endY = target.position.y
                    let midX = (startX + endX) / 2
                    
                    path.move(to: CGPoint(x: startX, y: startY))
                    path.addCurve(
                        to: CGPoint(x: endX, y: endY),
                        control1: CGPoint(x: midX, y: startY),
                        control2: CGPoint(x: midX, y: endY)
                    )
                }
                .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }
    }
    
    private func canvasNodeView(_ node: ScenarioNode) -> some View {
        ZStack {
            // Main node card
            VStack(spacing: 0) {
                // Node header
                HStack(spacing: 6) {
                    Image(systemName: node.type.icon)
                        .font(.system(size: 12))
                    Text(node.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(node.type.color)
                
                // Node body
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.type.rawValue)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if node.hasError {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Error")
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color.compat(nsColor: .controlBackgroundColor))
            }
            .frame(width: 160)
            .cornerRadius(10)
            .shadow(color: selectedCanvasNode?.id == node.id ? node.type.color.opacity(0.5) : .black.opacity(0.15), radius: selectedCanvasNode?.id == node.id ? 10 : 4)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedCanvasNode?.id == node.id ? node.type.color : .clear, lineWidth: 3)
            )
            
            // Input Port (Left)
            Circle()
                .fill(isAddingConnection && connectionSourceNode != nil ? Color.green : Color.gray)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(x: -80, y: 0)
                .onTapGesture {
                    if isAddingConnection, let source = connectionSourceNode, source.id != node.id {
                        // Create connection
                        manager.connect(from: source, to: node)
                        connectionSourceNode = nil
                        isAddingConnection = false
                    }
                }
            
            // Output Port (Right)
            Circle()
                .fill(connectionSourceNode?.id == node.id ? Color.orange : node.type.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .offset(x: 80, y: 0)
                .onTapGesture {
                    // Start connection from this node
                    connectionSourceNode = node
                    isAddingConnection = true
                }
        }
        .position(node.position)
        .gesture(
            DragGesture()
                .onChanged { value in
                    node.position = value.location
                }
        )
        .onTapGesture {
            if isAddingConnection, let source = connectionSourceNode, source.id != node.id {
                // Complete connection
                manager.connect(from: source, to: node)
                connectionSourceNode = nil
                isAddingConnection = false
            } else {
                selectedCanvasNode = node
                selectedPaletteNode = nil
            }
        }
        .contextMenu {
            Button("Connect from here") {
                connectionSourceNode = node
                isAddingConnection = true
            }
            
            if !getOutgoingConnections(node).isEmpty {
                Button("Remove all connections") {
                    removeAllConnections(for: node)
                }
            }
            
            Divider()
            
            Button("Duplicate") {
                duplicateNode(node)
            }
            
            Button("Delete", role: .destructive) {
                manager.removeNode(node)
                if selectedCanvasNode?.id == node.id {
                    selectedCanvasNode = nil
                }
            }
        }
    }
    
    private var emptyCanvasView: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.5))
            
            Text("Select a node from the palette")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Then click on the canvas to place it")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.7))
        }
    }
    
    // MARK: - Right Panel
    
    private var rightPanel: some View {
        VStack(spacing: 0) {
            if showNodeSettings {
                nodeSettingsPanel
            }
            
            if showLogs {
                logsPanel
            }
        }
        .background(Color.compat(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private var nodeSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("NODE SETTINGS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                
                if selectedCanvasNode != nil {
                    Button(action: {
                        Task {
                            if let node = selectedCanvasNode {
                                await manager.executeSingleNode(node)
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.fill")
                            Text("Test Node")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.blue, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    Button(action: saveNodeSettings) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Save")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Connection mode indicator
            if isAddingConnection, let source = connectionSourceNode {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundColor(.orange)
                    Text("Connecting from: \(source.name)")
                        .font(.system(size: 11))
                    Spacer()
                    Button("Cancel") {
                        cancelConnection()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
            }
            
            Divider()
            
            if let node = selectedCanvasNode {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Node info
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(node.type.color.opacity(0.15))
                                    .frame(width: 44, height: 44)
                                
                                Image(systemName: node.type.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(node.type.color)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Node name", text: Binding(
                                    get: { node.name },
                                    set: { node.name = $0 }
                                ))
                                .font(.system(size: 14, weight: .semibold))
                                .textFieldStyle(.plain)
                                
                                Text(node.type.rawValue)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Divider()
                        
                        // Node-specific settings
                        nodeConfigForm(node)
                    }
                    .padding(16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "cursorarrow.click")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Select a node to configure")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
        @ViewBuilder
    private func nodeConfigForm(_ node: ScenarioNode) -> some View {
        switch node.type {
        case .email:
            emailSettings(node)
        case .http:
            httpSettings(node)
        case .line:
            lineSettings(node)
        case .telegram:
            telegramSettings(node)
        case .whatsapp:
            whatsappSettings(node)
        case .slack:
            slackSettings(node)
        case .discord:
            discordSettings(node)
        case .code:
            codeSettings(node)
        case .delay:
            delaySettings(node)
        case .schedule, .trigger:
            triggerSettings(node)
        case .openai, .gemini, .claude, .deepseek, .glm, .perplexity:
            aiSettings(node)
        case .googleSheets:
            sheetsSettings(node)
        case .container:
             containerSettings(node)
        case .database:
            databaseSettings(node)
        case .broadcast:
            broadcastSettings(node)
        case .transform:
            transformSettings(node)
        case .filter:
            filterSettings(node)
        default:
            VStack(alignment: .leading, spacing: 8) {
                Text("Configuration for \(node.type.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Coming soon...")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
    }
    
    // MARK: - Node Settings Forms
    
    private func emailSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider
            settingSection("Provider") {
                Picker("", selection: Binding(
                    get: { node.config.smtpHost.contains("gmail") ? "gmail" : (node.config.smtpHost.contains("outlook") ? "outlook" : "custom") },
                    set: { provider in
                        switch provider {
                        case "gmail":
                            node.config.smtpHost = "smtp.gmail.com"
                            node.config.smtpPort = 587
                        case "outlook":
                            node.config.smtpHost = "smtp.office365.com"
                            node.config.smtpPort = 587
                        default: break
                        }
                    }
                )) {
                    Text("Gmail").tag("gmail")
                    Text("Outlook").tag("outlook")
                    Text("Custom SMTP").tag("custom")
                }
                .pickerStyle(.segmented)
            }
            
            // Recipient
            settingField("To", placeholder: "recipient@email.com", text: Binding(
                get: { node.config.emailTo },
                set: { node.config.emailTo = $0 }
            ))
            
            // Subject
            settingField("Subject", placeholder: "Email subject", text: Binding(
                get: { node.config.emailSubject },
                set: { node.config.emailSubject = $0 }
            ))
            
            // Body
            settingSection("Message") {
                TextEditor(text: Binding(
                    get: { node.config.emailBody },
                    set: { node.config.emailBody = $0 }
                ))
                .font(.system(size: 12))
                .frame(height: 100)
                .padding(8)
                .background(Color.compat(nsColor: .textBackgroundColor))
                .cornerRadius(8)
            }
            
            // SMTP Settings
            DisclosureGroup("SMTP Configuration") {
                VStack(spacing: 12) {
                    HStack {
                        settingField("Host", placeholder: "smtp.gmail.com", text: Binding(get: { node.config.smtpHost }, set: { node.config.smtpHost = $0 }))
                        settingField("Port", placeholder: "587", text: Binding(get: { String(node.config.smtpPort) }, set: { node.config.smtpPort = Int($0) ?? 587 }))
                            .frame(width: 80)
                    }
                    settingField("Username", placeholder: "your@email.com", text: Binding(get: { node.config.smtpUser }, set: { node.config.smtpUser = $0 }))
                    settingSecureField("Password", placeholder: "App Password", text: Binding(get: { node.config.smtpPassword }, set: { node.config.smtpPassword = $0 }))
                    
                    Text("💡 Use App Password for Gmail")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func httpSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            settingSection("Method") {
                Picker("", selection: Binding(get: { node.config.httpMethod }, set: { node.config.httpMethod = $0 })) {
                    Text("GET").tag("GET")
                    Text("POST").tag("POST")
                    Text("PUT").tag("PUT")
                    Text("DELETE").tag("DELETE")
                }
                .pickerStyle(.segmented)
            }
            
            settingField("URL", placeholder: "https://api.example.com/endpoint", text: Binding(get: { node.config.httpUrl }, set: { node.config.httpUrl = $0 }))
            
            settingSection("Body (JSON)") {
                TextEditor(text: Binding(get: { node.config.httpBody }, set: { node.config.httpBody = $0 }))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
    
    private func lineSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Message Type Picker (Menu for responsiveness)
            HStack {
                Text("Type")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(get: { node.config.lineMessageType }, set: { node.config.lineMessageType = $0 })) {
                    Label("Push (User)", systemImage: "person.fill").tag("push")
                    Label("Broadcast (All)", systemImage: "megaphone.fill").tag("broadcast")
                    Label("Notify", systemImage: "bell.fill").tag("notify")
                    Label("Group", systemImage: "person.3.fill").tag("group")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            
            Divider()
            
            // Type-specific credentials (compact)
            Group {
                switch node.config.lineMessageType {
                case "notify":
                    compactSecureField("Notify Token", text: Binding(get: { node.config.lineNotifyToken }, set: { node.config.lineNotifyToken = $0 }))
                    Text("💡 notify-bot.line.me")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                case "broadcast":
                    compactSecureField("Channel Token", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
                    Label("Sends to ALL followers", systemImage: "megaphone.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                case "group":
                    compactSecureField("Channel Token", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
                    compactField("Group ID", text: Binding(get: { node.config.lineGroupId }, set: { node.config.lineGroupId = $0 }))
                default: // push
                    compactSecureField("Channel Token", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
                    compactField("User ID", text: Binding(get: { node.config.lineUserId }, set: { node.config.lineUserId = $0 }))
                }
            }
            
            Divider()
            
            // Message (compact)
            Text("Message")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            TextEditor(text: Binding(get: { node.config.lineMessage }, set: { node.config.lineMessage = $0 }))
                .font(.system(size: 11))
                .frame(height: 60)
                .padding(6)
                .background(Color.compat(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            
            // Image URL (optional, compact)
            compactField("Image URL", text: Binding(get: { node.config.lineImageUrl }, set: { node.config.lineImageUrl = $0 }))
        }
    }
    
    // Compact field helpers
    private func compactField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
    
    private func compactSecureField(_ label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            SecureField("", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
        }
    }
    
    private func telegramSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Bot Token
            settingSection("Telegram Bot API") {
                VStack(spacing: 8) {
                    settingSecureField("Bot Token", placeholder: "123456789:ABCdef...", text: Binding(get: { node.config.telegramBotToken }, set: { node.config.telegramBotToken = $0 }))
                    settingField("Chat ID", placeholder: "-100123456789 or @channel", text: Binding(get: { node.config.telegramChatId }, set: { node.config.telegramChatId = $0 }))
                    Text("💡 Get bot token from @BotFather")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // Message
            settingSection("Message") {
                TextEditor(text: Binding(get: { node.config.telegramMessage }, set: { node.config.telegramMessage = $0 }))
                    .font(.system(size: 12))
                    .frame(height: 80)
                    .padding(8)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
            
            // Parse mode
            settingSection("Format") {
                Picker("", selection: Binding(get: { node.config.telegramParseMode }, set: { node.config.telegramParseMode = $0 })) {
                    Text("HTML").tag("HTML")
                    Text("Markdown").tag("Markdown")
                    Text("Plain").tag("")
                }
                .pickerStyle(.segmented)
            }
            
            // Image (optional)
            DisclosureGroup("📷 Send Photo (Optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    settingField("Photo URL or file_id", placeholder: "https://example.com/photo.jpg", text: Binding(get: { node.config.telegramImageUrl }, set: { node.config.telegramImageUrl = $0 }))
                }
                .padding(.top, 4)
            }
            .font(.system(size: 11, weight: .medium))
        }
    }
    
    private func codeSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            settingSection("Language") {
                Picker("", selection: Binding(get: { node.config.codeLanguage }, set: { node.config.codeLanguage = $0 })) {
                    Text("Python").tag("python")
                    Text("JavaScript").tag("javascript")
                }
                .pickerStyle(.segmented)
            }
            
            settingSection("Code") {
                TextEditor(text: Binding(get: { node.config.codeContent }, set: { node.config.codeContent = $0 }))
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
            }
        }
    }
    
    private func delaySettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            settingField("Delay (seconds)", placeholder: "5", text: Binding(
                get: { String(node.config.delaySeconds) },
                set: { node.config.delaySeconds = Int($0) ?? 5 }
            ))
        }
    }
    
    private func triggerSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Trigger Type (if it's a Trigger node)
            if node.type == .trigger {
                HStack {
                    Text("Trigger Type")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                    Picker("", selection: .constant("manual")) {
                        Text("Manual").tag("manual")
                        Text("Interval").tag("interval")
                        Text("Cron").tag("cron")
                        Text("Webhook").tag("webhook")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                Divider()
            }
            
            // Interval
            compactField("Interval (sec)", text: Binding(
                get: { String(node.config.scheduleInterval) },
                set: { node.config.scheduleInterval = Int($0) ?? 60 }
            ))
            
            // Cron
            compactField("Cron", text: Binding(get: { node.config.scheduleCron }, set: { node.config.scheduleCron = $0 }))
            
            // Webhook (if trigger node)
            if node.type == .trigger {
                compactField("Webhook Path", text: Binding(get: { node.config.webhookPath }, set: { node.config.webhookPath = $0 }))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("💡 Cron: */5 * * * * = every 5 min")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text("💡 Interval: 60 = every 60 seconds")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - AI Settings (GenAI)
    
    private func aiSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Provider Picker
            HStack {
                Text("Provider")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(get: { node.config.aiProvider }, set: { node.config.aiProvider = $0 })) {
                    Text("ChatGPT").tag("chatgpt")
                    Text("Gemini").tag("gemini")
                    Text("Claude").tag("claude")
                    Text("DeepSeek").tag("deepseek")
                    Text("GLM").tag("glm")
                    Text("Perplexity").tag("perplexity")
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            
            Divider()
            
            // API Key
            compactSecureField("API Key", text: Binding(get: { node.config.aiApiKey }, set: { node.config.aiApiKey = $0 }))
            
            Divider()
            
            // System Prompt (optional)
            Text("System Prompt")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextEditor(text: Binding(get: { node.config.aiSystemPrompt }, set: { node.config.aiSystemPrompt = $0 }))
                .font(.system(size: 10))
                .frame(height: 50)
                .padding(4)
                .background(Color.compat(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            
            // User Prompt
            Text("Prompt")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            TextEditor(text: Binding(get: { node.config.aiPrompt }, set: { node.config.aiPrompt = $0 }))
                .font(.system(size: 11))
                .frame(height: 80)
                .padding(4)
                .background(Color.compat(nsColor: .textBackgroundColor))
                .cornerRadius(6)
            
            // Temperature & Max Tokens
            HStack {
                compactField("Temp", text: Binding(
                    get: { String(format: "%.1f", node.config.aiTemperature) },
                    set: { node.config.aiTemperature = Double($0) ?? 0.7 }
                ))
                compactField("Tokens", text: Binding(
                    get: { String(node.config.aiMaxTokens) },
                    set: { node.config.aiMaxTokens = Int($0) ?? 1024 }
                ))
            }
        }
    }
    
    // MARK: - Google Sheets Settings
    
    private func sheetsSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Spreadsheet ID
            compactField("Spreadsheet ID", text: Binding(get: { node.config.sheetsSpreadsheetId }, set: { node.config.sheetsSpreadsheetId = $0 }))
            
            // Range
            compactField("Range", text: Binding(get: { node.config.sheetsRange }, set: { node.config.sheetsRange = $0 }))
            
            // Action
            HStack {
                Text("Action")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: Binding(get: { node.config.sheetsAction }, set: { node.config.sheetsAction = $0 })) {
                    Text("Read").tag("read")
                    Text("Append").tag("append")
                    Text("Update").tag("update")
                    Text("Clear").tag("clear")
                }
                .pickerStyle(.menu)
                .frame(width: 100)
            }
            
            Text("💡 ID from URL: docs.google.com/spreadsheets/d/{ID}/edit")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Setting UI Components
    
    private func settingSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            content()
        }
    }
    
    private func settingField(_ title: String, placeholder: String, text: Binding<String>, allowVariables: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                if allowVariables {
                    variablePicker(for: text)
                }
            }
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
    
    private func settingSecureField(_ title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
        }
    }
    
    private var logsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("EXECUTION LOG")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { ScenarioManager.shared.clearLogs() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(manager.logs) { log in
                        HStack(alignment: .top, spacing: 8) {
                            Text(log.timestamp, style: .time)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            
                            Text(log.message)
                                .font(.system(size: 11))
                        }
                    }
                }
                .padding(12)
            }
        }
    }
    
    // MARK: - Actions
    
    private func placeNode(type: ScenarioNodeType, at location: CGPoint) {
        manager.addNode(type: type, at: location)
        nodeCounter += 1
        
        // Auto-select the new node
        if let newNode = manager.activeScenario?.nodes.last {
            selectedCanvasNode = newNode
        }
    }
    
    private func clearCanvas() {
        guard let scenario = manager.activeScenario else { return }
        scenario.nodes.removeAll()
        scenario.connections.removeAll()
        selectedCanvasNode = nil
        nodeCounter = 0
    }
    
    // MARK: - Connection Helpers
    
    private func getOutgoingConnections(_ node: ScenarioNode) -> [ScenarioConnection] {
        return manager.activeScenario?.connections.filter { $0.sourceNodeId == node.id } ?? []
    }
    
    private func removeAllConnections(for node: ScenarioNode) {
        guard let scenario = manager.activeScenario else { return }
        scenario.connections.removeAll { $0.sourceNodeId == node.id || $0.targetNodeId == node.id }
    }
    
    private func duplicateNode(_ node: ScenarioNode) {
        let newPosition = CGPoint(x: node.position.x + 50, y: node.position.y + 50)
        let newNode = ScenarioNode(type: node.type, position: newPosition)
        newNode.name = "\(node.name) Copy"
        newNode.config = node.config
        manager.activeScenario?.nodes.append(newNode)
        selectedCanvasNode = newNode
    }
    
    private func cancelConnection() {
        connectionSourceNode = nil
        isAddingConnection = false
    }
    
    private func saveNodeSettings() {
        // Trigger UI update
        manager.objectWillChange.send()
        ScenarioManager.shared.addLog("💾 Settings saved for: \(selectedCanvasNode?.name ?? "Unknown")")
    }
    
    // MARK: - Variable Picker
    
    private func variablePicker(for text: Binding<String>) -> some View {
        Menu {
            Button("Timestamp") { text.wrappedValue.append("{{$timestamp}}") }
            Button("Input JSON") { text.wrappedValue.append("{{$result}}") }
            
            Divider()
            
            if let scenario = manager.activeScenario {
                ForEach(scenario.nodes) { node in
                    if node.id != selectedCanvasNode?.id {
                        Menu(node.name) {
                            Button("Full Result") { text.wrappedValue.append("{{$result.\(node.name)}}") }
                            Button("Specific Key...") { text.wrappedValue.append("{{$result.\(node.name).output}}") }
                        }
                    }
                }
            }
        } label: {
             Image(systemName: "curlybraces")
                .font(.system(size: 10))
                .foregroundColor(.blue)
                .padding(4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - New Settings Forms
    
    private func whatsappSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
             settingSection("Provider") {
                 Picker("", selection: .constant("meta")) {
                     Text("Meta Cloud API").tag("meta")
                 }
                 .pickerStyle(.menu)
             }
             settingField("Phone Number ID", placeholder: "123456789", text: Binding(get: { node.config.lineUserId }, set: { node.config.lineUserId = $0 }))
             settingSecureField("Access Token", placeholder: "EA...", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
             settingField("To Phone Number", placeholder: "15551234567", text: Binding(get: { node.config.lineGroupId }, set: { node.config.lineGroupId = $0 }))
             settingSection("Message") {
                 TextEditor(text: Binding(get: { node.config.lineMessage }, set: { node.config.lineMessage = $0 }))
                    .font(.system(size: 11))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
             }
        }
    }
    
    private func slackSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
             settingSecureField("Bot Token", placeholder: "xoxb-...", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
             settingField("Channel ID", placeholder: "C12345678", text: Binding(get: { node.config.lineGroupId }, set: { node.config.lineGroupId = $0 }))
             settingSection("Message") {
                 TextEditor(text: Binding(get: { node.config.lineMessage }, set: { node.config.lineMessage = $0 }))
                    .font(.system(size: 11))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
             }
        }
    }
    
    private func discordSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
             settingSecureField("Bot Token", placeholder: "MTA...", text: Binding(get: { node.config.lineChannelToken }, set: { node.config.lineChannelToken = $0 }))
             settingField("Channel ID", placeholder: "123456789...", text: Binding(get: { node.config.lineGroupId }, set: { node.config.lineGroupId = $0 }))
             settingSection("Message") {
                 TextEditor(text: Binding(get: { node.config.lineMessage }, set: { node.config.lineMessage = $0 }))
                    .font(.system(size: 11))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
             }
        }
    }
    
    private func containerSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Executes a task in an isolated container environment.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            settingField("Command", placeholder: "echo 'Hello'", text: Binding(get: { node.config.codeContent }, set: { node.config.codeContent = $0 }))
            settingField("Image", placeholder: "ubuntu:latest", text: Binding(get: { node.config.codeLanguage }, set: { node.config.codeLanguage = $0 }))
        }
    }

    private func databaseSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            settingSection("Database Config") {
                Picker("Type", selection: Binding(get: { node.config.dbType }, set: { node.config.dbType = $0 })) {
                    Text("SQLite").tag("sqlite")
                    Text("PostgreSQL").tag("postgres")
                    Text("MySQL").tag("mysql")
                }
                .pickerStyle(.segmented)
            }
            
            settingField("Connection String", placeholder: "postgres://user:pass@localhost:5432/db", text: Binding(get: { node.config.dbConnection }, set: { node.config.dbConnection = $0 }))
            
            settingSection("Query") {
                TextEditor(text: Binding(get: { node.config.dbQuery }, set: { node.config.dbQuery = $0 }))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 100)
                    .padding(4)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.1), lineWidth: 1))
            }
        }
    }
    
    private func broadcastSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Broadcasts a message to all configured output channels.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            settingSection("Message") {
                TextEditor(text: Binding(get: { node.config.broadcastMessage }, set: { node.config.broadcastMessage = $0 }))
                    .font(.system(size: 13))
                    .frame(height: 100)
                    .padding(4)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }
    
    private func transformSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transform JSON data using expression.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            settingSection("Expression") {
                TextEditor(text: Binding(get: { node.config.transformExpression }, set: { node.config.transformExpression = $0 }))
                    .font(.system(size: 13, design: .monospaced))
                    .frame(height: 100)
                    .padding(4)
                    .background(Color.compat(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
            }
        }
    }
    
    private func filterSettings(_ node: ScenarioNode) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Continue flow only if condition is met.")
                .font(.caption)
                .foregroundColor(.secondary)
            
            settingField("Condition", placeholder: "data.success == true", text: Binding(get: { node.config.filterCondition }, set: { node.config.filterCondition = $0 }))
        }
    }
}

