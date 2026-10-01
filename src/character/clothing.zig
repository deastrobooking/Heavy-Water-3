//! Clothing generation.
//!
//! * Shells: select body triangles by region/coverage, extrude along normals
//!   by a per-layer offset. The garment inherits the body's skin weights, so
//!   it deforms identically and layer order == offset order (no clipping).
//! * Skirts: a lofted cone with pleats, driven by a ring of spring-bone
//!   chains that collide with the legs.

const std = @import("std");
const m = @import("math.zig");
const curve = @import("curve.zig");
const mesh_mod = @import("mesh.zig");
const skel_mod = @import("skeleton.zig");
const loft_mod = @import("loft.zig");
const spec_mod = @import("spec.zig");
const body = @import("body.zig");
const spring = @import("spring.zig");

const Vec3 = m.Vec3;
const Mesh = mesh_mod.Mesh;
const Vertex = mesh_mod.Vertex;
const Region = mesh_mod.Region;
const Material = mesh_mod.Material;
const Skeleton = skel_mod.Skeleton;
const Joint = skel_mod.Joint;
const GarmentSpec = spec_mod.GarmentSpec;
const Allocator = std.mem.Allocator;

/// Offset per layer (meters). Thin enough to read as fabric, thick enough
/// to win the depth test at typical camera distances.
pub const layer_step: f32 = 0.0045;

/// Signed coverage of a body vertex by garment `g`: > 0 covered, < 0 not.
/// Continuous where a cut is continuous (sleeve length, hem height, neckline)
/// so `buildShell` can clip triangles along the zero crossing for clean,
/// stair-free hems. `uv.y` is the loft parameter along limbs
/// (0 at shoulder/hip, 1 at wrist/ankle).
pub fn coverage(g: GarmentSpec, v: Vertex, lm: body.Landmarks) f32 {
    const t = v.uv.y;
    const B = lm.B;
    const y = v.pos.y;
    const yes: f32 = 1;
    const no: f32 = -1;
    const top_hem = y - (lm.waist_y - 0.30 * B); // tops end below the waist
    const val: f32 = switch (g.coverage) {
        .tshirt => switch (v.region) {
            .chest, .belly => yes,
            .hips => top_hem,
            .upper_arm_l, .upper_arm_r => 0.30 - t,
            else => no,
        },
        .long_sleeve => switch (v.region) {
            .chest, .belly => yes,
            .hips => top_hem,
            .upper_arm_l, .upper_arm_r, .lower_arm_l, .lower_arm_r => 0.95 - t,
            else => no,
        },
        .tank => switch (v.region) {
            .chest, .belly => yes,
            .hips => top_hem,
            else => no,
        },
        .shorts => switch (v.region) {
            .hips => yes,
            .belly => lm.waist_y + 0.05 * B - y,
            .thigh_l, .thigh_r => 0.24 - t,
            else => no,
        },
        .leggings => switch (v.region) {
            .hips => yes,
            .belly => lm.waist_y + 0.05 * B - y,
            .thigh_l, .thigh_r, .shin_l, .shin_r => 0.97 - t,
            else => no,
        },
        .thigh_highs => switch (v.region) {
            .thigh_l, .thigh_r => t - 0.26,
            .shin_l, .shin_r, .foot_l, .foot_r => yes,
            else => no,
        },
        .shoes => switch (v.region) {
            .foot_l, .foot_r => yes,
            .shin_l, .shin_r => t - 0.93,
            else => no,
        },
        .gloves => switch (v.region) {
            .hand_l, .hand_r => yes,
            .lower_arm_l, .lower_arm_r => t - 0.88,
            else => no,
        },
        // Armor: limb plates stop short of the joints so elbows and knees stay free.
        // One continuous lower edge just below the waist across belly and hips, with the
        // abdomen bands spaced over the whole span so no band ends at a region border.
        .cuirass => switch (v.region) {
            .chest => yes,
            .belly, .hips => @min(y - (lm.waist_y - 0.04 * B), segment(g.segments, (lm.shoulder_y - y) / (lm.shoulder_y - lm.waist_y + 0.04 * B))),
            else => no,
        },
        .pauldrons => switch (v.region) {
            .upper_arm_l, .upper_arm_r => @min(0.34 - t, segment(g.segments, t / 0.34)),
            else => no,
        },
        .vambraces => switch (v.region) {
            .lower_arm_l, .lower_arm_r => @min(@min(t - 0.10, 0.90 - t), segment(g.segments, (t - 0.10) / 0.80)),
            else => no,
        },
        .gauntlets => switch (v.region) {
            .hand_l, .hand_r => yes,
            .lower_arm_l, .lower_arm_r => t - 0.84,
            else => no,
        },
        // A continuous cut just above the waist (not the region border) keeps the top edge smooth.
        .faulds => switch (v.region) {
            .belly, .hips => @min(lm.waist_y + 0.03 * B - y, segment(g.segments, (lm.waist_y + 0.03 * B - y) / (0.30 * B))),
            .thigh_l, .thigh_r => 0.16 - t,
            else => no,
        },
        .cuisses => switch (v.region) {
            .thigh_l, .thigh_r => @min(@min(t - 0.20, 0.86 - t), segment(g.segments, (t - 0.20) / 0.66)),
            else => no,
        },
        .greaves => switch (v.region) {
            .shin_l, .shin_r => @min(@min(t - 0.08, 0.90 - t), segment(g.segments, (t - 0.08) / 0.82)),
            else => no,
        },
        .sabatons => switch (v.region) {
            .foot_l, .foot_r => yes,
            .shin_l, .shin_r => t - 0.90,
            else => no,
        },
        .skirt => no,
    };
    if (v.region == .chest and val > 0) return @min(val, neckline(g.neckline, v.pos, lm));
    return val;
}

