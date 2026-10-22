//! Anime/cel shading math. Every function here is pure scalar/vector math
//! that ports line-for-line to WGSL/GLSL/HLSL — the Zig versions are used by
//! the CPU preview renderer, for baking textures, and as the reference
//! implementation for unit tests.

const std = @import("std");
const m = @import("math.zig");
const spec_mod = @import("spec.zig");
const CelStyle = @import("CelStyle.zig");
const Vec2 = m.Vec2;
const Vec3 = m.Vec3;
const Rgb = spec_mod.Rgb;
const EyeSpec = spec_mod.EyeSpec;

pub fn mix(a: Rgb, b: Rgb, t: f32) Rgb {
    return .{ .r = m.lerp(a.r, b.r, t), .g = m.lerp(a.g, b.g, t), .b = m.lerp(a.b, b.b, t) };
}
pub fn mulc(a: Rgb, b: Rgb) Rgb {
    return .{ .r = a.r * b.r, .g = a.g * b.g, .b = a.b * b.b };
}
pub fn scalec(a: Rgb, s: f32) Rgb {
    return .{ .r = a.r * s, .g = a.g * s, .b = a.b * s };
}
pub fn addc(a: Rgb, b: Rgb) Rgb {
    return .{ .r = a.r + b.r, .g = a.g + b.g, .b = a.b + b.b };
}

// ---------------------------------------------------------------- lighting
pub const ToonParams = struct {
    /// N·L at which light turns to shadow.
    threshold: f32 = 0.05,
    /// Half-width of the terminator blur. 0.0-0.02 = crisp anime edge.
    softness: f32 = 0.015,
    /// Shadow color = base * shadow_tint (a saturated, slightly cool tint
    /// reads as "anime"; plain darkening reads as "3D").
    shadow_tint: Rgb = Rgb.init(0.72, 0.66, 0.82),
    /// Second, deeper band (occlusion / core shadow). Set threshold < -1 to disable.
    deep_threshold: f32 = -0.55,
    deep_tint: Rgb = Rgb.init(0.55, 0.48, 0.66),
    rim_width: f32 = 0.25,
    rim_strength: f32 = 0.35,
    ambient: f32 = 0.0,
};

/// Two-band cel ramp. Returns 1 = fully lit, 0 = shadow.
pub fn cel(ndl: f32, threshold: f32, softness: f32) f32 {
    return m.smoothstep(threshold - softness, threshold + softness, ndl);
}

/// Classic anime lighting: lit / shadow / deep shadow bands plus a
/// light-side rim. `shadow_mask` lets callers inject cast shadows or the
/// face-shadow-map result (1 = lit). Returns the shaded color.
pub fn shadeToon(base: Rgb, n: Vec3, l: Vec3, v: Vec3, shadow_mask: f32, p: ToonParams) Rgb {
    const ndl = n.dot(l);
    const lit = @min(cel(ndl, p.threshold, p.softness), shadow_mask);
    const deep = cel(ndl, p.deep_threshold, p.softness);
    const shadow_col = mix(mulc(base, p.deep_tint), mulc(base, p.shadow_tint), deep);
    var c = mix(shadow_col, base, lit);
    // Rim: thin bright band on silhouette edges that face the light.
    const ndv = m.saturate(n.dot(v));
    const rim = m.smoothstep(1 - p.rim_width, 1 - p.rim_width + 0.04, 1 - ndv) * m.saturate(ndl * 2 + 0.3);
    c = addc(c, scalec(base, rim * p.rim_strength));
    return addc(c, scalec(base, p.ambient));
}

/// World-space outline extrusion distance that yields `px` pixels on screen
/// regardless of distance (inverted-hull technique). Clamped so far-away
/// characters don't get fat lines and close-ups don't get hairlines.
pub fn outlineWidth(px: f32, view_depth: f32, fovy: f32, screen_h: f32, min_w: f32, max_w: f32) f32 {
    const world_per_px = 2.0 * view_depth * @tan(fovy * 0.5) / screen_h;
    return m.clamp(px * world_per_px, min_w, max_w);
}


