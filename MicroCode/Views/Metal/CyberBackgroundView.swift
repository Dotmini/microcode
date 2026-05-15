import SwiftUI
import MetalKit

class CyberBackgroundRenderer: NSObject, MetalRenderer {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    private var startTime: Date = Date()
    
    func setup(device: MTLDevice) {
        if self.pipelineState != nil { return } // Already setup
        
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        
        // Robust library loading
        let library: MTLLibrary?
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            // Fallback for cases where default library isn't automatically found (e.g. SPM)
            let bundle = Bundle(for: Self.self)
            if let path = bundle.path(forResource: "default", ofType: "metallib") {
                library = try? device.makeLibrary(filepath: path)
            } else {
                library = nil
            }
        }
        
        guard let lib = library,
              let vertexFunction = lib.makeFunction(name: "vertex_main"),
              let fragmentFunction = lib.makeFunction(name: "background_fragment") else {
            print("❌ Metal error: Could not load background shaders")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Metal error: Failed to create background pipeline state: \(error)")
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let device = device,
              let commandQueue = commandQueue,
              let pipelineState = pipelineState,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        var time = Float(Date().timeIntervalSince(startTime))
        renderEncoder.setFragmentBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        
        var resolution = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        renderEncoder.setFragmentBytes(&resolution, length: MemoryLayout<simd_float2>.size, index: 1)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}

struct CyberBackgroundView: View {
    @State private var renderer = CyberBackgroundRenderer()
    
    var body: some View {
        MetalView(renderer: renderer, preferredFramesPerSecond: 15)
            .ignoresSafeArea()
    }
}