/// Splits a 0..1 span into `n` plates with gaps between them: > 0 on a plate, < 0 in a gap.
/// Continuous, so `buildShell` clips plate edges as smooth curves like any hem.
fn segment(n: u8, s: f32) f32 {
    if (n <= 1) return 1;
    const gap: f32 = 0.035;
    const f = @as(f32, @floatFromInt(n)) * std.math.clamp(s, 0, 0.9999);
    const local = f - @floor(f);
    return @min(local - gap, 1 - gap - local) / @as(f32, @floatFromInt(n));
}

pub fn covers(g: GarmentSpec, v: Vertex, lm: body.Landmarks) bool {
    return coverage(g, v, lm) > 0;
}

/// Signed neckline test (> 0 = covered).
fn neckline(n: spec_mod.Neckline, p: Vec3, lm: body.Landmarks) f32 {
    const B = lm.B;
    const base = lm.shoulder_y - 0.02 * B;
    // horizontal distance from the neck axis
    const r = @sqrt(p.x * p.x + (p.z + 0.07 * B) * (p.z + 0.07 * B));
    const crew = @max(base - p.y, r - 0.25 * B);
    return switch (n) {
        .high => 1,
        .crew => crew,
        .v => blk: {
            // V dips down the front center
            const front = m.smoothstep(-0.05 * B, 0.15 * B, p.z);
            const half_w = 0.26 * B;
            const v_depth = 0.40 * B * @max(0, 1 - @abs(p.x) / half_w);
            const base_v = base - v_depth;
            const v_cut = @max(base_v - p.y, @max((0.5 - front) * B, @abs(p.x) - half_w));
            break :blk @min(crew, v_cut);
        },
    };
}

fn materialFor(cov: spec_mod.Coverage) Material {
    return switch (cov) {
        .tshirt, .long_sleeve, .tank => .cloth_top,
        .shorts, .leggings, .thigh_highs, .skirt => .cloth_bottom,
        .shoes => .shoes,
        .gloves => .accent,
        .cuirass, .pauldrons, .vambraces, .gauntlets, .faulds, .cuisses, .greaves, .sabatons => .armor,
    };
}

