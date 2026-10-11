//! Anime hair: a scalp cap plus a few dozen tapered, ridged clumps routed
//! over a scalp ellipsoid, with spring-bone chains for the long parts.
//!
//! Clump paths are authored in "scalp space" (azimuth, elevation, height
//! above scalp) so they hug the head regardless of head shape, then switch
//! to free-hanging 3D once they leave the head.

const std = @import("std");
const m = @import("math.zig");
const curve = @import("curve.zig");
const mesh_mod = @import("mesh.zig");
const skel_mod = @import("skeleton.zig");
const loft_mod = @import("loft.zig");
const spec_mod = @import("spec.zig");
const body = @import("body.zig");
const spring = @import("spring.zig");
const hair_style = @import("hair_style.zig");
const hair_library = @import("hair_library.zig");

const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Vertex = mesh_mod.Vertex;
const Skeleton = skel_mod.Skeleton;
const Joint = skel_mod.Joint;
const Allocator = std.mem.Allocator;

pub const Scalp = struct {
    c: Vec3,
    r: Vec3,

    /// Point at azimuth `phi` (0 = front, + toward character's left),
    /// elevation `el` (radians, + up), lifted `h` meters off the surface.
    pub fn point(s: Scalp, phi: f32, el: f32, h: f32) Vec3 {
        const d = Vec3.init(@sin(phi) * @cos(el), @sin(el), @cos(phi) * @cos(el));
        const p = s.c.add(d.mul(s.r));
        const n = Vec3.init(d.x / s.r.x, d.y / s.r.y, d.z / s.r.z).normalize();
        return p.addScaled(n, h);
    }
    pub fn normal(s: Scalp, phi: f32, el: f32) Vec3 {
        const d = Vec3.init(@sin(phi) * @cos(el), @sin(el), @cos(phi) * @cos(el));
        return Vec3.init(d.x / s.r.x, d.y / s.r.y, d.z / s.r.z).normalize();
    }
    /// Elevation whose surface point has height `y`.
    pub fn elevationAt(s: Scalp, y: f32) f32 {
        return std.math.asin(m.clamp((y - s.c.y) / s.r.y, -1, 1));
    }
};

/// How a clump is bound to the skeleton.
const Rig = struct {
    /// Up to two chains blended by `w` (index into `chain_joints`), or none.
    a: ?usize = null,
    b: ?usize = null,
    w: f32 = 0,
    /// Clump parameter where hair leaves the head (head-only above).
    t_free: f32 = 1,
};

const Clump = struct {
    pts: [6]Vec3,
    width: f32,
    thickness: f32,
    /// Taper exponent: low = pointy spikes, high = blunt/rounded.
    taper: f32,
    /// Cross-section exponent at the tip (< 2 pinches into a ridge).
    pinch: f32 = 1.4,
    ref_normal: Vec3,
    rig: Rig = .{},
};

/// Chain bookkeeping during generation.
const ChainInfo = struct {
    joints: [16]u16,
    count: usize,
    /// Clump parameter of each chain joint (joint 0 == t_free).
    ts: [16]f32,
};

const HairCtx = struct {
    clump: *const Clump,
    chains: []const ChainInfo,
    pub fn section(c: *const HairCtx, t: f32) loft_mod.Section {
        const k = 1 - std.math.pow(f32, t, c.clump.taper);
        const swell = 0.8 + 0.2 * m.smoothstep(0, 0.25, t);
        const w = c.clump.width * k * swell;
        const th = c.clump.thickness * (0.55 + 0.45 * k) * swell;
        // n < 2 pinches the edges into a ridge: crisp clump silhouettes under cel shading
        return .{ .a = @max(th, 0.0008), .b = @max(w, 0.001), .n = m.lerp(1.9, c.clump.pinch, t) };
    }
    pub fn skin(_: *const HairCtx, _: f32, _: Vec3) mesh_mod.SkinBlend {
        return .{ .a = Joint.head.idx() };
    }
    pub fn finish(c: *const HairCtx, v: *Vertex, t: f32, _: f32) void {
        v.region = .hair;
        v.material = .hair;
        const rig = c.clump.rig;
        const ra = rig.a orelse return; // static
        const la = alongChain(c.chains[ra], t);
        if (rig.b) |rb| {
            const lb = alongChain(c.chains[rb], t);
            const w = rig.w;
            v.joints = .{ la.a, la.b, lb.a, lb.b };
            v.weights = .{ (1 - w) * (1 - la.wb), (1 - w) * la.wb, w * (1 - lb.wb), w * lb.wb };
        } else {
            la.apply(v);
        }
    }
};

/// Skin along [head, c0, c1, ...] with pivots [0, t0, t1, ...].
fn alongChain(ch: ChainInfo, t: f32) mesh_mod.SkinBlend {
    var joints: [17]u16 = undefined;
    var pivots: [17]f32 = undefined;
    joints[0] = Joint.head.idx();
    pivots[0] = 0;
    for (0..ch.count) |i| {
        joints[i + 1] = ch.joints[i];
        pivots[i + 1] = ch.ts[i];
    }
    return loft_mod.chainSkin(joints[0 .. ch.count + 1], pivots[0 .. ch.count + 1], t, 0.04);
}

