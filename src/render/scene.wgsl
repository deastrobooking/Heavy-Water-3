// Painterly cel shading: a soft two-step toon ramp under a warm key and a cool hemispheric
// fill, rim light, emissive lumen (instance tint alpha above 1), and height-aware haze tinted
// by the sky. Mach's WGSL compiler lacks `cross` and `pow`, so both are written out.
struct Frame {
    view_projection: mat4x4<f32>,
    eye: vec4<f32>,
    light_direction: vec4<f32>,
    light_color: vec4<f32>,
    ambient_sky: vec4<f32>,
    ambient_ground: vec4<f32>,
    // rgb: haze color; a: night factor (0 day, 1 night).
    horizon: vec4<f32>,
    // Frustum planes (inward unit normal, distance) for per-instance culling.
    plane0: vec4<f32>,
    plane1: vec4<f32>,
    plane2: vec4<f32>,
    plane3: vec4<f32>,
    plane4: vec4<f32>,
    plane5: vec4<f32>,
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

fn cross3(a: vec3<f32>, b: vec3<f32>) -> vec3<f32> {
    return vec3<f32>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x);
}

fn rotate(q: vec4<f32>, v: vec3<f32>) -> vec3<f32> {
    let t = 2.0 * cross3(q.xyz, v);
    return v + q.w * t + cross3(q.xyz, t);
}

fn outside(p: vec4<f32>, c: vec3<f32>, r: f32) -> bool {
    return dot(p.xyz, c) + p.w < -r;
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
    // Instances that carry a bounding radius in stretch.w (scale workloads) are culled here, per
    // instance: every vertex collapses to one point behind the near plane, so nothing rasterizes.
    if (stretch.w > 0.0) {
        let c = translation_scale.xyz;
        let r = stretch.w * translation_scale.w;
        if (outside(frame.plane0, c, r) || outside(frame.plane1, c, r) || outside(frame.plane2, c, r) || outside(frame.plane3, c, r) || outside(frame.plane4, c, r) || outside(frame.plane5, c, r)) {
            out.clip = vec4<f32>(0.0, 0.0, -1.0, 1.0);
            out.normal = vec3<f32>(0.0, 1.0, 0.0);
            out.uv = vec2<f32>(0.0, 0.0);
            out.tint = vec4<f32>(0.0, 0.0, 0.0, 1.0);
            out.world = c;
            return out;
        }
    }
    let world = rotate(rotation, position * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    // Inverse-transpose of a diagonal scale: divide, then renormalize in the fragment stage.
    out.normal = rotate(rotation, normal / stretch.xyz);
    out.uv = uv;
    out.tint = vec4<f32>(tint.rgb * color, tint.a);
    out.world = world;
    return out;
}

@fragment fn frag_main(in: VertexOut) -> @location(0) vec4<f32> {
    let texel = textureSample(surface_texture, surface_sampler, in.uv).rgb;
    let base = in.tint.rgb * mix(vec3<f32>(1.0, 1.0, 1.0), texel, 0.35);
    var color = base;
    var emissive = 0.0;
    // Negative tint alpha selects unlit shading without expanding the 64-byte instance record.
    // Keep this branch in the shared pipeline so material choice adds no draw or pipeline switch.
    if (in.tint.a >= 0.0) {
        let n = normalize(in.normal);
        let ndl = dot(n, frame.light_direction.xyz);
        // Two soft steps: shadow, half-lit, lit.
        let band = smoothstep(-0.04, 0.06, ndl) * 0.6 + smoothstep(0.42, 0.52, ndl) * 0.4;
        let hemi = n.y * 0.5 + 0.5;
        let ambient = mix(frame.ambient_ground.rgb, frame.ambient_sky.rgb, hemi);
        let view = normalize(frame.eye.xyz - in.world);
        let facing = 1.0 - max(dot(n, view), 0.0);
        let rim = facing * facing * facing * 0.45;
        color = base * (ambient + frame.light_color.rgb * band) + frame.light_color.rgb * rim * (0.25 + 0.75 * band);
        // Lumen: tint alpha above 1 glows, more so at night.
        emissive = clamp(in.tint.a - 1.0, 0.0, 1.0);
        let glow = base * (0.9 + 0.8 * frame.horizon.a);
        color = mix(color, glow, emissive);
    }

    // Height-aware haze: ground haze hides the streamed terrain's edge (~320 m), tall shapes
    // rise out of it, and everything picks up aerial tint with distance. Lumen resists haze.
    let d = distance(in.world, frame.eye.xyz);
    let ground = clamp((d - 40.0) / 340.0, 0.0, 1.0) * exp(-max(in.world.y, 0.0) / 90.0);
    let aerial = 1.0 - exp(-d / 2200.0);
    let fog = clamp(max(ground, aerial), 0.0, 0.95) * (1.0 - 0.6 * emissive);
    return vec4<f32>(mix(color, frame.horizon.rgb, fog), 1.0);
}
