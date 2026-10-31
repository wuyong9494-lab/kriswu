import Foundation

/// Authored shader code ships with the App; the private pack contains only
/// declarative geometry, clocks and images. No shader source comes from a pack.
enum ArenaLobbyTimelineShaders {
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct LobbyVertex {
        float2 position;
        float2 uv;
        float4 multiply;
        float4 add;
    };
    struct LobbyVertexOut {
        float4 position [[position]];
        float2 uv;
        float2 sourcePoint;
        float4 multiply;
        float4 add;
    };

    vertex LobbyVertexOut arenaLobbyVertex(
        uint vertexID [[vertex_id]],
        constant LobbyVertex *vertices [[buffer(0)]],
        constant float4 &viewport [[buffer(1)]]) {
        LobbyVertex value = vertices[vertexID];
        float2 normalized = (value.position - viewport.xy) / viewport.zw;
        LobbyVertexOut result;
        result.position = float4(normalized.x * 2.0 - 1.0, 1.0 - normalized.y * 2.0, 0.0, 1.0);
        result.uv = value.uv;
        result.sourcePoint = value.position;
        result.multiply = value.multiply;
        result.add = value.add;
        return result;
    }

    fragment float4 arenaLobbyFragment(
        LobbyVertexOut value [[stage_in]],
        texture2d<float, access::read> source [[texture(0)]],
        texture2d<float, access::read> mask [[texture(1)]],
        constant float4 &settings [[buffer(0)]],
        constant float4 &maskRect [[buffer(1)]]) {
        float2 size = float2(source.get_width(), source.get_height());
        // Authored SC UVs use the same nearest-pixel convention as the checked
        // face sampler. Render-target quads use pixel-center sampling instead.
        float rounding = settings.x > 0.5 ? 0.0 : 0.5;
        float2 at = clamp(floor(value.uv * size + rounding), float2(0.0), size - 1.0);
        float4 pixel = source.read(uint2(at));
        if (pixel.a <= 0.0) return float4(0.0);
        float alpha = pixel.a * value.multiply.a;
        float3 straight = pixel.rgb / pixel.a;
        float3 rgb = clamp(straight * value.multiply.rgb + value.add.rgb, 0.0, 1.0);
        float4 output = float4(rgb * alpha, alpha);
        if (settings.y > 0.5) {
            float2 relative = (value.sourcePoint - maskRect.xy) / maskRect.zw;
            if (any(relative < 0.0) || any(relative >= 1.0)) return float4(0.0);
            uint2 maskSize = uint2(mask.get_width(), mask.get_height());
            uint2 coordinate = min(uint2(floor(relative * float2(maskSize))), maskSize - 1);
            // Continuous alpha, not a binary stencil approximation. Both RGB
            // and alpha are multiplied to preserve premultiplied arithmetic.
            output *= mask.read(coordinate).a;
        }
        return output;
    }
    """#
}