fn samplePath(pts: []const Vec3, t: f32) Vec3 {
    var out: [65]Vec3 = undefined;
    curve.sampleCatmullRom(pts, &out);
    const f = t * 64;
    const i: usize = @min(@as(usize, @intFromFloat(@floor(f))), 63);
    return out[i].lerp(out[i + 1], f - @as(f32, @floatFromInt(i)));
}

// ---------------------------------------------------------------- paths
const Ctx = struct {
    s: Scalp,
    lm: body.Landmarks,
    spec: spec_mod.HairSpec,
    H: f32,
};

/// Back/side hair path at azimuth phi. `len_h` is total length below the chin in head units.
fn backPath(c: Ctx, phi: f32, lift: f32, len_h: f32, curl_in: f32) [6]Vec3 {
    const H = c.H;
    const v = c.spec.volume;
    const p0 = c.s.point(phi * 0.35, 1.25, 0.0);
    const p1 = c.s.point(phi * 0.85, 0.75, (0.02 + lift) * H * v);
    const p2 = c.s.point(phi, 0.0, (0.05 + lift) * H * v);
    const leave = c.s.point(phi, -0.55, (0.06 + lift) * H * v);
    // free fall: keep clear of neck/back by pushing z behind the torso
    const back_clear = -0.50 * H - lift * H;
    const y_end = c.lm.chin_y - len_h * H;
    const side = @sin(phi);
    var p4 = Vec3.init(leave.x * 1.05 + side * 0.04 * H, m.lerp(leave.y, y_end, 0.45), @min(leave.z, back_clear * @abs(@cos(phi))));
    var p5 = Vec3.init(leave.x * (1.0 - curl_in * 0.5) + side * 0.06 * H, y_end, @min(leave.z, back_clear * @abs(@cos(phi))) * (1 - curl_in * 0.3));
    if (c.spec.style == .short_spiky or c.spec.style == .mohawk or c.spec.style == .undercut or c.spec.style == .nova_spike or c.spec.style == .alien_crown or c.spec.style == .crew_cut or c.spec.style == .curly_fade) {
        // spiky: clumps leave the scalp and kick outward/back into points
        // spikes kick out mostly at the back; at the sides they hug the head
        const spike = c.spec.spikiness;
        const backness = m.smoothstep(1.6, 2.6, @min(@abs(phi), m.tau - @abs(phi)));
        if (c.spec.style == .undercut or c.spec.style == .crew_cut or c.spec.style == .curly_fade) {
            p4 = c.s.point(phi, -0.68, 0.035 * H * v);
            p5 = c.s.point(phi, -0.88, 0.025 * H * v);
        } else {
            const crest: f32 = if (c.spec.style == .mohawk) 0.45 else if (c.spec.style == .nova_spike) 2.2 else if (c.spec.style == .alien_crown) 1.8 else 1.0;
            p4 = c.s.point(phi, -0.40, (0.06 + 0.06 * spike * backness * crest) * H * v);
            p5 = c.s.point(phi * 1.03, m.lerp(-0.75, -0.50, backness), (0.05 + (0.06 + 0.12 * spike * crest) * backness) * H * v);
        }
    } else if (isCurlStyle(c.spec.style)) {
        // Repeated side-to-side turns through the hanging clumps give curls a springy outline.
        const amp = switch (c.spec.style) {
            .afro => 0.17 * H,
            .curly_coils, .long_curls => 0.14 * H,
            .curly_fade, .textured_crop => 0.07 * H,
            else => 0.11 * H,
        };
        const phase = phi * 3.0;
        p4 = Vec3.init(leave.x + @sin(phase + 2.4) * amp, m.lerp(leave.y, y_end, 0.46), leave.z - 0.035 * H + @cos(phase + 2.4) * amp * 0.38);
        p5 = Vec3.init(leave.x + @sin(phase + 4.8) * amp * 0.7, y_end, leave.z - 0.08 * H + @cos(phase + 4.8) * amp * 0.55);
    } else if (c.spec.style == .swept_back or c.spec.style == .side_part) {
        const sweep: f32 = if (c.spec.style == .swept_back) 0.15 else 0.09;
        p4 = Vec3.init(leave.x + sweep * H, leave.y + 0.12 * H, leave.z - 0.11 * H);
        p5 = Vec3.init(leave.x + sweep * 1.4 * H, y_end + 0.12 * H, leave.z - 0.15 * H);
    } else if (c.spec.style == .locs) {
        const sway = @sin(phi * 8) * 0.045 * H;
        p4 = Vec3.init(p4.x + sway, p4.y, p4.z - 0.025 * H);
        p5 = Vec3.init(p5.x - sway, p5.y, p5.z - 0.045 * H);
    } else if (len_h < 0.4) {
        // short hair: end just below where it leaves the head, curling in
        p4 = leave.lerp(c.s.point(phi, -0.9, 0.04 * H), 0.5);
        p5 = c.s.point(phi * (1 - 0.1 * curl_in), -1.05, (0.02 - curl_in * 0.02) * H);
    }
    return .{ p0, p1, p2, leave, p4, p5 };
}