// ---------------------------------------------------------------- per-material cel shading
/// The character shader's lighting for one material, line for line what `render/skin_lit.wgsl`
/// computes: a lit / shadow / deep ramp, a hard specular band, a hard rim, and emissive glow.
/// `face_lit` replaces the N.L ramp on face vertices (1 = lit, from `faceLit`). `illum` is the
/// scene light the ramp multiplies (hemispheric ambient plus key colour). `night` is 0..1.
pub fn shadeCel(s: CelStyle.MaterialStyle, base: Rgb, n: Vec3, l: Vec3, v: Vec3, face_lit: ?f32, illum: Rgb, night: f32) Rgb {
    const ndl = n.dot(l);
    var lit = celBand(ndl, s.ramp.threshold, s.ramp.softness);
    var deep = celBand(ndl, s.ramp.deep_threshold, s.ramp.softness);
    if (face_lit) |mask| {
        lit = mask;
        deep = @max(deep, mask);
    }
    const shadow = mix(rgb3(s.ramp.deep_tint), rgb3(s.ramp.shadow_tint), deep);
    const ramp = mix(shadow, Rgb.init(1, 1, 1), lit);
    const h = l.add(v).normalize();
    const spec = celBand(n.dot(h), s.specular.threshold, s.specular.softness) * lit * s.specular.strength;
    const ndv = m.saturate(n.dot(v));
    const rim = m.smoothstep(1 - s.rim.width, 1 - s.rim.width + 0.04, 1 - ndv) * m.saturate(ndl * 2 + 0.3) * s.rim.strength;
    const body = addc(addc(mulc(base, ramp), scalec(base, rim)), scalec(rgb3(s.specular.tint), spec));
    const shaded = mulc(body, illum);
    return mix(shaded, scalec(base, 0.9 + 0.8 * night), s.emissive);
}

fn celBand(x: f32, edge: f32, soft: f32) f32 {
    const w = @max(soft, 0.001);
    return m.smoothstep(edge - w, edge + w, x);
}

fn rgb3(c: CelStyle.Rgb3) Rgb {
    return Rgb.init(c[0], c[1], c[2]);
}

/// World-space ink extrusion for a character vertex, as `skin_hull.wgsl` computes it: the
/// material's pixel width (face detail 0.6x, all scaled by the style) through `outlineWidth`.
pub fn hullWidth(style: *const CelStyle.CelStyle, material: CelStyle.Material, face: bool, view_depth: f32, fovy: f32, screen_h: f32) f32 {
    const px = style.get(material).outline.width_px * style.outline_scale * @as(f32, if (face) 0.6 else 1.0);
    if (px <= 0) return 0;
    return outlineWidth(px, view_depth, fovy, screen_h, style.outline_min_world, style.outline_max_world);
}

// ---------------------------------------------------------------- face shadows
/// Analytic face shadow threshold map ("SDF face shadow" technique).
/// For light arriving from the character's LEFT (+X), a texel at face UV
/// (u, v) is lit when `faceShadowMap(u, v) > ctrl`. The map is ~u, bent so
/// the terminator curves around the cheek and the nose casts a small wedge.
/// Bake to a texture (see `bakeFaceShadowMap`) for the GPU.
pub fn faceShadowMap(u: f32, v: f32) f32 {
    var t = u;
    // Cheek curvature: the terminator bows toward the lit side below the eyes.
    const cy = (v - 0.30) / 0.28;
    t += 0.06 * (1 - m.saturate(cy * cy));
    // Nose wedge: just right of the nose (u < 0.5) stays in shadow longer.
    const nx = (u - 0.44) / 0.07;
    const ny = (v - 0.29) / 0.08;
    const r2 = nx * nx + ny * ny;
    if (r2 < 1) t -= 0.10 * (1 - r2) * (1 - r2);
    // Eye sockets stay lit slightly longer (keeps eyes readable).
    const ey = (v - 0.45) / 0.10;
    t += 0.04 * (1 - m.saturate(ey * ey));
    return m.saturate(t);
}

/// Shader-side evaluation. `fwd` and `left` are the head bone's +Z (forward)
/// and +X (character's left) axes in world space.
/// Returns 1 = lit, 0 = shadow, with a small blur `soft`.
pub fn faceLit(face_uv: Vec2, fwd: Vec3, left: Vec3, light_dir: Vec3, soft: f32) f32 {
    // Project onto the head's horizontal plane.
    const lf = light_dir.dot(fwd);
    const ll = light_dir.dot(left);
    const len = @sqrt(lf * lf + ll * ll);
    if (len < 1e-4) return 1; // light straight overhead: fully lit
    const f_dot_l = lf / len;
    const ctrl = 1.0 - (f_dot_l * 0.5 + 0.5); // 0 front-lit .. 1 back-lit
    // Mirror the map when light comes from the character's right.
    const u = if (ll >= 0) face_uv.x else 1.0 - face_uv.x;
    return m.smoothstep(ctrl - soft, ctrl + soft, faceShadowMap(u, face_uv.y));
}

// ---------------------------------------------------------------- eyes
pub const Decal = struct { color: Rgb, alpha: f32 };

fn ellipse(p: Vec2, c: Vec2, rx: f32, ry: f32) f32 {
    // approximate signed distance (in units of the smaller radius)
    const dx = (p.x - c.x) / rx;
    const dy = (p.y - c.y) / ry;
    return (@sqrt(dx * dx + dy * dy) - 1.0) * @min(rx, ry);
}