/// Build an offset shell garment from `body_mesh` (which must have normals).
/// Triangles straddling a coverage boundary are clipped along it, so hems,
/// cuffs and necklines are smooth curves rather than triangle staircases.
pub fn buildShell(gpa: Allocator, out: *Mesh, body_mesh: *const Mesh, g: GarmentSpec, lm: body.Landmarks) !void {
    const bv = body_mesh.vertices.items;
    const none = std.math.maxInt(u32);
    const remap = try gpa.alloc(u32, bv.len);
    defer gpa.free(remap);
    @memset(remap, none);
    const cov = try gpa.alloc(f32, bv.len);
    defer gpa.free(cov);
    for (bv, cov) |v, *c| c.* = coverage(g, v, lm);
    // cut vertices shared by neighbouring triangles: keyed by sorted edge
    var cuts: std.AutoHashMapUnmanaged([2]u32, u32) = .empty;
    defer cuts.deinit(gpa);

    const offset = @as(f32, @floatFromInt(g.layer)) * layer_step + g.looseness;
    const mat = materialFor(g.coverage);
    const base = out.vertexCount();

    const Emit = struct {
        gpa: Allocator,
        out: *Mesh,
        bv: []const Vertex,
        cov: []const f32,
        remap: []u32,
        cuts: *std.AutoHashMapUnmanaged([2]u32, u32),
        offset: f32,
        mat: Material,
        shoes: bool,
        /// Hard armor: rigid binding and a domed plate profile.
        hard: bool,
        bulge: f32,

        fn finishVertex(e: @This(), v0: Vertex, inside: f32) Vertex {
            var v = v0;
            // Plates dome toward their centers; rims (coverage ~0) sit at the base offset.
            const dome = if (e.hard) e.bulge * m.smoothstep(0, 0.12, inside) else 0;
            v.pos = v.pos.addScaled(v.normal, e.offset + dome);
            if (e.hard) {
                // Bind to the single most influential joint so the plate never stretches.
                var best: usize = 0;
                for (v.weights, 0..) |w, k| if (w > v.weights[best]) {
                    best = k;
                };
                v.joints = .{ v.joints[best], 0, 0, 0 };
                v.weights = .{ 1, 0, 0, 0 };
            }
            if (e.shoes) v.pos.y = @max(v.pos.y, 0.0); // flat sole
            v.region = .garment;
            v.material = e.mat;
            return v;
        }
        fn corner(e: @This(), vi: u32) !u32 {
            if (e.remap[vi] == std.math.maxInt(u32)) e.remap[vi] = try e.out.addVertex(e.gpa, e.finishVertex(e.bv[vi], e.cov[vi]));
            return e.remap[vi];
        }
        /// Vertex where coverage crosses zero on edge (inside, outside).
        fn cut(e: @This(), inside: u32, outside: u32) !u32 {
            const key = if (inside < outside) [2]u32{ inside, outside } else [2]u32{ outside, inside };
            const gop = try e.cuts.getOrPut(e.gpa, key);
            if (gop.found_existing) return gop.value_ptr.*;
            const a = e.bv[inside];
            const b = e.bv[outside];
            const ca = e.cov[inside];
            const cb = e.cov[outside];
            const t = m.saturate(ca / (ca - cb));
            var v = a; // skin weights from the covered side
            v.pos = a.pos.lerp(b.pos, t);
            v.normal = a.normal.lerp(b.normal, t).normalize();
            v.uv = .{ .x = m.lerp(a.uv.x, b.uv.x, t), .y = m.lerp(a.uv.y, b.uv.y, t) };
            gop.value_ptr.* = try e.out.addVertex(e.gpa, e.finishVertex(v, 0));
            return gop.value_ptr.*;
        }
    };
    const e: Emit = .{ .gpa = gpa, .out = out, .bv = bv, .cov = cov, .remap = remap, .cuts = &cuts, .offset = offset, .mat = mat, .shoes = g.coverage == .shoes or g.coverage == .sabatons, .hard = g.hard, .bulge = g.bulge };

    var i: usize = 0;
    const idx = body_mesh.indices.items;
    while (i + 2 < idx.len) : (i += 3) {
        const tri = [3]u32{ idx[i], idx[i + 1], idx[i + 2] };
        var n_in: u32 = 0;
        for (tri) |vi| n_in += @intFromBool(cov[vi] > 0);
        if (n_in == 0) continue;
        if (n_in == 3) {
            try out.addTri(gpa, try e.corner(tri[0]), try e.corner(tri[1]), try e.corner(tri[2]));
            continue;
        }
        // rotate so the lone vertex (in when n_in == 1, out when n_in == 2) is first,
        // preserving winding
        var r: usize = 0;
        for (0..3) |k| {
            const inside = cov[tri[k]] > 0;
            if ((n_in == 1 and inside) or (n_in == 2 and !inside)) r = k;
        }
        const a = tri[r];
        const b = tri[(r + 1) % 3];
        const c = tri[(r + 2) % 3];
        if (n_in == 1) {
            // keep the small corner triangle at a
            try out.addTri(gpa, try e.corner(a), try e.cut(a, b), try e.cut(a, c));
        } else {
            // a is outside: keep the quad b, c, cut(c,a), cut(b,a)
            const ab = try e.cut(b, a);
            const ac = try e.cut(c, a);
            try out.addTri(gpa, ab, try e.corner(b), try e.corner(c));
            try out.addTri(gpa, ab, try e.corner(c), ac);
        }
    }
    try thickenHems(gpa, out, base, layer_step * (if (g.hard) @as(f32, 0.9) else 0.45));
    computeNormalsRange(out, base);
}