fn bangPath(c: Ctx, phi: f32, tip_y: f32) [6]Vec3 {
    const H = c.H;
    const v = c.spec.volume;
    const el_tip = c.s.elevationAt(tip_y);
    // sweep away from the part
    const part = c.spec.part * 0.6;
    const away: f32 = if (phi > part) 1 else -1;
    return .{
        c.s.point(part + (phi - part) * 0.2, 1.30, 0.0),
        c.s.point(part + (phi - part) * 0.55, 1.0, 0.03 * H * v),
        c.s.point(phi * 0.95, 0.62, 0.05 * H * v),
        c.s.point(phi, 0.30, 0.055 * H * v),
        c.s.point(phi + away * 0.04, m.lerp(0.30, el_tip, 0.6), 0.05 * H * v),
        c.s.point(phi + away * 0.08, el_tip, 0.035 * H * v),
    };
}

// ---------------------------------------------------------------- build
pub fn buildHair(
    gpa: Allocator,
    out: *Mesh,
    skel: *Skeleton,
    chains_out: *std.ArrayList(spring.Chain),
    spec: spec_mod.CharacterSpec,
    lm: body.Landmarks,
) !void {
    const hs = spec.hair;
    if (hs.custom orelse hair_library.lookup(hs.style)) |def| {
        try buildFromDef(gpa, out, skel, chains_out, spec, lm, def.*);
        return;
    }
    const H = lm.H;
    const c: Ctx = .{ .s = .{ .c = lm.scalp_center, .r = lm.scalp_radii }, .lm = lm, .spec = hs, .H = H };
    var prng = std.Random.DefaultPrng.init(hs.seed);
    const rnd = prng.random();
    const jitter = struct {
        fn f(r: std.Random, amt: f32) f32 {
            return (r.float(f32) * 2 - 1) * amt;
        }
    }.f;

    try buildCap(gpa, out, c, spec);

    var clumps: std.ArrayList(Clump) = .empty;
    defer clumps.deinit(gpa);
    var chain_infos: std.ArrayList(ChainInfo) = .empty;
    defer chain_infos.deinit(gpa);

    const spiky = hs.spikiness;
    const taper_base = m.lerp(4.0, 1.5, spiky);
    const n_joints: usize = @min(hs.chain_joints, 15);

    const long_len: f32 = switch (hs.style) {
        .long_straight => hs.length,
        .long_curls => 1.25,
        .locs => 1.45,
        .layered_shag => 0.58,
        .swept_back, .side_part => 0.20,
        .twin_tails => 0.5,
        .ponytail => 0.12,
        .braids => 0.12,
        .curly => 0.62,
        .curly_coils => 0.34,
        .afro, .short_curly, .curly_fade, .textured_crop, .crew_cut => 0.08,
        .bun => 0.08,
        .bob => 0.1,
        .short_spiky, .undercut, .mohawk, .nova_spike, .alien_crown => 0.0,
        // data-driven styles never reach this procedural path (see `hair_library`)
        .spiky_hero, .widow_flame, .fringe_spikes, .super_flare, .flip_bob, .pilot_sweep, .big_fringe, .topknot, .spike_tail => 0.0,
    };
    const curl_in: f32 = if (hs.style == .bob) 1.0 else 0.15;

    // ---- shared back chains (blended by azimuth)
    const back_chain_phis = [_]f32{ m.pi - 1.3, m.pi - 0.65, m.pi, m.pi + 0.65, m.pi + 1.3 };
    const back_t_free: f32 = 0.55;
    var back_chain_first: ?usize = null;
    if (n_joints >= 2 and long_len >= 0.4) {
        back_chain_first = chain_infos.items.len;
        for (back_chain_phis) |phi| {
            const path = backPath(c, phi, 0.03, long_len, curl_in);
            try addChain(gpa, skel, chains_out, &chain_infos, &path, back_t_free, n_joints, hairParams(H, 1.0));
        }
    }

    // ---- back & side clumps (two layers: inner shorter, outer longer)
    const n_back: usize = if (hs.style == .afro or hs.style == .curly_coils or hs.style == .long_curls) 22 else 16;
    for (0..2) |layer| {
        const lift: f32 = if (layer == 0) 0.0 else 0.05;
        for (0..n_back) |i| {
            const u = (@as(f32, @floatFromInt(i)) + 0.5 * @as(f32, @floatFromInt(layer))) / @as(f32, @floatFromInt(n_back));
            const phi = m.lerp(1.05, m.tau - 1.05, u) + jitter(rnd, 0.04);
            const len_var = long_len * (1.0 - 0.18 * @as(f32, @floatFromInt(1 - layer))) + jitter(rnd, 0.12) * @min(long_len, 1);
            // sides (near the face) are shorter: frames the face
            const sideness = 1 - m.smoothstep(1.2, 2.2, @min(phi, m.tau - phi));
            const len_h = if (long_len >= 0.4) @max(0.45, len_var * (1 - 0.55 * sideness)) else long_len;
            const path = backPath(c, phi, lift, len_h, curl_in);
            var cl: Clump = .{
                .pts = path,
                .width = (m.tau - 2.1) / @as(f32, @floatFromInt(n_back)) * 0.5 * lm.scalp_radii.z * 2.4 * (1 + jitter(rnd, 0.15)) * (if (isCurlStyle(hs.style)) @as(f32, 1.28) else 1),
                .thickness = 0.035 * H * hs.volume * (if (isCurlStyle(hs.style) or hs.style == .locs) @as(f32, 1.25) else 1),
                .taper = taper_base * (1 + jitter(rnd, 0.2)),
                .ref_normal = c.s.normal(phi, 0.2),
            };
            if (back_chain_first) |first| {
                // nearest two back chains by azimuth
                const rel = m.clamp((phi - back_chain_phis[0]) / (back_chain_phis[4] - back_chain_phis[0]) * 4, 0, 4);
                const ia: usize = @min(@as(usize, @intFromFloat(@floor(rel))), 3);
                cl.rig = .{ .a = first + ia, .b = first + ia + 1, .w = rel - @as(f32, @floatFromInt(ia)), .t_free = back_t_free };
            }
            try clumps.append(gpa, cl);
        }
    }

    // ---- bangs
    const nb: usize = @max(hs.bang_count, 3);
    const brow_y = lm.chin_y + 0.60 * H;
    for (0..nb) |i| {
        const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(nb - 1));
        const phi = m.lerp(-1.0, 1.0, u) + jitter(rnd, 0.03);
        // center bangs a bit longer, sides shorter; spikiness adds variation
        const centered = 1 - @abs(u * 2 - 1);
        const tip_y = brow_y - 0.05 * H * centered + jitter(rnd, 0.04 * H * (0.5 + spiky));
        var bang = bangPath(c, phi, tip_y);
        if (isCurlStyle(hs.style)) {
            for (3..6) |j| {
                const t: f32 = @floatFromInt(j - 2);
                bang[j].x += @sin(t * 2.2 + phi * 4) * 0.055 * H;
                bang[j].z += @cos(t * 2.2 + phi * 4) * 0.025 * H;
            }
        }
        try clumps.append(gpa, .{
            .pts = bang,
            .width = 2.0 / @as(f32, @floatFromInt(nb)) * 0.5 * lm.scalp_radii.z * 2.1,
            .thickness = 0.03 * H * hs.volume,
            .taper = taper_base * 0.9,
            .ref_normal = c.s.normal(phi, 0.6),
        });
    }

    // ---- side locks framing the face (long-ish, own chains)
    if (hs.style != .short_spiky and hs.style != .undercut and hs.style != .mohawk and hs.style != .braids) {
        for ([_]f32{ 1, -1 }) |side| {
            const phi = 1.28 * side;
            const end_y = if (hs.style == .bob) lm.chin_y + 0.05 * H else lm.chin_y - 0.30 * H;
            const pts = [6]Vec3{
                c.s.point(phi * 0.5, 1.1, 0),
                c.s.point(phi * 0.85, 0.6, 0.03 * H),
                c.s.point(phi, 0.1, 0.045 * H),
                c.s.point(phi * 1.02, -0.35, 0.05 * H),
                Vec3.init(c.s.point(phi, -0.6, 0.05 * H).x, m.lerp(lm.chin_y + 0.2 * H, end_y, 0.5), 0.08 * H),
                Vec3.init(c.s.point(phi, -0.6, 0.04 * H).x * 0.97, end_y, 0.10 * H),
            };
            var cl: Clump = .{ .pts = pts, .width = 0.15 * H, .thickness = 0.03 * H, .taper = taper_base, .ref_normal = c.s.normal(phi, 0) };
            if (n_joints >= 2) {
                cl.rig = .{ .a = chain_infos.items.len, .t_free = 0.5 };
                try addChain(gpa, skel, chains_out, &chain_infos, &pts, 0.5, @min(n_joints, 4), hairParams(H, 0.8));
            }
            try clumps.append(gpa, cl);
        }
    }

    // ---- twin tails
    if (hs.style == .twin_tails or hs.style == .ponytail) {
        const tails: usize = if (hs.style == .twin_tails) 2 else 1;
        for (0..tails) |tail_index| {
            const side: f32 = if (hs.style == .twin_tails) (if (tail_index == 0) @as(f32, 1) else -1) else 0;
            const anchor = if (hs.style == .twin_tails) c.s.point(2.15 * side, 0.55, 0.05 * H) else c.s.point(m.pi, 0.78, 0.04 * H);
            const out_dir = if (hs.style == .twin_tails) Vec3.init(side, 0, -0.35).normalize() else Vec3.init(0.12, 0, -1).normalize();
            const tail_len = hs.length * H;
            const center = [6]Vec3{
                anchor,
                anchor.addScaled(out_dir, 0.12 * H).add(Vec3.init(0, 0.03 * H, 0)),
                anchor.addScaled(out_dir, 0.30 * H).add(Vec3.init(0, -0.10 * H, 0)),
                anchor.addScaled(out_dir, 0.38 * H).add(Vec3.init(0, -0.40 * tail_len, 0)),
                anchor.addScaled(out_dir, 0.33 * H).add(Vec3.init(0, -0.75 * tail_len, 0)),
                anchor.addScaled(out_dir, 0.22 * H).add(Vec3.init(0, -tail_len, 0)),
            };
            const ci = chain_infos.items.len;
            if (n_joints >= 2) try addChain(gpa, skel, chains_out, &chain_infos, &center, 0.08, n_joints, hairParams(H, 1.2));
            // 6 sub-clumps around the center path
            for (0..6) |k| {
                const a = @as(f32, @floatFromInt(k)) / 6.0 * m.tau;
                const offs = Vec3.init(0, @cos(a), @sin(a)).scale(0.07 * H);
                var pts: [6]Vec3 = undefined;
                for (center, 0..) |p, j| {
                    const spread: f32 = if (j == 0) 0.3 else if (j == 5) 0.5 else 1.0;
                    pts[j] = p.addScaled(offs, spread + jitter(rnd, 0.2));
                }
                pts[5] = pts[5].add(Vec3.init(jitter(rnd, 0.06 * H), jitter(rnd, 0.15 * H), jitter(rnd, 0.06 * H)));
                var cl: Clump = .{ .pts = pts, .width = 0.15 * H, .thickness = 0.05 * H, .taper = taper_base, .ref_normal = offs.normalize() };
                if (n_joints >= 2) cl.rig = .{ .a = ci, .t_free = 0.08 };
                try clumps.append(gpa, cl);
            }
        }
    }

    // Paired woven locks run down the chest. Alternating lateral crossings make each one read
    // as a braid at the same stylized scale as the surrounding hair clumps.
    if (hs.style == .braids) {
        for ([_]f32{ -1, 1 }) |side| {
            for (0..2) |strand| {
                var pts: [6]Vec3 = undefined;
                for (&pts, 0..) |*p, i| {
                    const t = @as(f32, @floatFromInt(i)) / 5.0;
                    const crossing = @sin(t * m.tau * 2 + @as(f32, @floatFromInt(strand)) * m.pi) * 0.065 * H;
                    const x = side * (0.23 * H + crossing);
                    const y = m.lerp(lm.chin_y + 0.12 * H, lm.chin_y - 0.96 * H, t);
                    const z = 0.10 * H + @cos(t * m.tau * 2 + @as(f32, @floatFromInt(strand)) * m.pi) * 0.025 * H;
                    p.* = Vec3.init(x, y, z);
                }
                try clumps.append(gpa, .{ .pts = pts, .width = 0.12 * H, .thickness = 0.045 * H, .taper = 1.5, .ref_normal = Vec3.init(side, 0, 1) });
            }
        }
    }

    // A compact coiled knot at the back of the crown gives the bun a distinct tied-up profile.
    if (hs.style == .bun) {
        const root = c.s.point(m.pi, 0.72, 0.05 * H);
        const center = root.add(Vec3.init(0, 0.12 * H, -0.20 * H));
        for (0..10) |i| {
            const a = @as(f32, @floatFromInt(i)) / 10.0 * m.tau;
            const radial = Vec3.init(@cos(a), @sin(a), -0.45).normalize();
            const pts = [6]Vec3{
                root,
                root.lerp(center, 0.35),
                center.add(radial.scale(0.04 * H)),
                center.add(radial.scale(0.14 * H)),
                center.add(radial.scale(0.20 * H)),
                center.add(radial.scale(0.10 * H)),
            };
            try clumps.append(gpa, .{ .pts = pts, .width = 0.11 * H, .thickness = 0.045 * H, .taper = 1.8, .ref_normal = radial });
        }
    }

    // ---- spiky crown: a few clumps that stand up and sweep back
    if (hs.style == .short_spiky or hs.style == .mohawk or hs.style == .nova_spike or hs.style == .alien_crown) {
        const spike_count: usize = if (hs.style == .nova_spike) 11 else if (hs.style == .alien_crown) 13 else 6;
        for (0..spike_count) |i| {
            const spread: f32 = if (hs.style == .mohawk) 0.28 else if (hs.style == .alien_crown) m.pi else 0.8;
            const u = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(spike_count - 1));
            const phi = m.lerp(-spread, spread, u) + m.pi + jitter(rnd, 0.1);
            const height_factor: f32 = if (hs.style == .nova_spike) 4.2 else if (hs.style == .alien_crown) 3.1 else if (hs.style == .mohawk) 1.5 else 1;
            const tip_lift = (0.06 + 0.10 * spiky) * H * height_factor;
            const sweep = if (hs.style == .nova_spike) 0.075 * H else if (hs.style == .alien_crown) 0.045 * H else 0;
            const spike_width: f32 = if (hs.style == .nova_spike) 0.22 else if (hs.style == .alien_crown) 0.17 else 0.20;
            try clumps.append(gpa, .{
                .pts = .{
                    c.s.point(phi * 0.2, 1.40, 0.015 * H),
                    c.s.point(phi * 0.5, 1.25, 0.04 * H),
                    c.s.point(phi * 0.8, 1.05, 0.08 * H),
                    c.s.point(phi, 0.85, 0.12 * H + tip_lift * 0.15),
                    c.s.point(phi, 0.70, 0.12 * H + tip_lift * 0.58),
                    c.s.point(phi * 1.05, 0.62, 0.12 * H + tip_lift).add(Vec3.init(@sin(phi) * sweep, 0, @cos(phi) * sweep)),
                },
                .width = spike_width * H,
                .thickness = 0.04 * H,
                .taper = 1.4,
                .ref_normal = c.s.normal(phi, 1.0),
            });
        }
    }

    // ---- crown fill + ahoge (the iconic antenna strand)
    for (0..5) |i| {
        const phi = m.lerp(-0.9, 0.9, @as(f32, @floatFromInt(i)) / 4) + m.pi;
        try clumps.append(gpa, .{
            .pts = .{
                c.s.point(0, 1.45, 0),
                c.s.point(phi * 0.3, 1.3, 0.02 * H),
                c.s.point(phi, 1.05, 0.04 * H),
                c.s.point(phi, 0.75, 0.05 * H),
                c.s.point(phi, 0.45, 0.04 * H),
                c.s.point(phi, 0.25, 0.02 * H),
            },
            .width = 0.20 * H,
            .thickness = 0.03 * H,
            .taper = taper_base,
            .ref_normal = Vec3.unit_y,
        });
    }
    if (hs.ahoge) {
        const root = c.s.point(0.25, 1.35, 0);
        const pts = [6]Vec3{
            root.add(Vec3.init(0, -0.02 * H, 0)),
            root.add(Vec3.init(0.01 * H, 0.10 * H, 0.02 * H)),
            root.add(Vec3.init(0.02 * H, 0.22 * H, 0.08 * H)),
            root.add(Vec3.init(0.03 * H, 0.27 * H, 0.17 * H)),
            root.add(Vec3.init(0.04 * H, 0.24 * H, 0.24 * H)),
            root.add(Vec3.init(0.05 * H, 0.17 * H, 0.28 * H)),
        };
        var cl: Clump = .{ .pts = pts, .width = 0.035 * H, .thickness = 0.022 * H, .taper = 1.3, .pinch = 2.0, .ref_normal = Vec3.unit_x };
        if (n_joints >= 2) {
            cl.rig = .{ .a = chain_infos.items.len, .t_free = 0.1 };
            try addChain(gpa, skel, chains_out, &chain_infos, &pts, 0.1, 3, .{ .stiffness = 0.35, .damping = 0.08, .gravity_scale = 0.2, .radius = 0.004 });
        }
        try clumps.append(gpa, cl);
    }

    // ---- loft every clump
    const rows = spec.res(16, 6);
    const cols = spec.res(10, 5);
    const line = try gpa.alloc(Vec3, rows);
    defer gpa.free(line);
    for (clumps.items) |*cl| {
        curve.sampleCatmullRom(&cl.pts, line);
        const ctx: HairCtx = .{ .clump = cl, .chains = chain_infos.items };
        _ = try loft_mod.loft(gpa, out, line, .{
            .cols = cols,
            .ref_normal = cl.ref_normal,
            .region = .hair,
            .material = .hair,
            .cap_start = .dome,
            .cap_end = .dome,
            .cap_rings = 2,
            .cap_length = 0.6,
        }, &ctx);
    }
    out.computeNormals();
}