/// The eye opening with the upper lid cut flat by `lid` (0 = the plain ellipse): the cut line
/// sits lower as the lid closes and slants down toward the inner corner. `skin_lit.wgsl`
/// `eye_opening` is the same formula.
fn eyeOpening(q: Vec2, c: Vec2, w: f32, h: f32, lid: f32) f32 {
    return @max(ellipse(q, c, w, h), q.y - lidLine(q, c, w, h, lid));
}

fn lidLine(q: Vec2, c: Vec2, w: f32, h: f32, lid: f32) f32 {
    return c.y + h * (1 - 0.5 * lid) + (q.x - c.x) / w * h * 0.3 * lid;
}

/// Distance from `p` to the segment a..b and how far along it (0..1) the nearest point lies.
fn segment(p: Vec2, a: Vec2, b: Vec2) struct { d: f32, k: f32 } {
    const ab = b.sub(a);
    const k = m.saturate(p.sub(a).dot(ab) / ab.dot(ab));
    return .{ .d = p.sub(a.add(ab.scale(k))).length(), .k = k };
}

/// A face mark's paint colour packed into one float (4 bits a channel) for a spare vertex lane.
pub fn packMarkColor(c: Rgb) f32 {
    const r = @round(m.saturate(c.r) * 15);
    const g = @round(m.saturate(c.g) * 15);
    const b = @round(m.saturate(c.b) * 15);
    return r * 256 + g * 16 + b;
}

pub fn unpackMarkColor(v: f32) Rgb {
    const x = @floor(v + 0.5);
    const r = @floor(x / 256);
    const g = @floor((x - r * 256) / 16);
    const b = x - r * 256 - g * 16;
    return Rgb.init(r / 15, g / 15, b / 15);
}

fn hash2(x: f32, y: f32) f32 {
    const v = @sin(x * 127.1 + y * 311.7) * 43758.5453;
    return v - @floor(v);
}

/// Freckles, a scar, war paint and the like, drawn under the eyes. Coordinates follow the
/// eye: `p` is the mirrored face UV, `ec` the eye centre, `w` and `h0` its half width and open
/// half height. `skin_lit.wgsl` `draw_face_mark` is the same drawing per fragment.
fn faceMark(dst: Decal, uv: Vec2, eyes: EyeSpec, aa: f32) Decal {
    var out = dst;
    const p = Vec2.init(0.5 + @abs(uv.x - 0.5), uv.y);
    const ec = Vec2.init(0.5 + eyes.spacing, eyes.height);
    const w = eyes.size * 0.5;
    const h0 = w * eyes.aspect;
    const left = uv.x >= 0.5;
    switch (eyes.mark) {
        .none => {},
        .freckles => {
            const rx = (uv.x - 0.5) / (eyes.spacing + w * 0.9);
            const ry = (uv.y - (ec.y - h0 * 1.5)) / (h0 * 0.75);
            const region = m.saturate(1 - (rx * rx + ry * ry));
            if (region > 0) {
                const cell: f32 = 0.024;
                const ix = @floor(uv.x / cell);
                const iy = @floor(uv.y / cell);
                const n = hash2(ix, iy);
                if (n > 0.5) {
                    const center = Vec2.init((ix + 0.5 + (hash2(iy, ix) - 0.5) * 0.5) * cell, (iy + 0.5 + (n - 0.5) * 0.5) * cell);
                    const d = uv.sub(center).length() - cell * (0.12 + 0.1 * n);
                    out = over(out, Rgb.hex(0xa0603f), (1 - m.smoothstep(-aa * 0.5, aa * 0.5, d)) * 0.55 * m.smoothstep(0, 0.4, region));
                }
            }
        },
        .scar => if (left) {
            const sg = segment(uv, Vec2.init(ec.x - w * 0.35, ec.y + h0 * 1.9), Vec2.init(ec.x + w * 0.45, ec.y - h0 * 1.7));
            const radius = 0.008 * (1 - 0.3 * @abs(sg.k * 2 - 1));
            out = over(out, Rgb.hex(0xc9736c), (1 - m.smoothstep(radius - aa * 0.5, radius + aa * 0.5, sg.d)) * 0.9);
        },
        .war_paint => {
            const a1 = Vec2.init(ec.x - w * 0.5, ec.y - h0 * 1.25);
            const b1 = Vec2.init(ec.x + w * 1.15, ec.y - h0 * 1.05);
            for ([_]f32{ 0, 1 }) |i| {
                const drop = Vec2.init(w * 0.3 * i, -0.03 * i);
                const sg = segment(p, a1.add(drop), b1.add(drop));
                const radius = 0.0085 * m.lerp(1.0, 0.45, sg.k);
                out = over(out, eyes.mark_color, (1 - m.smoothstep(radius - aa * 0.5, radius + aa * 0.5, sg.d)) * 0.92);
            }
        },
        .beauty_mark => if (left) {
            const d = uv.sub(Vec2.init(ec.x + w * 0.75, ec.y - h0 * 1.35)).length() - 0.0075;
            out = over(out, Rgb.hex(0x3b2520), (1 - m.smoothstep(-aa * 0.5, aa * 0.5, d)) * 0.9);
        },
        .tech_seams => {
            const top = Vec2.init(ec.x + w * 0.2, ec.y - h0 * 1.15);
            const knee = Vec2.init(ec.x + w * 0.2, ec.y - h0 * 2.2);
            const foot = Vec2.init(ec.x + w * 0.95, ec.y - h0 * 2.8);
            const d = @min(segment(p, top, knee).d, segment(p, knee, foot).d) - 0.0035;
            out = over(out, eyes.mark_color, (1 - m.smoothstep(-aa * 0.5, aa * 0.5, d)) * 0.95);
            const node = p.sub(top).length() - 0.0075;
            out = over(out, eyes.mark_color, 1 - m.smoothstep(-aa * 0.5, aa * 0.5, node));
        },
        .tear_lines => {
            // Ends beside the default mouth corner (the shader has no mouth data).
            const sg = segment(p, Vec2.init(ec.x - w * 0.8, ec.y - h0 * 0.7), Vec2.init(0.575, 0.205));
            const radius = 0.0065 * m.lerp(1.0, 0.3, sg.k);
            out = over(out, Rgb.hex(0x3a2622), (1 - m.smoothstep(radius - aa * 0.5, radius + aa * 0.5, sg.d)) * 0.85);
        },
    }
    return out;
}

