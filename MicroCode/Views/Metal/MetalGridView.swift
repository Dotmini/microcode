import SwiftUI
import MetalKit

class GridRenderer: NSObject, MetalRenderer {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipelineState: MTLRenderPipelineState?
    
    var zoom: Float = 1.0
    var offset: simd_float2 = .init(0, 0)
    var gridSize: Float = 20.0
    
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
              let fragmentFunction = lib.makeFunction(name: "grid_fragment") else {
            print("❌ Metal error: Could not load grid shaders")
            return
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
        pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("❌ Metal error: Failed to create grid pipeline state: \(error)")
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
        
        var res = simd_float2(Float(view.drawableSize.width), Float(view.drawableSize.height))
        renderEncoder.setFragmentBytes(&res, length: MemoryLayout<simd_float2>.size, index: 0)
        renderEncoder.setFragmentBytes(&zoom, length: MemoryLayout<Float>.size, index: 1)
        renderEncoder.setFragmentBytes(&offset, length: MemoryLayout<simd_float2>.size, index: 2)
        renderEncoder.setFragmentBytes(&gridSize, length: MemoryLayout<Float>.size, index: 3)
        
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        commandBuffer.commit()
    }
}

struct MetalGridView: View {
    let zoom: CGFloat
    let offset: CGSize
    let gridSize: CGFloat
    
    @State private var renderer = GridRenderer()
    
    var body: some View {
        MetalView(renderer: renderer, isAnimated: false)
            .onChange(of: zoom) { renderer.zoom = Float($0) }
            .onChange(of: offset) { renderer.offset = simd_float2(Float($0.width), Float($0.height)) }
            .onChange(of: gridSize) { renderer.gridSize = Float($0) }
    }
}