/// The only place hair reads the head model: everything data-driven roots on this ellipsoid.
fn headFrom(lm: body.Landmarks) hair_style.Head {
    return .{ .center = lm.scalp_center, .radii = lm.scalp_radii, .H = lm.H, .chin_y = lm.chin_y, .half_width = lm.head_half_width };
}

/// Build a style from its clump data: a scalp cap with the style's hairline, then each clump
/// lofted from a root on the scalp along its authored path.
pub fn buildFromDef(
    gpa: Allocator,
    out: *Mesh,
    skel: *Skeleton,
    chains_out: *std.ArrayList(spring.Chain),
    spec: spec_mod.CharacterSpec,
    lm: body.Landmarks,
    def: hair_style.StyleDef,
) !void {
    try hair_style.validate(def);
    const head = headFrom(lm);
    const H = head.H;
    const hs = spec.hair;
    const adj: hair_style.Adjust = .{
        .spike = m.clamp(hs.spike_scale, 0.2, 2),
        .volume = m.clamp(hs.volume_scale, 0.4, 2),
        .length = m.clamp(hs.length_scale, 0.4, 2),
    };
    const girth = head.girth();
    const s: Scalp = .{ .c = head.center, .r = head.radii };
    try buildCapKeys(gpa, out, s, spec.res(36, 12), spec.res(14, 6), def.cap.hairline, def.cap.lift * H);

    var chain_infos: std.ArrayList(ChainInfo) = .empty;
    defer chain_infos.deinit(gpa);
    const n_joints: usize = @min(hs.chain_joints, 15);
    const rows = spec.res(16, 6);
    const cols = spec.res(10, 5);
    const line = try gpa.alloc(Vec3, rows);
    defer gpa.free(line);

    for (def.clumps) |def_clump| {
        const pair = [2]hair_style.ClumpDef{ def_clump, hair_style.mirrored(def_clump) };
        for (pair[0 .. if (def_clump.mirror) 2 else 1]) |cd| {
            var cl: Clump = .{
                .pts = hair_style.clumpPath(head, cd, adj),
                .width = cd.width * H * girth * adj.volume,
                .thickness = (if (cd.thickness > 0) cd.thickness else cd.width * 0.75) * H * girth * adj.volume,
                .taper = cd.taper,
                .pinch = 1.7,
                .ref_normal = head.normalAt(hair_style.Head.direction(cd.az, cd.el)),
            };
            if (cd.sway and n_joints >= 2) {
                cl.rig = .{ .a = chain_infos.items.len, .t_free = 0.3 };
                try addChain(gpa, skel, chains_out, &chain_infos, &cl.pts, 0.3, n_joints, hairParams(H, 1.0));
            }
            curve.sampleCatmullRom(&cl.pts, line);
            const ctx: HairCtx = .{ .clump = &cl, .chains = chain_infos.items };
            _ = try loft_mod.loft(gpa, out, line, .{
                .cols = cols,
                .ref_normal = cl.ref_normal,
                .region = .hair,
                .material = .hair,
                .cap_start = .dome,
                .cap_end = .dome,
                .cap_rings = 2,
                .cap_length = 0.6,
            }, &ctx);
        }
    }
    out.computeNormals();
}

