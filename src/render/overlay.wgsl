@group(0) @binding(0) var font_atlas: texture_2d<f32>;
@group(0) @binding(1) var font_sampler: sampler;
struct Out { @builtin(position) position: vec4<f32>, @location(0) color: vec4<f32>, @location(1) uv: vec2<f32> };
@vertex fn vertex_main(@location(0) position: vec2<f32>, @location(1) color: vec4<f32>, @location(2) uv: vec2<f32>) -> Out {
    var out: Out;
    out.position = vec4<f32>(position, 0.0, 1.0);
    out.color = color;
    out.uv = uv;
    return out;
}
@fragment fn frag_main(in: Out) -> @location(0) vec4<f32> {
    var alpha = 1.0;
    if (in.uv.x >= 0.0) { alpha = textureSample(font_atlas, font_sampler, in.uv).a; }
    return vec4<f32>(in.color.rgb, in.color.a * alpha);
}