/// Push open-boundary (hem/cuff) vertices slightly outward so cuffs and
/// collars read as a thicker rolled edge under toon shading + outlines.
fn thickenHems(gpa: Allocator, mesh: *Mesh, first_vertex: u32, amount: f32) !void {
    var edges: std.AutoHashMapUnmanaged([2]u32, u8) = .empty;
    defer edges.deinit(gpa);
    const idx = mesh.indices.items;
    var i: usize = 0;
    while (i + 2 < idx.len) : (i += 3) {
        if (idx[i] < first_vertex) continue;
        for (0..3) |k| {
            const a = idx[i + k];
            const b = idx[i + (k + 1) % 3];
            const key = if (a < b) [2]u32{ a, b } else [2]u32{ b, a };
            const gop = try edges.getOrPut(gpa, key);
            if (!gop.found_existing) gop.value_ptr.* = 0;
            gop.value_ptr.* +|= 1;
        }
    }
    var moved = try std.DynamicBitSetUnmanaged.initEmpty(gpa, mesh.vertices.items.len);
    defer moved.deinit(gpa);
    var it = edges.iterator();
    while (it.next()) |e| {
        if (e.value_ptr.* != 1) continue; // boundary edges are used exactly once
        for (e.key_ptr.*) |vi| {
            if (moved.isSet(vi)) continue;
            moved.set(vi);
            const v = &mesh.vertices.items[vi];
            v.pos = v.pos.addScaled(v.normal, amount);
        }
    }
}

fn computeNormalsRange(mesh: *Mesh, first_vertex: u32) void {
    const vs = mesh.vertices.items;
    for (vs[first_vertex..]) |*v| v.normal = Vec3.zero;
    const idx = mesh.indices.items;
    var i: usize = 0;
    while (i + 2 < idx.len) : (i += 3) {
        if (idx[i] < first_vertex) continue;
        const a = idx[i];
        const b = idx[i + 1];
        const c = idx[i + 2];
        const n = vs[b].pos.sub(vs[a].pos).cross(vs[c].pos.sub(vs[a].pos));
        vs[a].normal = vs[a].normal.add(n);
        vs[b].normal = vs[b].normal.add(n);
        vs[c].normal = vs[c].normal.add(n);
    }
    for (vs[first_vertex..]) |*v| v.normal = v.normal.normalizeOr(Vec3.unit_y);
}