/// Porter-Duff "over" with straight (non-premultiplied) alpha.
fn over(dst: Decal, src: Rgb, a: f32) Decal {
    const out_a = a + dst.alpha * (1 - a);
    if (out_a < 1e-6) return dst;
    const kd = dst.alpha * (1 - a) / out_a;
    const ks = a / out_a;
    return .{
        .color = .{ .r = src.r * ks + dst.color.r * kd, .g = src.g * ks + dst.color.g * kd, .b = src.b * ks + dst.color.b * kd },
        .alpha = out_a,
    };
}

/// Procedural anime eyes, brows and mouth as a decal over the face UV
/// (u across face 0..1, v chin(0)..crown(1)). `aa` is the antialias width
/// in UV units (use fwidth(uv) in a shader). Everything is SDF-based so the
/// eyes stay crisp at any resolution and expressions are just parameters.
pub const Expression = struct {
    /// 0 = closed, 1 = open.
    eye_open: f32 = 1.0,
    /// Look direction in face-UV units (shifts iris).
    look: Vec2 = .{},
    /// -1 frown .. 1 smile.
    smile: f32 = 0.3,
    mouth_open: f32 = 0.0,
    brow_raise: f32 = 0.0,
};

pub fn faceDecal(uv: Vec2, eyes: EyeSpec, expr: Expression, aa: f32) Decal {
    return faceDecalImpl(uv, eyes, expr, aa, true);
}

/// Face marks for the GPU-skinned path. The eyes are evaluated per fragment in
/// `skin_lit.wgsl`; brows, nose and mouth remain baked into the mesh colors.
pub fn faceDecalWithoutEyes(uv: Vec2, eyes: EyeSpec, expr: Expression, aa: f32) Decal {
    return faceDecalImpl(uv, eyes, expr, aa, false);
}

