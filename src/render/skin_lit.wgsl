// Appended to scene.wgsl prelude + skin.wgsl: the lit character stage. Per-material cel ramps
// from the CelTable (see character/CelStyle.zig, toon.shadeCel is the CPU reference), the face
// shadow map on the face, a hard specular band, rim light, emissive strips, and ramp debug.
struct SkinOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) tint: vec4<f32>,
    @location(3) world: vec3<f32>,
    // x: material index, y: 1 on face vertices that carry a face UV.
    @location(4) style: vec2<f32>,
    // Head forward (+Z) and left (+X) axes in world space, for the face shadow map.
    @location(5) fwd: vec3<f32>,
    @location(6) left: vec3<f32>,
};

@vertex fn vertex_skinned(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(5) color: vec3<f32>,
    @location(8) joints: vec4<u32>,
    @location(9) weights: vec4<f32>,
    @location(10) kind: vec4<u32>,
    @location(11) face_uv: vec2<f32>,
    @location(3) translation_scale: vec4<f32>,
    @location(4) tint: vec4<f32>,
    @location(6) stretch: vec4<f32>,
    @location(7) rotation: vec4<f32>,
) -> SkinOut {
    let s = skin_blend(joints, weights, position, normal);
    var out: SkinOut;
    let world = rotate(rotation, s.local * stretch.xyz) * translation_scale.w + translation_scale.xyz;
    out.clip = frame.view_projection * vec4<f32>(world, 1.0);
    out.normal = rotate(rotation, s.bent / stretch.xyz);
    out.uv = face_uv;
    out.tint = vec4<f32>(tint.rgb * color, tint.a);
    out.world = world;
    out.style = vec2<f32>(f32(kind.x), f32(kind.y));
    out.fwd = rotate(rotation, rotate(s.real, vec3<f32>(0.0, 0.0, 1.0)));
    out.left = rotate(rotation, rotate(s.real, vec3<f32>(1.0, 0.0, 0.0)));
    return out;
}

fn step_band(x: f32, edge: f32, soft: f32) -> f32 {
    let w = max(soft, 0.001);
    return smoothstep(edge - w, edge + w, x);
}

// toon.faceShadowMap
fn face_shadow_map(u: f32, v: f32) -> f32 {
    var t = u;
    let cy = (v - 0.30) / 0.28;
    t = t + 0.06 * (1.0 - clamp(cy * cy, 0.0, 1.0));
    let nx = (u - 0.44) / 0.07;
    let ny = (v - 0.33) / 0.09;
    let r2 = nx * nx + ny * ny;
    if (r2 < 1.0) {
        t = t - 0.10 * (1.0 - r2) * (1.0 - r2);
    }
    let ey = (v - 0.45) / 0.10;
    t = t + 0.04 * (1.0 - clamp(ey * ey, 0.0, 1.0));
    return clamp(t, 0.0, 1.0);
}

// toon.faceLit: 1 lit, 0 shadow.
fn face_lit(uv: vec2<f32>, fwd: vec3<f32>, left: vec3<f32>, l: vec3<f32>, soft: f32) -> f32 {
    let lf = dot(l, fwd);
    let ll = dot(l, left);
    let len = sqrt(lf * lf + ll * ll);
    if (len < 0.0001) {
        return 1.0;
    }
    let ctrl = 1.0 - (lf / len * 0.5 + 0.5);
    var u = uv.x;
    if (ll < 0.0) {
        u = 1.0 - uv.x;
    }
    let w = max(soft, 0.001);
    return smoothstep(ctrl - w, ctrl + w, face_shadow_map(u, uv.y));
}

@fragment fn frag_skinned(in: SkinOut) -> @location(0) vec4<f32> {
    let base = in.tint.rgb;
    if (in.tint.a < 0.0) {
        return vec4<f32>(hazed(base, in.world, 0.0), 1.0);
    }
    let flags = u32(cel.v[0].w);
    let m = 2u + u32(in.style.x) * 6u;
    let a = cel.v[m];
    let b = cel.v[m + 1u];
    let c = cel.v[m + 2u];
    let d = cel.v[m + 3u];
    let e = cel.v[m + 5u];
    let n = normalize(in.normal);
    let l = frame.light_direction.xyz;
    let view = normalize(frame.eye.xyz - in.world);
    let ndl = dot(n, l);

    var lit = step_band(ndl, a.x, a.y);
    var deep = step_band(ndl, a.z, a.y);
    var mask = 1.0;
    if (in.style.y > 0.5) {
        // The face terminator comes from the face shadow map, not from the normal.
        mask = face_lit(in.uv, normalize(in.fwd), normalize(in.left), l, cel.v[1].x);
        lit = mask;
        deep = max(deep, mask);
    }
    if ((flags & 4u) != 0u && in.style.y > 0.5) {
        return vec4<f32>(mask, mask, mask, 1.0);
    }
    let shadow_rgb = mix(c.rgb, b.rgb, deep);
    let ramp = mix(shadow_rgb, vec3<f32>(1.0, 1.0, 1.0), lit);

    let h = normalize(l + view);
    let spec = step_band(dot(n, h), c.w, e.x) * lit * d.w;
    let ndv = clamp(dot(n, view), 0.0, 1.0);
    let rim = smoothstep(1.0 - a.w, 1.0 - a.w + 0.04, 1.0 - ndv) * clamp(ndl * 2.0 + 0.3, 0.0, 1.0) * b.w;

    let hemi = n.y * 0.5 + 0.5;
    let illum = mix(frame.ambient_ground.rgb, frame.ambient_sky.rgb, hemi) + frame.light_color.rgb;
    var color = (base * ramp + base * rim + d.rgb * spec) * illum;
    if ((flags & 2u) != 0u) {
        // Ramp view: lit white, shadow blue, deep violet, highlight yellow, rim red.
        var dbg = mix(mix(vec3<f32>(0.45, 0.10, 0.55), vec3<f32>(0.25, 0.40, 0.95), deep), vec3<f32>(0.95, 0.95, 0.95), lit);
        dbg = mix(dbg, vec3<f32>(1.0, 0.9, 0.2), clamp(spec * 2.0, 0.0, 1.0));
        dbg = mix(dbg, vec3<f32>(0.95, 0.2, 0.2), clamp(rim * 3.0, 0.0, 1.0));
        return vec4<f32>(dbg, 1.0);
    }
    // Lumen strips and visors glow; instance tint alpha above 1 glows the whole body.
    let glow_amount = clamp(max(e.y, in.tint.a - 1.0), 0.0, 1.0);
    let glow = base * (0.9 + 0.8 * frame.horizon.a);
    color = mix(color, glow, glow_amount);
    return vec4<f32>(hazed(color, in.world, glow_amount), 1.0);
}