/// Duplicate a vertex range as an inward-facing back side (for single-surface
/// cloth like skirts so the inside renders when seen from below).
pub fn addBackside(gpa: Allocator, mesh: *Mesh, first_vertex: u32, first_index: usize, inset: f32) !void {
    const vcount = mesh.vertexCount() - first_vertex;
    const base = mesh.vertexCount();
    try mesh.vertices.ensureUnusedCapacity(gpa, vcount);
    for (first_vertex..first_vertex + vcount) |i| {
        var v = mesh.vertices.items[i];
        v.pos = v.pos.addScaled(v.normal, -inset);
        v.normal = v.normal.neg();
        mesh.vertices.appendAssumeCapacity(v);
    }
    const icount = mesh.indices.items.len - first_index;
    try mesh.indices.ensureUnusedCapacity(gpa, icount);
    var i: usize = first_index;
    while (i < first_index + icount) : (i += 3) {
        const a = mesh.indices.items[i] - first_vertex + base;
        const b = mesh.indices.items[i + 1] - first_vertex + base;
        const c = mesh.indices.items[i + 2] - first_vertex + base;
        mesh.indices.appendSliceAssumeCapacity(&.{ a, c, b });
    }
}

// ---------------------------------------------------------------- skirt
pub const skirt_chain_count = 10;
pub const skirt_chain_joints = 4;

/// Polar "envelope" of a mesh around the vertical axis: max radius per
/// (height, azimuth) bin. Lets draped garments (skirts, coats, capes) fit
/// whatever is underneath — glutes, bust, inner layers — instead of
/// trusting an analytic body shape.
pub const RadialFit = struct {
    pub const ny = 32;
    pub const na = 64;
    y0: f32,
    y1: f32,
    r: [ny][na]f32,

    fn binA(ang: f32) f32 {
        return @mod(ang / m.tau + 1.0, 1.0) * na;
    }

    /// `max_r` rejects far-away parts (arms hanging beside the hips).
    pub fn build(fit: *const Mesh, y0: f32, y1: f32, max_r: f32) RadialFit {
        var f: RadialFit = .{ .y0 = y0, .y1 = y1, .r = @splat(@splat(0)) };
        for (fit.vertices.items) |v| {
            switch (v.region) {
                .upper_arm_l, .lower_arm_l, .hand_l, .upper_arm_r, .lower_arm_r, .hand_r, .hair, .head, .face => continue,
                else => {},
            }
            if (v.pos.y < y0 or v.pos.y > y1) continue;
            const r = @sqrt(v.pos.x * v.pos.x + v.pos.z * v.pos.z);
            if (r > max_r) continue;
            const iy: usize = @intFromFloat(@round((v.pos.y - y0) / (y1 - y0) * (ny - 1)));
            const ia: usize = @as(usize, @intFromFloat(@floor(binA(std.math.atan2(v.pos.x, v.pos.z))))) % na;
            f.r[iy][ia] = @max(f.r[iy][ia], r);
        }
        // dilate one bin in each direction (fills gaps between sparse verts)
        var d = f.r;
        for (0..ny) |iy| for (0..na) |ia| {
            var mx: f32 = 0;
            for ([_]i32{ -1, 0, 1 }) |dy| for ([_]i32{ -1, 0, 1 }) |da| {
                const yy = @as(i32, @intCast(iy)) + dy;
                if (yy < 0 or yy >= ny) continue;
                const aa: usize = @intCast(@mod(@as(i32, @intCast(ia)) + da, na));
                mx = @max(mx, f.r[@intCast(yy)][aa]);
            };
            d[iy][ia] = mx;
        };
        // hanging cloth never tucks back in below a bulge: monotone toward the hem
        var iy: usize = ny - 1;
        while (iy > 0) {
            iy -= 1;
            for (0..na) |ia| d[iy][ia] = @max(d[iy][ia], d[iy + 1][ia]);
        }
        f.r = d;
        return f;
    }

    pub fn sample(f: *const RadialFit, y: f32, ang: f32) f32 {
        const fy = m.clamp((y - f.y0) / (f.y1 - f.y0), 0, 1) * (ny - 1);
        const iy: usize = @min(@as(usize, @intFromFloat(@floor(fy))), ny - 2);
        const ty = fy - @as(f32, @floatFromInt(iy));
        const fa = binA(ang);
        const ia: usize = @as(usize, @intFromFloat(@floor(fa))) % na;
        const ib = (ia + 1) % na;
        const ta = fa - @floor(fa);
        const r0 = m.lerp(f.r[iy][ia], f.r[iy][ib], ta);
        const r1 = m.lerp(f.r[iy + 1][ia], f.r[iy + 1][ib], ta);
        return m.lerp(r0, r1, ty);
    }
};