fn hairParams(H: f32, weight: f32) spring.Params {
    return .{ .stiffness = 0.12 / weight, .damping = 0.10, .gravity_scale = 0.45 * weight, .radius = 0.02 * H };
}

/// Create skeleton joints along `path` from parameter `t_free` to 1, parented
/// to the head, and register a spring chain for them.
fn addChain(
    gpa: Allocator,
    skel: *Skeleton,
    chains_out: *std.ArrayList(spring.Chain),
    infos: *std.ArrayList(ChainInfo),
    path: []const Vec3,
    t_free: f32,
    n: usize,
    params: spring.Params,
) !void {
    var info: ChainInfo = .{ .joints = undefined, .count = n, .ts = undefined };
    var parent: u16 = Joint.head.idx();
    for (0..n) |k| {
        const t = m.lerp(t_free, 1.0, @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(n - 1)));
        const jid = try skel.addBone(gpa, "hair", @intCast(parent), samplePath(path, t));
        info.joints[k] = jid;
        info.ts[k] = t;
        parent = jid;
    }
    var chain = try spring.Chain.init(gpa, skel, info.joints[0..n], params);
    errdefer chain.deinit(gpa);
    try chains_out.append(gpa, chain);
    try infos.append(gpa, info);
}

/// Scalp cap: a partial ellipsoid down to an azimuth-dependent hairline,
/// so gaps between clumps never reveal the skull.
fn buildCap(gpa: Allocator, out: *Mesh, c: Ctx, spec: spec_mod.CharacterSpec) !void {
    var keys_el = [_]f32{ 0.62, 0.42, -0.12, -0.75, -0.95 };
    if (spec.hair.style == .undercut or spec.hair.style == .crew_cut or spec.hair.style == .curly_fade or spec.hair.style == .textured_crop) keys_el = .{ 0.62, 0.42, 0.34, -0.65, -0.92 };
    if (spec.hair.style == .mohawk or spec.hair.style == .nova_spike) keys_el = .{ 0.62, 0.20, -0.30, -0.88, -0.95 };
    if (spec.hair.style == .afro) keys_el = .{ 0.92, 0.72, 0.50, -0.18, -0.42 };
    const cap_lift = if (spec.hair.style == .afro) 0.11 * c.H else if (spec.hair.style == .alien_crown) 0.045 * c.H else 0.006 * c.H;
    try buildCapKeys(gpa, out, c.s, spec.res(36, 12), spec.res(14, 6), keys_el, cap_lift);
}