fn faceDecalImpl(uv: Vec2, eyes: EyeSpec, expr: Expression, aa: f32, draw_eyes: bool) Decal {
    var out: Decal = .{ .color = Rgb.init(0, 0, 0), .alpha = 0 };
    if (uv.x < 0 or uv.y < 0) return out;
    // Warm charcoal keeps linework distinct from skin without turning the eye into a black mask.
    const lash = Rgb.hex(0x493631);
    const white = Rgb.init(0.96, 0.93, 0.86);

    // mirror: work in the left eye's space
    const side: f32 = if (uv.x >= 0.5) 1 else -1;
    const p = Vec2.init(0.5 + @abs(uv.x - 0.5), uv.y);
    const ec = Vec2.init(0.5 + eyes.spacing, eyes.height);
    const w = eyes.size * 0.5;
    const h = w * eyes.aspect * m.lerp(0.06, 1.0, expr.eye_open);
    // tilt outer corner up
    const q = Vec2.init(p.x, p.y - (p.x - ec.x) * eyes.tilt);
    if (draw_eyes) out = faceMark(out, uv, eyes, aa);

    if (draw_eyes and expr.eye_open > 0.08) {
        // eye opening: an ellipse, its top cut by the lid
        const d_open = eyeOpening(q, ec, w, h, eyes.lid);
        const in_eye = 1 - m.smoothstep(-aa, aa, d_open);
        if (in_eye > 0) {
            out = over(out, white, in_eye);
            // iris: tall ellipse, vertical gradient dark (top) -> light (bottom)
            const ic = Vec2.init(ec.x + expr.look.x * w * side, ec.y - h * 0.12 + expr.look.y * h);
            const irx = w * 0.54;
            const iry = h * 0.78;
            const d_iris = ellipse(q, ic, irx, iry);
            const a_iris = (1 - m.smoothstep(-aa, aa, d_iris)) * in_eye;
            const g = m.saturate((q.y - (ic.y - iry)) / (2 * iry));
            var iris_col = mix(eyes.iris_color, eyes.iris_dark, m.smoothstep(0.25, 0.95, g));
            // lower-iris glow, a staple of anime eyes
            const glow = m.saturate(1 - ellipse(q, Vec2.init(ic.x, ic.y - iry * 0.45), irx * 0.7, iry * 0.35) / (0.3 * irx));
            iris_col = mix(iris_col, addc(eyes.iris_color, Rgb.init(0.25, 0.25, 0.2)), glow * 0.6 * (1 - g));
            out = over(out, iris_col, a_iris);
            // iris rim
            const ring = (1 - m.smoothstep(0, aa * 2, @abs(d_iris) - aa * 0.6)) * in_eye;
            out = over(out, eyes.iris_dark, ring * 0.62);
            // pupil
            const d_pupil = ellipse(q, Vec2.init(ic.x, ic.y + iry * 0.05), irx * eyes.pupil_size, iry * eyes.pupil_size * 1.1);
            out = over(out, scalec(eyes.iris_dark, 0.45), (1 - m.smoothstep(-aa, aa, d_pupil)) * in_eye);
            // highlights (fixed to the character's upper-left so both eyes match)
            const hl_main = ellipse(q, Vec2.init(ic.x - irx * 0.35 * side, ic.y + iry * 0.42), irx * 0.30, iry * 0.22);
            out = over(out, white, (1 - m.smoothstep(-aa, aa, hl_main)) * in_eye);
            if (eyes.highlight_count > 1) {
                const hl2 = ellipse(q, Vec2.init(ic.x + irx * 0.38 * side, ic.y - iry * 0.45), irx * 0.13, iry * 0.10);
                out = over(out, white, (1 - m.smoothstep(-aa, aa, hl2)) * in_eye * 0.9);
            }
            // upper-lid shadow on the eye white
            const lid_y = lidLine(q, ec, w, h, eyes.lid);
            const lid_sh = m.smoothstep(lid_y - h * 0.55, lid_y - h * 0.05, q.y) * in_eye;
            out = over(out, Rgb.init(0.72, 0.70, 0.86), lid_sh * 0.6 * (1 - a_iris));
        }
        // upper lash line: a band hugging the top of the opening, thin at the
        // inner corner, heavy at the outer corner, ending in a small flick.
        const ang = std.math.atan2((q.y - ec.y) / h, (q.x - ec.x) / w); // 0 outer .. pi inner
        if (ang > -0.35 and ang < m.pi + 0.15) {
            const s_out = 1 - m.saturate(ang / m.pi);
            const thick = h * (0.035 + 0.13 * m.smoothstep(0.05, 0.75, s_out));
            const d_edge = eyeOpening(q, ec, w, h, eyes.lid);
            var a_lash = (1 - m.smoothstep(thick - aa, thick + aa, d_edge)) * m.smoothstep(-0.25 * thick - aa, -0.25 * thick + aa, d_edge);
            a_lash *= m.smoothstep(-0.35, 0.0, ang) * (1 - m.smoothstep(m.pi - 0.1, m.pi + 0.15, ang));
            out = over(out, lash, a_lash);
        }
        {
            const rx = (q.x - ec.x) / w;
            if (rx > 0.80 and rx < 1.32) {
                const line_y = ec.y + h * (0.10 + (rx - 0.80) * 0.55);
                const th = h * 0.13 * (1 - m.smoothstep(0.85, 1.32, rx));
                out = over(out, lash, 1 - m.smoothstep(th - aa, th + aa, @abs(q.y - line_y)));
            }
        }
        // thin lower lash at the outer half
        const d_lo = ellipse(q, ec, w * 1.0, h * 1.02);
        if (q.y < ec.y - h * 0.55 and q.x > ec.x) {
            out = over(out, lash, (1 - m.smoothstep(aa * 0.5, aa * 1.5, @abs(d_lo))) * 0.48);
        }
    } else if (draw_eyes) {
        // closed eye: a happy arc
        const d = ellipse(q, Vec2.init(ec.x, ec.y - h * 3), w * 0.95, w * 0.55);
        const a = (1 - m.smoothstep(aa, aa * 2.5, @abs(d))) * @as(f32, if (q.y > ec.y - h * 3) 1 else 0);
        out = over(out, lash, a);
    }

    // brows: a tapered stroke, heavy at the inner end, tilted by `brow_tilt`. Distance to a
    // segment minus a radius that thins toward the temple keeps it crisp at any size.
    {
        const half_len = w * eyes.brow_length;
        const by = ec.y + w * eyes.aspect + eyes.brow_gap + expr.brow_raise * 0.03;
        const inner = Vec2.init(ec.x - half_len * 0.85, by - eyes.brow_tilt * half_len);
        const outer = Vec2.init(ec.x + half_len * 0.85, by + eyes.brow_tilt * half_len * 0.6);
        const seg = outer.sub(inner);
        const k = m.saturate(p.sub(inner).dot(seg) / seg.dot(seg));
        // The arch lifts the middle of the stroke (a parabola along it).
        const on = inner.add(seg.scale(k)).add(Vec2.init(0, eyes.brow_arch * 4 * k * (1 - k)));
        const radius = eyes.brow_weight * m.lerp(1.0, 0.4, k);
        const d_brow = p.sub(on).length() - radius;
        if (d_brow < aa * 2) out = over(out, scalec(lash, 0.9), (1 - m.smoothstep(-aa * 0.5, aa * 1.2, d_brow)) * 0.8);
    }

    // nose: only a short shadow under the tip plus a faint bridge line; the mesh carries the rest
    if (eyes.nose_mark > 0.001) {
        const nd = ellipse(uv, Vec2.init(0.5, eyes.nose_height - 0.012), 0.026, 0.014);
        const arc = (1 - m.smoothstep(aa * 0.4, aa * 1.4, @abs(nd))) * @as(f32, if (uv.y < eyes.nose_height - 0.012) 1 else 0);
        out = over(out, Rgb.hex(0x7a4a40), arc * eyes.nose_mark);
        const lx = (uv.x - 0.47) / 0.006;
        const ly = (uv.y - (eyes.nose_height + 0.03)) / 0.035;
        out = over(out, Rgb.hex(0x9a6a5e), m.saturate(1 - (lx * lx + ly * ly)) * eyes.nose_mark * 0.35);
    }

    // mouth (centered, not mirrored)
    const mx = (uv.x - 0.5) / eyes.mouth_width;
    const my = uv.y - (eyes.mouth_height + expr.smile * 0.012 * (mx * mx - 0.5));
    if (@abs(mx) < 1.0) {
        if (expr.mouth_open > 0.05) {
            const d_m = ellipse(uv, Vec2.init(0.5, eyes.mouth_height - 0.005), eyes.mouth_width * 0.65, 0.03 * expr.mouth_open);
            out = over(out, Rgb.hex(0x8a2f3c), 1 - m.smoothstep(-aa, aa, d_m));
        } else {
            out = over(out, Rgb.hex(0x7a4440), (1 - m.smoothstep(aa * 0.7, aa * 1.7, @abs(my))) * 0.85 * m.saturate(1.25 * (1 - @abs(mx))));
        }
    }
    // blush
    const bx = (p.x - ec.x - w * 0.15) / (w * 0.9);
    const by = (p.y - (ec.y - h * 1.35)) / (w * 0.35);
    const blush = m.saturate(1 - (bx * bx + by * by));
    if (blush > 0) out = over(out, Rgb.hex(0xff9aa8), blush * blush * 0.24);
    return out;
}

