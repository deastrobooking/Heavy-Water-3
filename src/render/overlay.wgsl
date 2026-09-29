struct Out { @builtin(position) position: vec4<f32>, @location(0) color: vec4<f32> };
@vertex fn vertex_main(@location(0) position: vec2<f32>, @location(1) color: vec4<f32>) -> Out {
    var out: Out;
    out.position = vec4<f32>(position, 0.0, 1.0);
    out.color = color;
    return out;
}
@fragment fn frag_main(in: Out) -> @location(0) vec4<f32> { return in.color; }