const SkirtCtx = struct {
    fit: *const RadialFit,
    clearance: f32,
    y_top: f32,
    y_bot: f32,
    ys: [4]f32,
    a: [4]f32,
    b: [4]f32,
    pleats: f32,
    pleat_depth: f32,
    /// chain joint ids: [chain][joint along length]
    chain: [skirt_chain_count][skirt_chain_joints]u16,

    fn yAt(c: *const SkirtCtx, t: f32) f32 {
        return m.lerp(c.y_top, c.y_bot, t);
    }
    pub fn section(c: *const SkirtCtx, t: f32) loft_mod.Section {
        const y = c.yAt(t);
        return .{ .a = curve.spline1D(&c.ys, &c.a, y), .b = curve.spline1D(&c.ys, &c.b, y), .n = 2.2 };
    }
    pub fn displace(c: *const SkirtCtx, t: f32, theta: f32, p0: Vec3, fr: curve.Frame) Vec3 {
        var p = p0;
        // never pass inside what's underneath (body + inner layers)
        const r_xz = @sqrt(p.x * p.x + p.z * p.z);
        const r_need = c.fit.sample(p.y, std.math.atan2(p.x, p.z)) + c.clearance;
        if (r_xz < r_need and r_xz > 1e-5) {
            const k = r_need / r_xz;
            p.x *= k;
            p.z *= k;
        }
        if (c.pleats < 1) return p;
        // triangle wave -> crisp knife pleats; depth grows from waist to hem
        const w = @abs(@mod(theta / m.tau * c.pleats, 1.0) * 2 - 1) * 2 - 1;
        const radial = p.sub(fr.origin).normalizeOr(Vec3.unit_z);
        return p.addScaled(radial, w * c.pleat_depth * m.smoothstep(0.0, 0.35, t));
    }
    pub fn skin(_: *const SkirtCtx, _: f32, _: Vec3) mesh_mod.SkinBlend {
        return .{ .a = Joint.hips.idx() }; // overwritten in finish
    }
    pub fn finish(c: *const SkirtCtx, v: *Vertex, t: f32, _: f32) void {
        // angle around the body -> two nearest chains
        const ang = std.math.atan2(v.pos.x, v.pos.z); // 0 = front
        const cf = @mod(ang / m.tau + 1.0, 1.0) * @as(f32, skirt_chain_count);
        const ca: usize = @as(usize, @intFromFloat(@floor(cf))) % skirt_chain_count;
        const cb = (ca + 1) % skirt_chain_count;
        const wb_ang = cf - @floor(cf);
        // along length -> two nearest joints
        const lf = t * @as(f32, skirt_chain_joints - 1);
        const ja: usize = @min(@as(usize, @intFromFloat(@floor(lf))), skirt_chain_joints - 2);
        const wl = m.saturate(lf - @as(f32, @floatFromInt(ja)));
        v.joints = .{ c.chain[ca][ja], c.chain[ca][ja + 1], c.chain[cb][ja], c.chain[cb][ja + 1] };
        v.weights = .{ (1 - wb_ang) * (1 - wl), (1 - wb_ang) * wl, wb_ang * (1 - wl), wb_ang * wl };
        v.region = .garment;
        v.material = .cloth_bottom;
    }
};