// ---------------------------------------------------------------- hair
/// Anime hair highlight ("angel ring"): a bright band at a fixed fraction
/// along each clump, only where the surface faces the viewer, with a
/// zig-zag edge. `uv.x` runs across the clump, `uv.y` root(0)->tip(1).
pub fn angelRing(uv: Vec2, ndv: f32, center: f32, width: f32) f32 {
    const zig = @abs(@mod(uv.x * 6.0, 2.0) - 1.0) * width * 0.6;
    const d = @abs(uv.y - center) - (width - zig);
    return (1 - m.smoothstep(0, 0.01, d)) * m.smoothstep(0.35, 0.7, ndv);
}

// ---------------------------------------------------------------- baking
/// Bake the face shadow map into an 8-bit grayscale buffer (size*size).
pub fn bakeFaceShadowMap(out: []u8, size: usize) void {
    for (0..size) |y| for (0..size) |x| {
        const u = (@as(f32, @floatFromInt(x)) + 0.5) / @as(f32, @floatFromInt(size));
        const v = 1 - (@as(f32, @floatFromInt(y)) + 0.5) / @as(f32, @floatFromInt(size));
        out[y * size + x] = @intFromFloat(@round(faceShadowMap(u, v) * 255));
    };
}

test "cel ramp is a step" {
    try std.testing.expect(cel(0.5, 0.05, 0.01) == 1);
    try std.testing.expect(cel(-0.5, 0.05, 0.01) == 0);
}

