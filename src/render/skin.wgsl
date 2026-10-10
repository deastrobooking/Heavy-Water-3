// Appended to scene.wgsl for the skinned-character pipeline (it uses Frame, VertexOut and
// rotate from there, and the same fragment entry point).
// GPU skinning for characters: each joint is a unit dual quaternion (real, dual), blended per
// vertex over four influences with antipodality kept to the first joint's hemisphere, matching
// the CPU `skinDualQuat`. One character's palette is selected by a dynamic uniform offset.
struct Palette {
    joints: array<vec4<f32>, 128>,
};
@group(1) @binding(0) var<uniform> palette: Palette;

fn quat_mul(a: vec4<f32>, b: vec4<f32>) -> vec4<f32> {
    return vec4<f32>(
        a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    );
}

@vertex fn vertex_skinned(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(5) color: vec3<f32>,
    @location(8) joints: vec4<u32>,
    @location(9) weights: vec4<f32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(6) stretch: vec4<f32>,
    @location(7) rotation: vec4<f32>,
) -> VertexOut {
    let pivot = palette.joints[joints.x * 2u];
    var real = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    var dual = vec4<f32>(0.0, 0.0, 0.0, 0.0);
    for (var k = 0u; k < 4u; k = k + 1u) {
        var w = weights[k];
        if (w != 0.0) {
            let r = palette.joints[joints[k] * 2u];
            let d = palette.joints[joints[k] * 2u + 1u];
            if (dot(r, pivot) < 0.0) {
                w = -w;
            }
            real = real + r * w;
            dual = dual + d * w;
        }
    }
    let len = length(real);
    if (len > 0.000001) {
        real = real / len;
        dual = dual / len;
    }
    // Translation = 2 * (dual * conjugate(real)).
    let t = quat_mul(dual, vec4<f32>(-real.xyz, real.w));
    let local = rotate(real, position) + 2.0 * t.xyz;
    let bent = rotate(real, normal);
    var out: VertexOut;
    let world = rotate(rotation, local * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    out.normal = rotate(rotation, bent / stretch.xyz);
    out.uv = vec2<f32>(0.0, 0.0);
    out.tint = vec4<f32>(tint.rgb * color, tint.a);
    out.world = world;
    return out;
}

