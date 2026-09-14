//
//  DeviceMetalRenderer.swift
//  MicroCode
//
//  Zero-copy Metal rendering pipeline for device video frames.
//  Converts NV12 (YpCbCr BiPlanar) CVPixelBuffer from VideoToolbox
//  or AVFoundation directly to sRGB via a Metal fragment shader,
//  with no CPU memory copies in the critical path.
//

import Foundation
import Metal
import MetalKit
import CoreVideo
import AppKit

final class DeviceMetalRenderer {

    // MARK: - Public

    /// The CAMetalLayer to render into. Set by the hosting NSView.
    weak var metalLayer: CAMetalLayer? {
        didSet { configureLayer() }
    }

    /// The most recent frame's pixel dimensions.
    private(set) var frameWidth: Int = 0
    private(set) var frameHeight: Int = 0

    /// Measured rendering FPS.
    private(set) var renderFPS: Double = 0

    // MARK: - Metal State

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?

    // Triple buffering
    private let inflightSemaphore = DispatchSemaphore(value: 3)

    // Vertex buffer (fullscreen quad)
    private let vertexBuffer: MTLBuffer

    // FPS measurement
    private var fpsFrameCount = 0
    private var fpsLastTime = CACurrentMediaTime()

    // MARK: - Init

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("[MetalRenderer] No Metal device available")
            return nil
        }
        self.device = device
        self.commandQueue = queue

        // Create texture cache for zero-copy CVPixelBuffer → MTLTexture
        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard cacheStatus == kCVReturnSuccess, let textureCache = cache else {
            print("[MetalRenderer] Failed to create texture cache")
            return nil
        }
        self.textureCache = textureCache

        // Create fullscreen quad vertices
        // Position (x, y) + TexCoord (u, v)
        let vertices: [Float] = [
            -1.0, -1.0,  0.0, 1.0,  // bottom-left
             1.0, -1.0,  1.0, 1.0,  // bottom-right
            -1.0,  1.0,  0.0, 0.0,  // top-left
             1.0,  1.0,  1.0, 0.0,  // top-right
        ]
        guard let vb = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride,
            options: .storageModeShared
        ) else {
            print("[MetalRenderer] Failed to create vertex buffer")
            return nil
        }
        self.vertexBuffer = vb

        // Build render pipeline
        // First, try to load from the default library (compiled .metal files)
        let library: MTLLibrary
        if let defaultLib = device.makeDefaultLibrary() {
            library = defaultLib
        } else {
            // Fallback: compile from source string
            let shaderSource = DeviceMetalRenderer.fallbackShaderSource
            do {
                library = try device.makeLibrary(source: shaderSource, options: nil)
            } catch {
                print("[MetalRenderer] Failed to compile shaders: \(error)")
                return nil
            }
        }

        guard let vertexFunc = library.makeFunction(name: "deviceVideoVertex"),
              let fragmentFunc = library.makeFunction(name: "deviceVideoFragment") else {
            print("[MetalRenderer] Shader functions not found")
            return nil
        }

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunc
        pipelineDescriptor.fragmentFunction = fragmentFunc
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[MetalRenderer] Failed to create pipeline state: \(error)")
            return nil
        }
    }

    // MARK: - Layer Configuration

    private func configureLayer() {
        guard let layer = metalLayer else { return }
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.displaySyncEnabled = false // Lowest latency
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
    }

    // MARK: - Render Frame

    /// Render a CVPixelBuffer (NV12 format) to the Metal layer.
    /// This is the hot path — zero CPU copies.
    func renderFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let layer = metalLayer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        frameWidth = width
        frameHeight = height

        // Create Metal textures from CVPixelBuffer planes (zero-copy via IOSurface)
        guard let textureY = createTexture(from: pixelBuffer, plane: 0, format: .r8Unorm),
              let textureCbCr = createTexture(from: pixelBuffer, plane: 1, format: .rg8Unorm) else {
            return
        }

        // Triple buffering (50ms timeout protects against GPU stalls/dropped frames)
        guard inflightSemaphore.wait(timeout: .now() + 0.05) == .success else {
            return
        }

        guard let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            inflightSemaphore.signal()
            return
        }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(textureY, index: 0)
        encoder.setFragmentTexture(textureCbCr, index: 1)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)

        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }

        commandBuffer.commit()

        // FPS tracking
        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        let elapsed = now - fpsLastTime
        if elapsed >= 1.0 {
            renderFPS = Double(fpsFrameCount) / elapsed
            fpsFrameCount = 0
            fpsLastTime = now
        }
    }

    /// Render a BGRA CVPixelBuffer (from AVFoundation iOS capture) to Metal.
    func renderBGRAFrame(_ pixelBuffer: CVPixelBuffer) {
        guard let layer = metalLayer else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        frameWidth = width
        frameHeight = height

        guard let texture = createTexture(
            from: pixelBuffer,
            plane: 0,
            format: .bgra8Unorm,
            width: width,
            height: height
        ) else { return }

        // Triple buffering (50ms timeout protects against GPU stalls/dropped frames)
        guard inflightSemaphore.wait(timeout: .now() + 0.05) == .success else {
            return
        }

        guard let drawable = layer.nextDrawable(),
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            inflightSemaphore.signal()
            return
        }

        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .dontCare
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            inflightSemaphore.signal()
            return
        }

        let sourceSize = MTLSize(width: min(width, drawable.texture.width),
                                  height: min(height, drawable.texture.height),
                                  depth: 1)
        blitEncoder.copy(from: texture,
                         sourceSlice: 0,
                         sourceLevel: 0,
                         sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                         sourceSize: sourceSize,
                         to: drawable.texture,
                         destinationSlice: 0,
                         destinationLevel: 0,
                         destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blitEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inflightSemaphore.signal()
        }
        commandBuffer.commit()

        fpsFrameCount += 1
        let now = CACurrentMediaTime()
        if now - fpsLastTime >= 1.0 {
            renderFPS = Double(fpsFrameCount) / (now - fpsLastTime)
            fpsFrameCount = 0
            fpsLastTime = now
        }
    }

    // MARK: - Texture Creation (Zero-Copy)

    private func createTexture(
        from pixelBuffer: CVPixelBuffer,
        plane: Int,
        format: MTLPixelFormat,
        width: Int? = nil,
        height: Int? = nil
    ) -> MTLTexture? {
        guard let cache = textureCache else { return nil }

        let planeWidth = width ?? CVPixelBufferGetWidthOfPlane(pixelBuffer, plane)
        let planeHeight = height ?? CVPixelBufferGetHeightOfPlane(pixelBuffer, plane)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            format,
            planeWidth,
            planeHeight,
            plane,
            &cvTexture
        )

        guard status == kCVReturnSuccess, let cvTex = cvTexture else {
            return nil
        }

        return CVMetalTextureGetTexture(cvTex)
    }

    // MARK: - Fallback Shader Source

    /// Inline shader source used when .metal file is not compiled into the default library.
    static let fallbackShaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    vertex VertexOut deviceVideoVertex(
        uint vertexID [[vertex_id]],
        const device float4* vertices [[buffer(0)]]
    ) {
        VertexOut out;
        float4 v = vertices[vertexID];
        out.position = float4(v.x, v.y, 0.0, 1.0);
        out.texCoord = float2(v.z, v.w);
        return out;
    }

    fragment float4 deviceVideoFragment(
        VertexOut in [[stage_in]],
        texture2d<float> textureY [[texture(0)]],
        texture2d<float> textureCbCr [[texture(1)]]
    ) {
        constexpr sampler s(address::clamp_to_edge, filter::linear);

        float y = textureY.sample(s, in.texCoord).r;
        float2 uv = textureCbCr.sample(s, in.texCoord).rg - float2(0.5, 0.5);

        // BT.709 YCbCr → RGB conversion matrix (video range)
        float r = y + 1.5748 * uv.y;
        float g = y - 0.1873 * uv.x - 0.4681 * uv.y;
        float b = y + 1.8556 * uv.x;

        return float4(r, g, b, 1.0);
    }
    """
}