test "face lighting: front fully lit, back fully dark, side half" {
    const fwd = Vec3.unit_z;
    const left = Vec3.unit_x;
    try std.testing.expectEqual(@as(f32, 1), faceLit(.{ .x = 0.1, .y = 0.5 }, fwd, left, Vec3.unit_z, 0.01));
    try std.testing.expectEqual(@as(f32, 0), faceLit(.{ .x = 0.9, .y = 0.5 }, fwd, left, Vec3.unit_z.neg(), 0.01));
    // light from the left: left half (u > 0.5) lit, right half dark
    try std.testing.expect(faceLit(.{ .x = 0.85, .y = 0.6 }, fwd, left, Vec3.unit_x, 0.01) > 0.99);
    try std.testing.expect(faceLit(.{ .x = 0.15, .y = 0.6 }, fwd, left, Vec3.unit_x, 0.01) < 0.01);
    // and mirrored from the right
    try std.testing.expect(faceLit(.{ .x = 0.15, .y = 0.6 }, fwd, left, Vec3.unit_x.neg(), 0.01) > 0.99);
}

test "face marks follow the spec: brow above the eye, nose and mouth at their heights" {
    const e: EyeSpec = .{};
    // Brow: dark stroke sits above the eye top and is absent far above it.
    const brow_y = e.height + 0.5 * e.size * e.aspect + e.brow_gap;
    var found = false;
    var x: f32 = 0.5 + e.spacing - 0.1;
    while (x < 0.5 + e.spacing + 0.1) : (x += 0.005) {
        if (faceDecal(.{ .x = x, .y = brow_y }, e, .{}, 0.002).alpha > 0.5) found = true;
    }
    try std.testing.expect(found);
    try std.testing.expect(faceDecal(.{ .x = 0.5 + e.spacing, .y = brow_y + 0.12 }, e, .{}, 0.002).alpha < 0.01);
    // Mouth line moves with its height; the nose mark vanishes when switched off.
    var low = e;
    low.mouth_height = 0.12;
    try std.testing.expect(faceDecal(.{ .x = 0.5, .y = e.mouth_height }, e, .{ .smile = 0 }, 0.002).alpha > 0.5);
    try std.testing.expect(faceDecal(.{ .x = 0.5, .y = e.mouth_height }, low, .{ .smile = 0 }, 0.002).alpha < 0.05);
    var no_nose = e;
    no_nose.nose_mark = 0;
    const under_tip = Vec2.init(0.5, e.nose_height - 0.026);
    try std.testing.expect(faceDecal(under_tip, e, .{}, 0.002).alpha > 0.1);
    try std.testing.expect(faceDecal(under_tip, no_nose, .{}, 0.002).alpha < 0.01);
}

test "the lid cut lowers the top of the eye; marks draw where they belong and pack their colour" {
    var e: EyeSpec = .{};
    const top = Vec2.init(0.5 + e.spacing, e.height + e.size * 0.5 * e.aspect * 0.85);
    try std.testing.expect(faceDecal(top, e, .{}, 0.002).color.r > 0.6);
    e.lid = 0.6;
    // The same point is now above the lid: skin (no white) or lash ink, never the eye white.
    const cut = faceDecal(top, e, .{}, 0.002);
    try std.testing.expect(cut.alpha < 0.05 or cut.color.r < 0.5);
    // Each mark changes some part of the face and nothing far above the brows.
    for (std.enums.values(spec_mod.FaceMark)) |mark| {
        if (mark == .none) continue;
        var marked: EyeSpec = .{};
        marked.mark = mark;
        var changed = false;
        var y: f32 = 0.12;
        while (y < 0.62) : (y += 0.0025) {
            var x: f32 = 0.3;
            while (x < 0.95) : (x += 0.0025) {
                const a = faceDecal(.{ .x = x, .y = y }, .{}, .{}, 0.002);
                const b = faceDecal(.{ .x = x, .y = y }, marked, .{}, 0.002);
                if (@abs(a.alpha - b.alpha) > 0.3) changed = true;
            }
        }
        try std.testing.expect(changed);
        try std.testing.expectEqual(faceDecal(.{ .x = 0.6, .y = 0.85 }, .{}, .{}, 0.002).alpha, faceDecal(.{ .x = 0.6, .y = 0.85 }, marked, .{}, 0.002).alpha);
    }
    const paint = Rgb.hex(0x30e0ff);
    const back = unpackMarkColor(packMarkColor(paint) + 0.2);
    try std.testing.expectApproxEqAbs(paint.g, back.g, 1.0 / 30.0);
    try std.testing.expectApproxEqAbs(paint.b, back.b, 1.0 / 30.0);
}