/// Cap ellipsoid down to the hairline `keys_el` (elevations at azimuth 0, 0.9, 1.6, 2.4, pi).
fn buildCapKeys(gpa: Allocator, out: *Mesh, s: Scalp, cols: usize, rows: usize, keys_el: [5]f32, cap_lift: f32) !void {
    const keys_phi = [_]f32{ 0, 0.9, 1.6, 2.4, m.pi };
    const first = out.vertexCount();
    for (0..rows) |r| {
        const rt = @as(f32, @floatFromInt(r + 1)) / @as(f32, @floatFromInt(rows));
        for (0..cols) |col| {
            const phi = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cols)) * m.tau;
            const ap = @min(phi, m.tau - phi);
            const el_min = curve.spline1D(&keys_phi, &keys_el, ap);
            const el = m.lerp(m.pi / 2.0, el_min, rt);
            const p = s.point(phi, el, cap_lift);
            _ = try out.addVertex(gpa, .{ .pos = p, .uv = .{ .x = phi / m.tau, .y = rt * 0.3 }, .region = .hair, .material = .hair, .joints = .{ Joint.head.idx(), 0, 0, 0 } });
        }
    }
    // ring order runs top->down, cols increase toward +X from front: stitch then flip as needed
    try out.stitchRings(gpa, first, @intCast(rows), @intCast(cols), true, true);
    const top = try out.addVertex(gpa, .{ .pos = s.point(0, m.pi / 2.0, cap_lift), .uv = .{ .x = 0.5, .y = 0 }, .region = .hair, .material = .hair, .joints = .{ Joint.head.idx(), 0, 0, 0 } });
    try out.capRing(gpa, first, @intCast(cols), top, false);
}

