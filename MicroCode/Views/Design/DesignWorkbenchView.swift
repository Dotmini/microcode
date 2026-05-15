import SwiftUI

struct DesignWorkbenchView: View {
    @StateObject var designStore = DesignStore()
    @State private var showingLayers = true
    @State private var showingInspector = true
    
    var body: some View {
        HStack(spacing: 0) {
            // 1. LEFT: Navigator (Layers & Assets)
            if showingLayers {
                DesignNavigatorSidebar(designStore: designStore)
                    .frame(width: 260)
                    .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    .border(Color(nsColor: .separatorColor), width: 0.5)
            }
            
            // 2. CENTER: Infinite Canvas
            ZStack(alignment: .bottom) {
                DesignCanvasView() // We will refactor this next
                    .environmentObject(designStore)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor)) // Infinite gray canvas
                
                // 3. Floating Toolbar (Capsule Style)
                DesignFloatingToolbar()
                    .padding(.bottom, 20)
            }
            
            // 4. RIGHT: Inspector (Properties)
            if showingInspector {
                DesignInspectorSidebar(designStore: designStore)
                    .frame(width: 280)
                    .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
                    .border(Color(nsColor: .separatorColor), width: 0.5)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { withAnimation { showingLayers.toggle() } }) {
                    Image(systemName: "sidebar.left")
                }
                Spacer()
                // Zoom Controls
                Button(action: { designStore.zoomLevel -= 0.1 }) { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int(designStore.zoomLevel * 100))%")
                    .font(.footnote).monospacedDigit()
                    .frame(width: 40)
                Button(action: { designStore.zoomLevel += 0.1 }) { Image(systemName: "plus.magnifyingglass") }
                
                Spacer()
                Button(action: { withAnimation { showingInspector.toggle() } }) {
                    Image(systemName: "sidebar.right")
                }
            }
        }
        .environmentObject(designStore)
    }
}

// VisualEffectView is likely defined globally or in another file. Using existing one.
// If not, we might need a unique name, but let's try relying on existing.