/// Lofted pleated skirt + its spring-bone chains (added to `skel`/`chains`).
pub fn buildSkirt(
    gpa: Allocator,
    out: *Mesh,
    /// Everything already on the character (body + inner garments).
    underneath: *const Mesh,
    skel: *Skeleton,
    chains: *std.ArrayList(spring.Chain),
    colliders: *std.ArrayList(spring.Collider),
    g: GarmentSpec,
    lm: body.Landmarks,
    spec: spec_mod.CharacterSpec,
) !void {
    const H = lm.B; // body unit
    const off = @as(f32, @floatFromInt(g.layer)) * layer_step + g.looseness;
    const y_top = lm.waist_y + 0.06 * H;
    const y_bot = lm.waist_y - g.length * H;
    const hip_y = lm.crotch_y + 0.20 * (lm.shoulder_y - lm.crotch_y);
    const hip_a = lm.hip_half_width * 1.10 + off;
    const hip_b = 0.48 * H + off;
    const fit = try gpa.create(RadialFit);
    defer gpa.destroy(fit);
    fit.* = RadialFit.build(underneath, y_bot - 0.05, y_top + 0.02, hip_a * 1.6);
    var ctx: SkirtCtx = .{
        .fit = fit,
        .clearance = off + g.pleat_depth + 0.002,
        .y_top = y_top,
        .y_bot = y_bot,
        // spline keys must ascend: hem, hips, waist, top
        .ys = .{ y_bot, hip_y, lm.waist_y, y_top },
        .a = .{ hip_a * g.flare, hip_a, lm.waist_half_width + off + 0.006, lm.waist_half_width + off },
        .b = .{ hip_b * g.flare * 0.92, hip_b, lm.waist_half_depth + off + 0.006, lm.waist_half_depth + off },
        .pleats = @floatFromInt(g.pleats),
        .pleat_depth = g.pleat_depth,
        .chain = undefined,
    };

    // ---- spring chains: one per angle slot, joints from waist to hem
    for (0..skirt_chain_count) |ci| {
        const ang = @as(f32, @floatFromInt(ci)) / skirt_chain_count * m.tau;
        const dir = Vec3.init(@sin(ang), 0, @cos(ang));
        var parent: u16 = Joint.hips.idx();
        var joint_ids: [skirt_chain_joints]u16 = undefined;
        for (0..skirt_chain_joints) |k| {
            const t = @as(f32, @floatFromInt(k)) / @as(f32, skirt_chain_joints - 1);
            const sec = ctx.section(t);
            // radius of the superellipse-ish section at this angle (ellipse approx)
            const r_design = 1.0 / @sqrt((dir.x * dir.x) / (sec.a * sec.a) + (dir.z * dir.z) / (sec.b * sec.b));
            const r = @max(r_design, fit.sample(ctx.yAt(t), ang) + ctx.clearance);
            const pos = Vec3.init(dir.x * r, ctx.yAt(t), dir.z * r);
            const jid = try skel.addBone(gpa, "skirt", @intCast(parent), pos);
            joint_ids[k] = jid;
            parent = jid;
        }
        ctx.chain[ci] = joint_ids;
        var chain = try spring.Chain.init(gpa, skel, &joint_ids, .{
            .stiffness = 0.10,
            .damping = 0.10,
            .gravity_scale = 0.6,
            .radius = 0.012,
        });
        errdefer chain.deinit(gpa);
        try chains.append(gpa, chain);
    }

    const rows = spec.res(14, 6);
    const pts = try gpa.alloc(Vec3, rows);
    defer gpa.free(pts);
    for (pts, 0..) |*p, i| p.* = Vec3.init(0, m.lerp(y_top, y_bot, @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(rows - 1))), 0);
    const first_v = out.vertexCount();
    const first_i = out.indices.items.len;
    const cols = @max(spec.res(48, 16), @as(u32, g.pleats) * 6);
    // Loft runs top->bottom; loft winding is outward for any centerline direction.
    _ = try loft_mod.loft(gpa, out, pts, .{ .cols = cols, .ref_normal = Vec3.unit_x, .region = .garment, .material = .cloth_bottom }, &ctx);
    computeNormalsRange(out, first_v);
    try addBackside(gpa, out, first_v, first_i, 0.0015);

    // Spheres inside the skirt volume so long hair rests on the skirt instead
    // of passing through it (they sit inside the cloth, so skirt chains ignore them).
    const hips_rest = skel.rest_world.items[Joint.hips.idx()];
    for ([_]f32{ 0.45, 0.80 }) |t| {
        const sec = ctx.section(t);
        const center = Vec3.init(0, ctx.yAt(t), -0.02 * H);
        const off_local = center.sub(hips_rest);
        try colliders.append(gpa, .{ .a = Joint.hips.idx(), .b = Joint.hips.idx(), .radius = 0.85 * @min(sec.a, sec.b), .offset_a = off_local, .offset_b = off_local });
    }
}