fn isCurlStyle(style: spec_mod.HairStyle) bool {
    return switch (style) {
        .curly, .short_curly, .curly_fade, .curly_coils, .afro, .long_curls, .textured_crop => true,
        else => false,
    };
}

test "hair builds for every style and stays above the shoulders except long hair" {
    const gpa = std.testing.allocator;
    inline for (.{ spec_mod.HairStyle.long_straight, .bob, .twin_tails, .short_spiky }) |style| {
        const spec: spec_mod.CharacterSpec = .{ .hair = .{ .style = style }, .detail = 0.6 };
        const lm = body.computeLandmarks(spec);
        var skel = try body.buildSkeleton(gpa, spec, lm);
        defer skel.deinit(gpa);
        var chains: std.ArrayList(spring.Chain) = .empty;
        defer {
            for (chains.items) |*ch| ch.deinit(gpa);
            chains.deinit(gpa);
        }
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try buildHair(gpa, &mesh, &skel, &chains, spec, lm);
        try std.testing.expect(mesh.vertices.items.len > 1000);
        const bb = mesh.bounds();
        if (style == .bob or style == .short_spiky) try std.testing.expect(bb.min.y > lm.shoulder_y - 0.1 * lm.H);
        for (mesh.vertices.items) |v| for (v.joints) |j| try std.testing.expect(j < skel.count());
    }
}