test "eye decal is symmetric and opaque in the iris" {
    const e: EyeSpec = .{};
    const a = faceDecal(.{ .x = 0.5 + e.spacing, .y = e.height - 0.02 }, e, .{ .smile = 0 }, 0.002);
    const b = faceDecal(.{ .x = 0.5 - e.spacing, .y = e.height - 0.02 }, e, .{ .smile = 0 }, 0.002);
    try std.testing.expect(a.alpha > 0.99);
    try std.testing.expectApproxEqAbs(a.color.b, b.color.b, 0.05);
}

test "cel ramp orders lit above shadow above deep, per material" {
    const style = CelStyle.heavy_water;
    const white = Rgb.init(0.8, 0.8, 0.8);
    const illum = Rgb.init(1, 1, 1);
    const v = Vec3.unit_z;
    for ([_]CelStyle.Material{ .skin, .cloth_top, .hair, .armor }) |mat| {
        const s = style.get(mat).*;
        const lit = shadeCel(s, white, Vec3.unit_z, Vec3.unit_z, v, null, illum, 0);
        const shadow = shadeCel(s, white, Vec3.unit_z, Vec3.init(0.995, 0, 0.1), v, null, illum, 0);
        const deep = shadeCel(s, white, Vec3.unit_z, Vec3.unit_z.neg(), v, null, illum, 0);
        try std.testing.expect(lit.g > shadow.g);
        try std.testing.expect(shadow.g >= deep.g);
        try std.testing.expect(lit.g > deep.g);
    }
}

test "armor has a hard specular band and skin has none" {
    const style = CelStyle.heavy_water;
    const base = Rgb.init(0.5, 0.5, 0.5);
    const illum = Rgb.init(1, 1, 1);
    const n = Vec3.unit_z;
    // Light and view both along the normal: N.H = 1, inside the band.
    const armor = shadeCel(style.get(.armor).*, base, n, n, n, null, illum, 0);
    var no_spec = style.get(.armor).*;
    no_spec.specular.strength = 0;
    const plain = shadeCel(no_spec, base, n, n, n, null, illum, 0);
    try std.testing.expect(armor.r > plain.r + 0.2);
    const skin = style.get(.skin).*;
    try std.testing.expectEqual(@as(f32, 0), skin.specular.strength);
    // Off the band the highlight vanishes completely (hard edge).
    const off = shadeCel(style.get(.armor).*, base, n, Vec3.init(0.95, 0, 0.31), n, null, illum, 0);
    var off_plain = style.get(.armor).*;
    off_plain.specular.strength = 0;
    try std.testing.expectApproxEqAbs(off.r, shadeCel(off_plain, base, n, Vec3.init(0.95, 0, 0.31), n, null, illum, 0).r, 1e-6);
}

test "the face shadow map decides face lighting, not the normal" {
    const s = CelStyle.heavy_water.get(.skin).*;
    const base = Rgb.init(0.8, 0.6, 0.5);
    const illum = Rgb.init(1, 1, 1);
    const n = Vec3.unit_z;
    const l = Vec3.unit_z;
    const lit = shadeCel(s, base, n, l, n, 1, illum, 0);
    const dark = shadeCel(s, base, n, l, n, 0, illum, 0);
    try std.testing.expect(lit.r > dark.r);
    // Shadow is a tint of the base: cooler (blue falls less than red).
    try std.testing.expect(dark.b / lit.b > dark.r / lit.r - 0.15);
}

test "ink width matches outlineWidth and thins on faces" {
    const style = CelStyle.heavy_water;
    const body = hullWidth(&style, .armor, false, 3, 1.0, 1080);
    try std.testing.expectApproxEqAbs(outlineWidth(2.4, 3, 1.0, 1080, 0.0006, 0.02), body, 1e-7);
    try std.testing.expect(hullWidth(&style, .skin, true, 3, 1.0, 1080) < hullWidth(&style, .skin, false, 3, 1.0, 1080));
    try std.testing.expectEqual(@as(f32, 0), hullWidth(&style, .iris, false, 3, 1.0, 1080));
    // Pixel width stays constant until the world clamps bite.
    const near = hullWidth(&style, .armor, false, 1.5, 1.0, 1080);
    const far = hullWidth(&style, .armor, false, 3, 1.0, 1080);
    try std.testing.expectApproxEqRel(near * 2, far, 1e-4);
}
