// Painterly cel shading: a soft two-step toon ramp under a warm key and a cool hemispheric
// fill, rim light, emissive lumen (instance tint alpha above 1), and height-aware haze tinted
// by the sky. Mach's WGSL compiler lacks `cross`, `pow` and `reflect`, so they are written out.
//
// Everything before `vertex_main` is shared: the renderer splices other stages in place of
// `vertex_main` (skin.wgsl, foliage.wgsl) or of `frag_main` (terrain.wgsl, water.wgsl), since
// Mach takes one entry point of each stage per module.
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
    // x: seconds (wraps), y: wind strength, zw: wind direction on the ground plane.
    params: vec4<f32>,
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

// World positions run to thousands of metres; hashing them directly loses float precision on
// the GPU, so patterns wrap every 1024 m (seams fall on whole cells and are invisible).
fn wrap(p: vec2<f32>) -> vec2<f32> {
    return p - floor(p / 1024.0) * 1024.0;
}

// `reflect` is not implemented in Mach's WGSL compiler.
fn reflected(i: vec3<f32>, n: vec3<f32>) -> vec3<f32> {
    return i - 2.0 * dot(n, i) * n;
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

// Smooth value noise in [0, 1].
fn vnoise(q: vec2<f32>) -> f32 {
    let p = wrap(q);
    let i = floor(p);
    let f = p - i;
    let u = f * f * (vec2<f32>(3.0, 3.0) - 2.0 * f);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// The cel ramp: two soft steps (shadow, half-lit, lit) of the key light.
fn band(n: vec3<f32>) -> f32 {
    let ndl = dot(n, frame.light_direction.xyz);
    return smoothstep(-0.04, 0.06, ndl) * 0.6 + smoothstep(0.42, 0.52, ndl) * 0.4;
}

// Toon key, hemispheric fill and rim light on a base colour.
fn lit(base: vec3<f32>, n: vec3<f32>, world: vec3<f32>) -> vec3<f32> {
    let b = band(n);
    let hemi = n.y * 0.5 + 0.5;
    let ambient = mix(frame.ambient_ground.rgb, frame.ambient_sky.rgb, hemi);
    let view = normalize(frame.eye.xyz - world);
    let facing = 1.0 - max(dot(n, view), 0.0);
    let rim = facing * facing * facing * 0.45;
    return base * (ambient + frame.light_color.rgb * b) + frame.light_color.rgb * rim * (0.25 + 0.75 * b);
}

// Height-aware haze: ground haze hides the streamed terrain's edge (~320 m), tall shapes
// rise out of it, and everything picks up aerial tint with distance. Lumen resists haze.
fn hazed(color: vec3<f32>, world: vec3<f32>, emissive: f32) -> vec3<f32> {
    let d = distance(world, frame.eye.xyz);
    let ground = clamp((d - 40.0) / 340.0, 0.0, 1.0) * exp(-max(world.y, 0.0) / 90.0);
    let aerial = 1.0 - exp(-d / 2200.0);
    let fog = clamp(max(ground, aerial), 0.0, 0.95) * (1.0 - 0.6 * emissive);
    return mix(color, frame.horizon.rgb, fog);
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
    // Negative UV sentinels reserve procedural materials without changing the vertex layout.
    let tag = select(0.0, floor(-in.uv.x + 0.5), in.uv.x < -9.5);
    let canopy = step(10.0, tag) * (1.0 - step(20.0, tag));
    let bark = step(20.0, tag);
    // Antarctica props opt into a world-space triplanar glacier material through tint alpha
    // -2. Sampling in world coordinates keeps long ice walls from stretching a single tile.
    let ice_tag = in.tint.a < -1.5 && in.tint.a > -2.5;
    var base = in.tint.rgb;
    if (ice_tag) {
        let normal_weights_raw = abs(normalize(in.normal));
        let normal_weights = normal_weights_raw / max(normal_weights_raw.x + normal_weights_raw.y + normal_weights_raw.z, 0.001);
        let ice_x = textureSample(surface_texture, surface_sampler, wrap(in.world.zy / 256.0)).rgb;
        let ice_y = textureSample(surface_texture, surface_sampler, wrap(in.world.xz / 256.0)).rgb;
        let ice_z = textureSample(surface_texture, surface_sampler, wrap(in.world.xy / 256.0)).rgb;
        let glacier = ice_x * normal_weights.x + ice_y * normal_weights.y + ice_z * normal_weights.z;
        base = in.tint.rgb * mix(vec3<f32>(0.54, 0.74, 0.92), glacier, 0.9);
    }
    let d = distance(in.world, frame.eye.xyz);
    let detail = 1.0 - smoothstep(150.0, 720.0, d);

    // Species-tagged canopy surfaces get layered leaf breakup at metre and branch scales.
    // Keeping it in world space lets giant crowns read as foliage without thousands of leaves.
    let crown_broad = vnoise(vec2<f32>(in.world.x * 0.045 + in.world.y * 0.017, in.world.z * 0.045 - in.world.y * 0.021));
    let crown_cluster = vnoise(vec2<f32>(in.world.x * 0.43 + in.world.y * 0.16, in.world.z * 0.43 - in.world.y * 0.11));
    let crown_fine = vnoise(vec2<f32>(in.world.x * 2.2 + in.world.y * 0.74, in.world.z * 2.2 - in.world.y * 0.61));
    let crown_mottle = ((crown_broad - 0.5) * 0.28 + (crown_cluster - 0.5) * 0.25 + (crown_fine - 0.5) * 0.12) * detail;
    let pine = step(16.5, tag) * (1.0 - step(20.0, tag));
    let needle_sheen = smoothstep(0.70, 0.91, crown_fine) * detail * pine;
    let leaf_base = in.tint.rgb * (1.0 + crown_mottle + needle_sheen * 0.22);

    // Mature bark gets long grain, shallow fissures, lichen flecks, and a warmer sunward
    // variation. The pattern follows the trunk in world space and fades before distant shimmer.
    let bark_axis = dot(in.world.xz, vec2<f32>(0.93, 0.37));
    let bark_broad = vnoise(vec2<f32>(bark_axis * 0.045, in.world.y * 0.012));
    let bark_grain = vnoise(vec2<f32>(bark_axis * 0.62, in.world.y * 0.075 + bark_broad * 1.8));
    let bark_fine = vnoise(vec2<f32>(bark_axis * 2.7, in.world.y * 0.19 + bark_grain));
    let fissure = smoothstep(0.61, 0.78, bark_grain) * (1.0 - smoothstep(0.12, 0.48, bark_fine));
    let lichen = smoothstep(0.76, 0.92, vnoise(in.world.xz * 0.31 + vec2<f32>(in.world.y * 0.04, -in.world.y * 0.03))) * detail;
    let bark_gain = 0.72 + bark_broad * 0.34 + bark_fine * 0.22 - fissure * 0.28;
    let bark_base = in.tint.rgb * bark_gain + vec3<f32>(0.075, 0.105, 0.052) * lichen * 0.48;
    base = mix(base, leaf_base, canopy);
    base = mix(base, bark_base, bark);
    var color = base;
    var emissive = 0.0;
    // Negative tint alpha selects unlit shading without expanding the 64-byte instance record.
    // Keep this branch in the shared pipeline so material choice adds no draw or pipeline switch.
    if (in.tint.a >= 0.0 || ice_tag) {
        color = lit(base, normalize(in.normal), in.world);
        if (ice_tag) {
            let view = normalize(frame.eye.xyz - in.world);
            let mirror = reflected(view * -1.0, normalize(in.normal));
            let sheen = smoothstep(0.89, 0.99, dot(mirror, frame.light_direction.xyz));
            let facing = 1.0 - max(dot(normalize(in.normal), view), 0.0);
            color = color + frame.light_color.rgb * sheen * sheen * 0.58 + vec3<f32>(0.10, 0.34, 0.62) * facing * facing * 0.16;
        }
        // Lumen: tint alpha above 1 glows, more so at night.
        emissive = clamp(in.tint.a - 1.0, 0.0, 1.0);
        // Living-sap meshes use a dedicated alpha tag. Keep their separate glow geometry
        // subdued by day, then let the existing lumen blend bring it forward at night.
        if (in.tint.a > 2.25) {
            emissive = frame.horizon.a * 0.92;
        }
        let glow = base * (0.9 + 0.8 * frame.horizon.a);
        color = mix(color, glow, emissive);
    }
    return vec4<f32>(hazed(color, in.world, emissive), 1.0);
}
