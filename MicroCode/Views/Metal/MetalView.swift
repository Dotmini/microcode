import SwiftUI
import MetalKit

struct MetalView: NSViewRepresentable {
    let renderer: MetalRenderer
    var preferredFramesPerSecond: Int = 60
    var isAnimated: Bool = true
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = renderer
        
        // Optimization: Control when the view draws
        mtkView.isPaused = !isAnimated
        mtkView.enableSetNeedsDisplay = !isAnimated
        mtkView.preferredFramesPerSecond = preferredFramesPerSecond
        
        mtkView.framebufferOnly = true
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.layer?.isOpaque = false
        
        // Finalize setup with the specific device and format
        if let device = mtkView.device {
            renderer.setup(device: device)
        }
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Sync properties that might change
        if nsView.isPaused != (!isAnimated) {
            nsView.isPaused = !isAnimated
            nsView.enableSetNeedsDisplay = !isAnimated
        }
        
        if nsView.preferredFramesPerSecond != preferredFramesPerSecond {
            nsView.preferredFramesPerSecond = preferredFramesPerSecond
        }
    }
}

protocol MetalRenderer: MTKViewDelegate {
    func setup(device: MTLDevice)
}
