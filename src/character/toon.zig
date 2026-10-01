//! Anime/cel shading math. Every function here is pure scalar/vector math
//! that ports line-for-line to WGSL/GLSL/HLSL — the Zig versions are used by
//! the CPU preview renderer, for baking textures, and as the reference
//! implementation for unit tests.

const std = @import("std");
const m = @import("math.zig");
const spec_mod = @import("spec.zig");
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
    const ny = (v - 0.33) / 0.09;
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
    var out: Decal = .{ .color = Rgb.init(0, 0, 0), .alpha = 0 };
    if (uv.x < 0 or uv.y < 0) return out;
    const lash = Rgb.hex(0x2a1a22);
    const white = Rgb.init(1, 1, 1);

    // mirror: work in the left eye's space
    const side: f32 = if (uv.x >= 0.5) 1 else -1;
    const p = Vec2.init(0.5 + @abs(uv.x - 0.5), uv.y);
    const ec = Vec2.init(0.5 + eyes.spacing, eyes.height);
    const w = eyes.size * 0.5;
    const h = w * eyes.aspect * m.lerp(0.06, 1.0, expr.eye_open);
    // tilt outer corner up
    const q = Vec2.init(p.x, p.y - (p.x - ec.x) * eyes.tilt);

    if (expr.eye_open > 0.08) {
        // eye opening: ellipse with flattened bottom
        const d_open = ellipse(q, ec, w, h);
        const in_eye = 1 - m.smoothstep(-aa, aa, d_open);
        if (in_eye > 0) {
            out = over(out, white, in_eye);
            // iris: tall ellipse, vertical gradient dark (top) -> light (bottom)
            const ic = Vec2.init(ec.x + expr.look.x * w * side, ec.y - h * 0.12 + expr.look.y * h);
            const irx = w * 0.62;
            const iry = h * 0.95;
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
            out = over(out, eyes.iris_dark, ring * 0.8);
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
            const lid_sh = m.smoothstep(ec.y + h * 0.45, ec.y + h * 0.95, q.y) * in_eye;
            out = over(out, Rgb.init(0.72, 0.70, 0.86), lid_sh * 0.6 * (1 - a_iris));
        }
        // upper lash line: a band hugging the top of the opening, thin at the
        // inner corner, heavy at the outer corner, ending in a small flick.
        const ang = std.math.atan2((q.y - ec.y) / h, (q.x - ec.x) / w); // 0 outer .. pi inner
        if (ang > -0.35 and ang < m.pi + 0.15) {
            const s_out = 1 - m.saturate(ang / m.pi);
            const thick = h * (0.05 + 0.22 * m.smoothstep(0.05, 0.75, s_out));
            const d_edge = ellipse(q, ec, w, h);
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
            out = over(out, lash, (1 - m.smoothstep(aa * 0.5, aa * 1.5, @abs(d_lo))) * 0.7);
        }
    } else {
        // closed eye: a happy arc
        const d = ellipse(q, Vec2.init(ec.x, ec.y - h * 3), w * 0.95, w * 0.55);
        const a = (1 - m.smoothstep(aa, aa * 2.5, @abs(d))) * @as(f32, if (q.y > ec.y - h * 3) 1 else 0);
        out = over(out, lash, a);
    }

    // brows: thin arcs
    const bc = Vec2.init(ec.x - w * 0.05, ec.y + w * eyes.aspect * 1.55 + expr.brow_raise * 0.03);
    const d_brow = ellipse(p, Vec2.init(bc.x, bc.y - w * 0.6), w * 1.05, w * 0.6);
    if (p.y > bc.y - w * 0.2 and @abs(p.x - bc.x) < w * 1.0) {
        out = over(out, lash, (1 - m.smoothstep(aa * 0.6, aa * 1.8, @abs(d_brow))) * 0.85);
    }

    // mouth (centered, not mirrored)
    const mx = (uv.x - 0.5) / 0.07;
    const my = uv.y - (0.205 + expr.smile * 0.012 * (mx * mx - 0.5));
    if (@abs(mx) < 1.0) {
        if (expr.mouth_open > 0.05) {
            const d_m = ellipse(uv, Vec2.init(0.5, 0.20), 0.045, 0.03 * expr.mouth_open);
            out = over(out, Rgb.hex(0x8a2f3c), 1 - m.smoothstep(-aa, aa, d_m));
        } else {
            out = over(out, lash, (1 - m.smoothstep(aa * 0.4, aa * 1.4, @abs(my))) * 0.8 * (1 - @abs(mx)));
        }
    }
    // blush
    const bx = (p.x - ec.x - w * 0.15) / (w * 0.9);
    const by = (p.y - (ec.y - h * 1.35)) / (w * 0.35);
    const blush = m.saturate(1 - (bx * bx + by * by));
    if (blush > 0) out = over(out, Rgb.hex(0xff9aa8), blush * blush * 0.40);
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

test "eye decal is symmetric and opaque in the iris" {
    const e: EyeSpec = .{};
    const a = faceDecal(.{ .x = 0.5 + e.spacing, .y = e.height - 0.02 }, e, .{ .smile = 0 }, 0.002);
    const b = faceDecal(.{ .x = 0.5 - e.spacing, .y = e.height - 0.02 }, e, .{ .smile = 0 }, 0.002);
    try std.testing.expect(a.alpha > 0.99);
    try std.testing.expectApproxEqAbs(a.color.b, b.color.b, 0.05);
}
