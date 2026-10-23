import SwiftUI
import MetalKit

/// Shared Apple Silicon Unified Memory Architecture (UMA) Metal context.
/// Shares a single MTLDevice, MTLCommandQueue, and compiled MTLLibrary across all Metal views
/// so shaders are compiled once and zero duplicate command queues are allocated.
enum SharedUMAMetalContext {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()
    static let commandQueue: MTLCommandQueue? = device?.makeCommandQueue()

    static let library: MTLLibrary? = {
        guard let device = device else { return nil }
        if let defaultLib = device.makeDefaultLibrary() {
            return defaultLib
        }
        if let path = Bundle.main.path(forResource: "default", ofType: "metallib"),
           let lib = try? device.makeLibrary(filepath: path) {
            return lib
        }
        return try? device.makeLibrary(source: embeddedShaderSource, options: nil)
    }()

    private static let embeddedShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
    };

    vertex VertexOut vertex_main(uint vertexID [[vertex_id]]) {
        float2 positions[4] = {
            float2(-1.0, -1.0),
            float2( 1.0, -1.0),
            float2(-1.0,  1.0),
            float2( 1.0,  1.0)
        };
        VertexOut out;
        out.position = float4(positions[vertexID], 0.0, 1.0);
        out.uv = positions[vertexID] * 0.5 + 0.5;
        return out;
    }

    fragment float4 grid_fragment(
        VertexOut in [[stage_in]],
        constant float2 &resolution [[buffer(0)]],
        constant float &zoom [[buffer(1)]],
        constant float2 &offset [[buffer(2)]],
        constant float &gridSize [[buffer(3)]]
    ) {
        float2 pixel = in.uv * resolution - offset;
        float stepSize = max(4.0, gridSize * zoom);
        float2 grid = abs(fract(pixel / stepSize - 0.5) - 0.5) / fwidth(pixel / stepSize);
        float line = min(grid.x, grid.y);
        float alpha = (1.0 - min(line, 1.0)) * 0.14;
        return float4(0.55, 0.62, 0.75, alpha);
    }

    fragment float4 background_fragment(
        VertexOut in [[stage_in]],
        constant float &time [[buffer(0)]],
        constant float2 &resolution [[buffer(1)]]
    ) {
        float2 uv = in.uv;
        float wave = sin(uv.x * 6.0 + time * 0.5) * cos(uv.y * 6.0 - time * 0.3) * 0.04;
        float3 base = float3(0.05, 0.06, 0.09) + wave;
        return float4(base, 1.0);
    }
    """
}

struct MetalView: NSViewRepresentable {
    let renderer: MetalRenderer
    var preferredFramesPerSecond: Int = 60
    var isAnimated: Bool = true
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = SharedUMAMetalContext.device
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
