struct Frame {
    view_projection: mat4x4<f32>,
    eye: vec4<f32>,
};
@group(0) @binding(0) var<uniform> frame: Frame;
@group(0) @binding(1) var surface_texture: texture_2d<f32>;
@group(0) @binding(2) var surface_sampler: sampler;

struct VertexOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) tint: vec4<f32>,
    @location(3) world: vec3<f32>,
};

@vertex fn vertex_main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(5) color: vec3<f32>,
    @location(6) stretch: vec4<f32>,
) -> VertexOut {
    var out: VertexOut;
    let world = position * stretch.xyz * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    // Inverse-transpose of a diagonal scale: divide, then renormalize in the fragment stage.
    out.normal = normal / stretch.xyz;
    out.uv = uv;
    out.tint = tint * vec4<f32>(color, 1.0);
    out.world = world;
    return out;
}

@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    let sunlight = max(dot(normalize(in.normal), normalize(vec3<f32>(-0.4, 0.8, -0.3))), 0.0);
    let texel = textureSample(surface_texture, surface_sampler, in.uv).rgb;
    let color = in.tint.rgb * texel * (0.28 + sunlight * 0.85);
    let fog = clamp(distance(in.world, frame.eye.xyz) / 380.0, 0.0, 0.94);
    return vec4<f32>(mix(color, vec3<f32>(0.055, 0.10, 0.14), fog), 1.0);
}
