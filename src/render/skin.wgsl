// Shared by the skinned-character modules (skin_lit.wgsl, skin_hull.wgsl), spliced after the
// scene.wgsl prelude (Frame, VertexOut, rotate, hazed). Entry points live in those files because
// Mach takes one per stage per module.
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

// Per-material cel style, laid out by character/CelStyle.zig `pack`: two header vec4s, then six
// vec4s per material.
struct CelTable {
    v: array<vec4<f32>, 104>,
};
@group(1) @binding(1) var<uniform> cel: CelTable;

struct Skinned {
    local: vec3<f32>,
    bent: vec3<f32>,
    real: vec4<f32>,
};

fn skin_blend(joints: vec4<u32>, weights: vec4<f32>, position: vec3<f32>, normal: vec3<f32>) -> Skinned {
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
    // Mach's WGSL compiler cannot negate a swizzle; conjugate by a sign multiply instead.
    let t = quat_mul(dual, real * vec4<f32>(-1.0, -1.0, -1.0, 1.0));
    var out: Skinned;
    out.local = rotate(real, position) + 2.0 * t.xyz;
    out.bent = rotate(real, normal);
    out.real = real;
    return out;
}