fn meshHash(mesh: *const Mesh) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (mesh.vertices.items) |v| {
        for ([_]f32{ v.pos.x, v.pos.y, v.pos.z }) |f| {
            h = (h ^ @as(u32, @bitCast(f))) *% 0x100000001b3;
        }
    }
    return h;
}

test "data-driven styles: finite, rooted on the scalp, bounded, skinned and all different" {
    const gpa = std.testing.allocator;
    var hashes: [hair_library.all.len]u64 = undefined;
    for (hair_library.all, 0..) |def, di| {
        const spec: spec_mod.CharacterSpec = .{ .hair = .{ .custom = &def, .chain_joints = 3 }, .detail = 0.6 };
        const lm = body.computeLandmarks(spec);
        var skel = try body.buildSkeleton(gpa, spec, lm);
        defer skel.deinit(gpa);
        var chains: std.ArrayList(spring.Chain) = .empty;
        defer {
            for (chains.items) |*ch| ch.deinit(gpa);
            chains.deinit(gpa);
        }
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try buildHair(gpa, &mesh, &skel, &chains, spec, lm);
        try std.testing.expect(mesh.vertices.items.len > 500);
        const head = headFrom(lm);
        for (mesh.vertices.items) |v| {
            try std.testing.expect(std.math.isFinite(v.pos.x) and std.math.isFinite(v.pos.y) and std.math.isFinite(v.pos.z));
            for (v.joints) |j| try std.testing.expect(j < skel.count());
            // nothing strays further than 3.5 head heights from the scalp center
            try std.testing.expect(v.pos.distance(head.center) < 3.5 * lm.H);
        }
        // every clump root sits on the scalp surface (within lift), none inside the skull
        const adj: hair_style.Adjust = .{};
        for (def.clumps) |cd| {
            const pts = hair_style.clumpPath(head, cd, adj);
            const r0 = head.radius(pts[0]);
            try std.testing.expect(r0 > 0.9 and r0 < 1.25);
            for (pts[1..]) |p| try std.testing.expect(head.radius(p) >= 1.03);
        }
        hashes[di] = meshHash(&mesh);
    }
    for (hashes, 0..) |a, i| for (hashes[i + 1 ..]) |b| try std.testing.expect(a != b);
}

test "style adjustments change the hair, and a head of a different width still fits" {
    const gpa = std.testing.allocator;
    const def = hair_library.lookup(.spiky_hero).?;
    var heights: [2]f32 = undefined;
    for ([_]f32{ 0.7, 1.3 }, 0..) |scale, i| {
        const spec: spec_mod.CharacterSpec = .{ .hair = .{ .custom = def, .spike_scale = scale, .length_scale = scale }, .detail = 0.6 };
        const lm = body.computeLandmarks(spec);
        var skel = try body.buildSkeleton(gpa, spec, lm);
        defer skel.deinit(gpa);
        var chains: std.ArrayList(spring.Chain) = .empty;
        defer chains.deinit(gpa);
        var mesh: Mesh = .{};
        defer mesh.deinit(gpa);
        try buildHair(gpa, &mesh, &skel, &chains, spec, lm);
        heights[i] = mesh.bounds().max.y;
    }
    try std.testing.expect(heights[1] > heights[0] + 0.01);

    var wide: spec_mod.CharacterSpec = .{ .hair = .{ .custom = def }, .detail = 0.6 };
    wide.body.head_width *= 1.3;
    const lm = body.computeLandmarks(wide);
    var skel = try body.buildSkeleton(gpa, wide, lm);
    defer skel.deinit(gpa);
    var chains: std.ArrayList(spring.Chain) = .empty;
    defer chains.deinit(gpa);
    var mesh: Mesh = .{};
    defer mesh.deinit(gpa);
    try buildHair(gpa, &mesh, &skel, &chains, wide, lm);
    const head = headFrom(lm);
    for (def.clumps) |cd| try std.testing.expect(@abs(head.radius(hair_style.clumpPath(head, cd, .{})[0]) - 1) < 0.25);
}
