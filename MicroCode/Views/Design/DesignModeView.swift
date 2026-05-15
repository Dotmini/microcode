import SwiftUI

struct DesignModeView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var designStore = DesignStore()
    @State private var showAIPanel = false
    @State private var showLayers = true
    @State private var showInspector = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            DesignToolbar()
                .zIndex(1)
            
            Divider()
            
            GeometryReader { geometry in
                ZStack {
                    HStack(spacing: 0) {
                        // Left Layers Panel
                        if showLayers {
                            DesignLayersPanel()
                                .frame(width: 200)
                                .transition(.move(edge: .leading))
                            
                            Divider()
                        }
                        
                        // Main Canvas + Floating Toolbar
                        ZStack(alignment: .bottom) {
                            DesignCanvasView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            
                            // Floating Toolbar (Figma-style)
                            DesignFloatingToolbar()
                                .padding(.bottom, 16)
                        }
                        
                        Divider()
                        
                        // Right Inspector
                        if showInspector {
                            PropertiesInspector()
                                .frame(width: 260)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .transition(.move(edge: .trailing))
                        }
                    }
                    
                    // AI Design Panel (floating overlay)
                    if showAIPanel {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                AIDesignPanel()
                                    .padding(.trailing, showInspector ? 276 : 16)
                                    .padding(.bottom, 16)
                                    .transition(.asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .scale(scale: 0.9).combined(with: .opacity)
                                    ))
                            }
                        }
                        .zIndex(10)
                    }
                }
            }
            
            // Bottom Status Bar
            bottomBar
        }
        .environmentObject(designStore)
        .background(appState.appTheme == .transparent || appState.appTheme == .extraClear ? Color.clear : Color(nsColor: .windowBackgroundColor))
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                // AI Design Toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showAIPanel.toggle()
                    }
                }) {
                    Image(systemName: showAIPanel ? "wand.and.sparkles" : "wand.and.stars")
                        .foregroundColor(showAIPanel ? .purple : .secondary)
                }
                .help("AI Design")
                
                Divider()
                
                // Panel Toggles
                Button(action: { withAnimation { showLayers.toggle() } }) {
                    Image(systemName: "sidebar.leading")
                        .foregroundColor(showLayers ? .blue : .secondary)
                }
                .help("Layers Panel")
                
                Button(action: { withAnimation { showInspector.toggle() } }) {
                    Image(systemName: "sidebar.trailing")
                        .foregroundColor(showInspector ? .blue : .secondary)
                }
                .help("Inspector Panel")
            }
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 12) {
            // Zoom
            HStack(spacing: 6) {
                Button(action: { withAnimation { designStore.zoomLevel = max(0.25, designStore.zoomLevel - 0.1) } }) {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                
                Text("\(Int(designStore.zoomLevel * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .frame(width: 36)
                
                Button(action: { withAnimation { designStore.zoomLevel = min(4.0, designStore.zoomLevel + 0.1) } }) {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            
            Divider().frame(height: 12)
            
            // Element count
            if let page = designStore.activePage {
                Text("\(page.elements.count) elements")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            // Selection info
            if !designStore.selection.isEmpty {
                Text("• \(designStore.selection.count) selected")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            // AI Status
            if !AIDesignEngine.shared.status.isEmpty {
                Text(AIDesignEngine.shared.status)
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
            }
            
            // Framework badge
            Text(designStore.project.framework.rawValue)
                .font(.system(size: 9, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
    }
}
