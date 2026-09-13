//
//  DeviceMetalShaders.metal
//  MicroCode
//
//  Metal shaders for real-time device screen mirroring.
//  Converts NV12 (YpCbCr BiPlanar) video frames to sRGB
//  using BT.709 color matrix for accurate device screen colors.
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Vertex Data

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// MARK: - Vertex Shader

/// Fullscreen quad pass-through vertex shader.
/// Input vertices: (x, y, u, v) packed as float4.
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

// MARK: - Fragment Shader (NV12 → sRGB)

/// Converts NV12 (Y plane + interleaved CbCr plane) to sRGB.
/// Uses BT.709 color conversion matrix (standard for HD/mobile screens).
///
/// The two textures correspond to the two planes of a BiPlanar pixel buffer:
///   texture(0) = Luma (Y) plane, format r8Unorm
///   texture(1) = Chroma (CbCr) plane, format rg8Unorm
fragment float4 deviceVideoFragment(
    VertexOut in [[stage_in]],
    texture2d<float> textureY [[texture(0)]],
    texture2d<float> textureCbCr [[texture(1)]]
) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);

    // Sample Y (luma) and CbCr (chroma) from their respective planes
    float y = textureY.sample(s, in.texCoord).r;
    float2 cbcr = textureCbCr.sample(s, in.texCoord).rg;

    // Offset chroma from [0, 1] to [-0.5, 0.5]
    float cb = cbcr.x - 0.5;
    float cr = cbcr.y - 0.5;

    // BT.709 video range (16-235 luma, 16-240 chroma) to full range
    // Scale Y from [16/255, 235/255] → [0, 1]
    // Scale CbCr from [16/255, 240/255] → [-0.5, 0.5]
    float yScaled = (y - 0.0627) * 1.1644;

    // BT.709 conversion coefficients
    float r = yScaled + 1.7928 * cr;
    float g = yScaled - 0.2132 * cb - 0.5329 * cr;
    float b = yScaled + 2.1124 * cb;

    return float4(saturate(r), saturate(g), saturate(b), 1.0);
}