/// Body colliders for spring chains (legs, hips, chest, head).
pub fn defaultColliders(lm: body.Landmarks) [9]spring.Collider {
    const H = lm.B; // body unit
    return .{
        .{ .a = Joint.thigh_l.idx(), .b = Joint.shin_l.idx(), .radius = 0.27 * H },
        .{ .a = Joint.thigh_r.idx(), .b = Joint.shin_r.idx(), .radius = 0.27 * H },
        .{ .a = Joint.shin_l.idx(), .b = Joint.foot_l.idx(), .radius = 0.17 * H },
        .{ .a = Joint.shin_r.idx(), .b = Joint.foot_r.idx(), .radius = 0.17 * H },
        .{ .a = Joint.hips.idx(), .b = Joint.hips.idx(), .radius = 0.45 * H, .offset_a = Vec3.init(0, -0.1 * H, -0.05 * H), .offset_b = Vec3.init(0, -0.1 * H, -0.05 * H) },
        .{ .a = Joint.chest.idx(), .b = Joint.chest.idx(), .radius = 0.48 * H },
        .{ .a = Joint.head.idx(), .b = Joint.head.idx(), .radius = 0.50 * lm.H, .offset_a = Vec3.init(0, 0.45 * lm.H, 0.06 * lm.H), .offset_b = Vec3.init(0, 0.45 * lm.H, 0.06 * lm.H) },
        .{ .a = Joint.upper_arm_l.idx(), .b = Joint.lower_arm_l.idx(), .radius = 0.14 * H },
        .{ .a = Joint.upper_arm_r.idx(), .b = Joint.lower_arm_r.idx(), .radius = 0.14 * H },
    };
}

test "shell inherits weights and sits outside the body" {
    const gpa = std.testing.allocator;
    const spec: spec_mod.CharacterSpec = .{ .detail = 0.6 };
    const lm = body.computeLandmarks(spec);
    var skel = try body.buildSkeleton(gpa, spec, lm);
    defer skel.deinit(gpa);
    var bm: Mesh = .{};
    defer bm.deinit(gpa);
    try body.buildBody(gpa, &bm, spec, lm, &skel);
    var shirt: Mesh = .{};
    defer shirt.deinit(gpa);
    try buildShell(gpa, &shirt, &bm, .{ .coverage = .long_sleeve, .layer = 1 }, lm);
    try std.testing.expect(shirt.vertices.items.len > 200);
    for (shirt.vertices.items) |v| {
        try std.testing.expect(v.material == .cloth_top);
        var s: f32 = 0;
        for (v.weights) |w| s += w;
        try std.testing.expectApproxEqAbs(@as(f32, 1), s, 1e-4);
    }
}

test "armor segments split a span into plates with gaps, continuously" {
    // One piece: always covered.
    try std.testing.expect(segment(0, 0.5) > 0 and segment(1, 0.99) > 0);
    // Two plates: covered mid-plate, uncovered at the seam and the ends.
    try std.testing.expect(segment(2, 0.25) > 0 and segment(2, 0.75) > 0);
    try std.testing.expect(segment(2, 0.5) < 0 and segment(2, 0.0) < 0);
    // Continuous across the seam (no jumps), so plate edges clip as smooth curves.
    var previous = segment(3, 0);
    var s: f32 = 0.001;
    while (s < 1) : (s += 0.001) {
        const v = segment(3, s);
        try std.testing.expect(@abs(v - previous) < 0.01);
        previous = v;
    }
}
