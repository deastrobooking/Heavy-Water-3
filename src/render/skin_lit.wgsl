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
    @location(7) eye_geometry: vec4<f32>,
    @location(8) eye_style: vec4<f32>,
    @location(9) eye_iris: vec4<f32>,
    @location(10) eye_shadow: vec4<f32>,
};

@vertex fn vertex_skinned(
    @location(0) position: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(5) color: vec3<f32>,
    @location(8) joints: vec4<u32>,
    @location(9) weights: vec4<f32>,
    @location(10) kind: vec4<u32>,
    @location(11) face_uv: vec2<f32>,
    @location(12) eye_geometry: vec4<f32>,
    @location(13) eye_style: vec4<f32>,
    @location(14) eye_iris: vec4<f32>,
    @location(15) eye_shadow: vec4<f32>,
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
    out.eye_geometry = eye_geometry;
    out.eye_style = eye_style;
    out.eye_iris = eye_iris;
    out.eye_shadow = eye_shadow;
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

// Resolution independent eye drawing. The CPU face marks intentionally omit the eye
// shapes on GPU-skinned characters; these SDFs are evaluated at fragment resolution.
fn eye_ellipse(p: vec2<f32>, center: vec2<f32>, radii: vec2<f32>) -> f32 {
    let delta = (p - center) / radii;
    return (length(delta) - 1.0) * min(radii.x, radii.y);
}

fn eye_over(dst: vec3<f32>, src: vec3<f32>, alpha: f32) -> vec3<f32> {
    return mix(dst, src, clamp(alpha, 0.0, 1.0));
}

// The eye opening with the upper lid cut flat (`toon.eyeOpening`).
fn eye_lid_line(q: vec2<f32>, center: vec2<f32>, w: f32, h: f32, lid: f32) -> f32 {
    return center.y + h * (1.0 - 0.5 * lid) + (q.x - center.x) / w * h * 0.3 * lid;
}

fn eye_opening(q: vec2<f32>, center: vec2<f32>, w: f32, h: f32, lid: f32) -> f32 {
    return max(eye_ellipse(q, center, vec2<f32>(w, h)), q.y - eye_lid_line(q, center, w, h, lid));
}

fn mark_segment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> vec2<f32> {
    let ab = b - a;
    let k = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
    return vec2<f32>(length(p - (a + ab * k)), k);
}

fn mark_hash(x: f32, y: f32) -> f32 {
    return fract(sin(x * 127.1 + y * 311.7) * 43758.5453);
}

fn mark_fill(d: f32, radius: f32, aa: f32) -> f32 {
    return 1.0 - smoothstep(radius - aa * 0.5, radius + aa * 0.5, d);
}

// Face marks under the eyes, as `toon.faceMark` draws them: 1 freckles, 2 scar, 3 war paint,
// 4 beauty mark, 5 tech seams, 6 tear lines. `packed` is the paint colour, 4 bits a channel.
fn draw_face_mark(original: vec3<f32>, uv: vec2<f32>, geometry: vec4<f32>, kind: f32, packed: f32) -> vec3<f32> {
    let mark = floor(kind + 0.5);
    if (mark < 0.5) {
        return original;
    }
    let x = floor(packed + 0.5);
    let pr = floor(x / 256.0);
    let pg = floor((x - pr * 256.0) / 16.0);
    let paint = vec3<f32>(pr, pg, x - pr * 256.0 - pg * 16.0) / 15.0;
    let p = vec2<f32>(0.5 + abs(uv.x - 0.5), uv.y);
    let center = vec2<f32>(0.5 + geometry.x, geometry.y);
    let w = geometry.z * 0.5;
    let h0 = w * geometry.w;
    let left = uv.x >= 0.5;
    let aa = 0.0035;
    var color = original;
    if (mark < 1.5) {
        let rx = (uv.x - 0.5) / (geometry.x + w * 0.9);
        let ry = (uv.y - (center.y - h0 * 1.5)) / (h0 * 0.75);
        let region = clamp(1.0 - (rx * rx + ry * ry), 0.0, 1.0);
        let cell = 0.024;
        let ix = floor(uv.x / cell);
        let iy = floor(uv.y / cell);
        let n = mark_hash(ix, iy);
        let dot_center = vec2<f32>((ix + 0.5 + (mark_hash(iy, ix) - 0.5) * 0.5) * cell, (iy + 0.5 + (n - 0.5) * 0.5) * cell);
        let freckle_d = length(uv - dot_center) - cell * (0.12 + 0.1 * n);
        let on = select(0.0, 1.0, n > 0.5 && region > 0.0);
        color = eye_over(color, vec3<f32>(0.627, 0.376, 0.247), mark_fill(freckle_d, 0.0, aa) * 0.55 * smoothstep(0.0, 0.4, region) * on);
    } else if (mark < 2.5) {
        let scar = mark_segment(uv, vec2<f32>(center.x - w * 0.35, center.y + h0 * 1.9), vec2<f32>(center.x + w * 0.45, center.y - h0 * 1.7));
        let scar_radius = 0.008 * (1.0 - 0.3 * abs(scar.y * 2.0 - 1.0));
        color = eye_over(color, vec3<f32>(0.788, 0.451, 0.424), mark_fill(scar.x, scar_radius, aa) * 0.9 * select(0.0, 1.0, left));
    } else if (mark < 3.5) {
        let a1 = vec2<f32>(center.x - w * 0.5, center.y - h0 * 1.25);
        let b1 = vec2<f32>(center.x + w * 1.15, center.y - h0 * 1.05);
        let s1 = mark_segment(p, a1, b1);
        color = eye_over(color, paint, mark_fill(s1.x, 0.0085 * mix(1.0, 0.45, s1.y), aa) * 0.92);
        let drop = vec2<f32>(w * 0.3, -0.03);
        let s2 = mark_segment(p, a1 + drop, b1 + drop);
        color = eye_over(color, paint, mark_fill(s2.x, 0.0085 * mix(1.0, 0.45, s2.y), aa) * 0.92);
    } else if (mark < 4.5) {
        let mole_d = length(uv - vec2<f32>(center.x + w * 0.75, center.y - h0 * 1.35));
        color = eye_over(color, vec3<f32>(0.231, 0.145, 0.125), mark_fill(mole_d, 0.0075, aa) * 0.9 * select(0.0, 1.0, left));
    } else if (mark < 5.5) {
        let top = vec2<f32>(center.x + w * 0.2, center.y - h0 * 1.15);
        let knee = vec2<f32>(center.x + w * 0.2, center.y - h0 * 2.2);
        let foot = vec2<f32>(center.x + w * 0.95, center.y - h0 * 2.8);
        let seam_d = min(mark_segment(p, top, knee).x, mark_segment(p, knee, foot).x);
        color = eye_over(color, paint, mark_fill(seam_d, 0.0035, aa) * 0.95);
        color = eye_over(color, paint, mark_fill(length(p - top), 0.0075, aa));
    } else {
        let tear = mark_segment(p, vec2<f32>(center.x - w * 0.8, center.y - h0 * 0.7), vec2<f32>(0.575, 0.205));
        color = eye_over(color, vec3<f32>(0.227, 0.149, 0.133), mark_fill(tear.x, 0.0065 * mix(1.0, 0.3, tear.y), aa) * 0.85);
    }
    return color;
}

fn draw_anime_eyes(
    original: vec3<f32>, uv: vec2<f32>, geometry: vec4<f32>, style: vec4<f32>,
    iris_color: vec3<f32>, iris_dark: vec3<f32>,
) -> vec3<f32> {
    let side = select(-1.0, 1.0, uv.x >= 0.5);
    let p = vec2<f32>(0.5 + abs(uv.x - 0.5), uv.y);
    let spacing = geometry.x;
    let eye_y = geometry.y;
    let w = geometry.z * 0.5;
    let h = w * geometry.w;
    let tilt = style.x;
    let pupil_size = style.y;
    let center = vec2<f32>(0.5 + spacing, eye_y);
    let q = vec2<f32>(p.x, p.y - (p.x - center.x) * tilt);
    // A small UV-space transition stays smooth with Mach's current WGSL compiler,
    // which rejects derivative builtins in this shared module.
    let aa = 0.0035;
    let lid = style.w;
    let eye_d = eye_opening(q, center, w, h, lid);
    let eye_mask = 1.0 - smoothstep(-aa, aa, eye_d);
    var color = original;
    color = eye_over(color, vec3<f32>(0.96, 0.93, 0.86), eye_mask);

    let iris_center = vec2<f32>(center.x, center.y - h * 0.12);
    let iris_r = vec2<f32>(w * 0.54, h * 0.78);
    let iris_d = eye_ellipse(q, iris_center, iris_r);
    let iris_mask = (1.0 - smoothstep(-aa, aa, iris_d)) * eye_mask;
    let gradient = clamp((q.y - (iris_center.y - iris_r.y)) / (2.0 * iris_r.y), 0.0, 1.0);
    let iris = mix(iris_color, iris_dark, smoothstep(0.25, 0.95, gradient));
    color = eye_over(color, iris, iris_mask);
    let rim = (1.0 - smoothstep(0.0, aa * 2.0, abs(iris_d) - aa * 0.6)) * eye_mask * 0.62;
    color = eye_over(color, iris_dark, rim);

    let pupil_d = eye_ellipse(q, iris_center + vec2<f32>(0.0, iris_r.y * 0.05), iris_r * vec2<f32>(pupil_size, pupil_size * 1.1));
    color = eye_over(color, iris_dark * 0.45, (1.0 - smoothstep(-aa, aa, pupil_d)) * eye_mask);
    let highlight = eye_ellipse(q, iris_center + vec2<f32>(-iris_r.x * 0.35 * side, iris_r.y * 0.42), iris_r * vec2<f32>(0.30, 0.22));
    color = eye_over(color, vec3<f32>(0.96, 0.93, 0.86), (1.0 - smoothstep(-aa, aa, highlight)) * eye_mask);
    if (style.z > 1.5) {
        let highlight_small = eye_ellipse(q, iris_center + vec2<f32>(iris_r.x * 0.38 * side, -iris_r.y * 0.45), iris_r * vec2<f32>(0.13, 0.10));
        color = eye_over(color, vec3<f32>(1.0), (1.0 - smoothstep(-aa, aa, highlight_small)) * eye_mask * 0.9);
    }
    let lid_y = eye_lid_line(q, center, w, h, lid);
    let lid_shadow = smoothstep(lid_y - h * 0.55, lid_y - h * 0.05, q.y) * eye_mask * (1.0 - iris_mask) * 0.60;
    color = eye_over(color, vec3<f32>(0.72, 0.70, 0.86), lid_shadow);

    // A softly antialiased upper ink line keeps the anime silhouette without a pixel stair-step.
    let upper = abs(eye_d - h * 0.025);
    let upper_mask = (1.0 - smoothstep(aa, aa * 2.3, upper)) * smoothstep(center.y - h * 0.12, center.y + h * 0.28, q.y);
    return eye_over(color, vec3<f32>(0.29, 0.21, 0.19), upper_mask * 0.88);
}

@fragment fn frag_skinned(in: SkinOut) -> @location(0) vec4<f32> {
    var base = in.tint.rgb;
    if (in.tint.a < 0.0) {
        return vec4<f32>(hazed(base, in.world, 0.0), 1.0);
    }
    if (in.style.y > 0.5) {
        base = draw_face_mark(base, in.uv, in.eye_geometry, in.eye_iris.w, in.eye_shadow.w);
        base = draw_anime_eyes(base, in.uv, in.eye_geometry, in.eye_style, in.eye_iris.rgb, in.eye_shadow.rgb);
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

    let sun = sunlight(in.world, n);
    var lit = step_band(ndl, a.x, a.y) * sun;
    var deep = step_band(ndl, a.z, a.y) * sun;
    var mask = 1.0;
    if (in.style.y > 0.5) {
        // The face terminator comes from the face shadow map, not from the normal.
        mask = face_lit(in.uv, normalize(in.fwd), normalize(in.left), l, cel.v[1].x);
        lit = mask * sun;
        deep = max(deep, mask * sun);
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
