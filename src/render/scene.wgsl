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

// Mach's WGSL compiler does not implement the `cross` builtin yet.
fn cross3(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

fn rotate(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    let t = 2.0 * cross3(q.xyz, v);
    return v + q.w * t + cross3(q.xyz, t);
}

@vertex fn vertex_main(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(5) color: vec3<f32>,
    @location(6) stretch: vec4<f32>,
    @location(7) rotation: vec4<f32>,
) -> VertexOut {
    var out: VertexOut;
    let world = rotate(rotation, position * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    // Inverse-transpose of a diagonal scale: divide, then renormalize in the fragment stage.
    out.normal = rotate(rotation, normal / stretch.xyz);
    out.uv = uv;
    out.tint = tint * vec4<f32>(color, 1.0);
    out.world = world;
    return out;
}

@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    let sunlight = max(dot(normalize(in.normal), normalize(vec3<f32>(-0.4, 0.8, -0.3))), 0.0);
    let texel = textureSample(surface_texture, surface_sampler, in.uv).rgb;
    let color = in.tint.rgb * texel * (0.28 + sunlight * 0.85);
    // Height-aware haze: ground haze hides the streamed terrain's edge (~320 m), tall shapes
    // rise out of it, and everything picks up aerial tint with distance.
    let d = distance(in.world, frame.eye.xyz);
    let ground = clamp((d - 40.0) / 340.0, 0.0, 1.0) * exp(-max(in.world.y, 0.0) / 90.0);
    let aerial = 1.0 - exp(-d / 2200.0);
    let fog = clamp(max(ground, aerial), 0.0, 0.95);
    return vec4<f32>(mix(color, vec3<f32>(0.055, 0.10, 0.14), fog), 1.0);
}
