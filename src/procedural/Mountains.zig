//! Mountain ranges: four seeded massifs on a ring 1.1–1.7 km from the hub, each a meandering
//! spine 1.4–2 km long with a peak of 160–260 m. Height is added to the base terrain along the
//! spine with a ridged crest and craggy shoulders, tapering at the range's ends and flanks.
//! Rivers cut passes: a range sinks to nothing within 40 m of a river lane, so water never
//! climbs over a mountain. Everything is evaluated in world space, so streamed chunks, physics
//! and the far panorama all agree.
const std = @import("std");
const Seed = @import("Seed.zig");
const Noise = @import("Noise.zig");

pub const count = 4;
pub const spine_points = 6;
/// No range reaches inside this distance of the hub (the city, nests and the air war).
pub const inner_clearance: f32 = 950;
/// Nothing beyond this distance from the hub belongs to a range.
pub const outer_reach: f32 = 2600;

pub const Range = struct {
    spine: [spine_points][2]f32,
    /// Peak height above the base terrain, and the half-width of the massif.
    peak: f32,
    half_width: f32,
    /// Spine bounds grown by the half-width, for quick rejection.
    lo: [2]f32,
    hi: [2]f32,
};

/// Where a point sits relative to a range: across distance from the spine and position along it.
pub const Place = struct { range: u8, across: f32, along: f32 };

/// Terrain sampling asks for the ranges millions of times, from several threads: each thread
/// keeps the last seed's ranges.
threadlocal var cached_seed: ?u64 = null;
threadlocal var cached: [count]Range = undefined;

/// The ranges for a seed (cheap: no terrain sampling).
pub fn ranges(seed: u64) [count]Range {
    if (cached_seed) |s| if (s == seed) return cached;
    cached = build(seed);
    cached_seed = seed;
    return cached;
}

fn build(seed: u64) [count]Range {
    var out: [count]Range = undefined;
    for (&out, 0..) |*r, i| {
        const s = Seed.mix(seed ^ (0x4d4f554e54 + @as(u64, i) * 0x9e37));
        const angle = (@as(f32, @floatFromInt(i)) + 0.15 + Seed.unit(s) * 0.5) * std.math.pi / 2.0;
        const distance = 1300 + Seed.unit(Seed.mix(s +% 1)) * 400;
        const center: [2]f32 = .{ @sin(angle) * distance, @cos(angle) * distance };
        // Roughly tangential to the hub, swung up to 30° either way.
        const heading = angle + std.math.pi / 2.0 + (Seed.unit(Seed.mix(s +% 2)) - 0.5) * 1.05;
        const length = 1400 + Seed.unit(Seed.mix(s +% 3)) * 600;
        const along: [2]f32 = .{ @sin(heading), @cos(heading) };
        const side: [2]f32 = .{ along[1], -along[0] };
        r.peak = 160 + Seed.unit(Seed.mix(s +% 4)) * 100;
        r.half_width = 230 + Seed.unit(Seed.mix(s +% 5)) * 90;
        r.lo = .{ std.math.inf(f32), std.math.inf(f32) };
        r.hi = .{ -std.math.inf(f32), -std.math.inf(f32) };
        for (&r.spine, 0..) |*p, k| {
            const t = @as(f32, @floatFromInt(k)) / (spine_points - 1) - 0.5;
            const sway = (Seed.unit(Seed.mix(s +% (10 + k))) - 0.5) * 260;
            p.* = .{ center[0] + along[0] * t * length + side[0] * sway, center[1] + along[1] * t * length + side[1] * sway };
            // Keep the range off the hub's ring: push spine points outward if needed.
            const d = @sqrt(p[0] * p[0] + p[1] * p[1]);
            const least = inner_clearance + r.half_width;
            if (d < least) p.* = .{ p[0] / d * least, p[1] / d * least };
            for (0..2) |a| {
                r.lo[a] = @min(r.lo[a], p[a] - r.half_width);
                r.hi[a] = @max(r.hi[a], p[a] + r.half_width);
            }
        }
    }
    return out;
}

/// The nearest range spine to (x, z), if within its half-width.
pub fn place(rs: *const [count]Range, x: f32, z: f32) ?Place {
    var best: ?Place = null;
    for (rs, 0..) |r, i| {
        if (x < r.lo[0] or x > r.hi[0] or z < r.lo[1] or z > r.hi[1]) continue;
        var nearest = std.math.inf(f32);
        var along: f32 = 0;
        for (0..spine_points - 1) |k| {
            const a = r.spine[k];
            const b = r.spine[k + 1];
            const ab: [2]f32 = .{ b[0] - a[0], b[1] - a[1] };
            const len2 = ab[0] * ab[0] + ab[1] * ab[1];
            const t = std.math.clamp(((x - a[0]) * ab[0] + (z - a[1]) * ab[1]) / len2, 0, 1);
            const dx = x - (a[0] + ab[0] * t);
            const dz = z - (a[1] + ab[1] * t);
            const d = @sqrt(dx * dx + dz * dz);
            if (d < nearest) {
                nearest = d;
                along = (@as(f32, @floatFromInt(k)) + t) / (spine_points - 1);
            }
        }
        if (nearest < r.half_width and (best == null or nearest / r.half_width < best.?.across / rs[best.?.range].half_width)) best = .{ .range = @intCast(i), .across = nearest, .along = along };
    }
    return best;
}

fn smooth(t: f32) f32 {
    const c = std.math.clamp(t, 0, 1);
    return c * c * (3 - 2 * c);
}

/// Ridged value noise in [0, 1]: sharp crests where the noise crosses its middle.
fn ridged(seed: u64, x: f32, z: f32) f32 {
    const n = 1 - @abs(Noise.value(seed, x, z) * 2 - 1);
    return n * n;
}

/// 0 on a river's centre line, rising to 1 by 140 m away: ranges open passes for rivers.
fn riverGap(seed: u64, x: f32, z: f32) f32 {
    const Hydrology = @import("Hydrology.zig");
    const lane: i64 = @intFromFloat(@round((z - Hydrology.lane_offset) / Hydrology.lane_spacing));
    const d = @abs(z - Hydrology.centerZ(seed, lane, x));
    return smooth((d - 40) / 100);
}

/// Mountain height to add at (x, z), and how far into a range the point is (0–1), for colour.
pub const Sample = struct { height: f32, influence: f32 };

pub fn sample(seed: u64, x: f32, z: f32) Sample {
    const r2 = x * x + z * z;
    if (r2 < inner_clearance * inner_clearance or r2 > outer_reach * outer_reach) return .{ .height = 0, .influence = 0 };
    if (cached_seed == null or cached_seed.? != seed) _ = ranges(seed);
    const rs = &cached;
    const at = place(rs, x, z) orelse return .{ .height = 0, .influence = 0 };
    const r = rs[at.range];
    const across = 1 - at.across / r.half_width;
    // The massif: a broad shoulder profile across, tapering toward the spine's ends.
    const ends = smooth(at.along / 0.18) * smooth((1 - at.along) / 0.18);
    const shoulder = smooth(across) * smooth(across * 1.6);
    const gap = riverGap(seed, x, z);
    const mass = shoulder * ends * gap;
    if (mass <= 0) return .{ .height = 0, .influence = 0 };
    const rseed = Seed.mix(seed ^ 0x52414e4745 ^ @as(u64, at.range));
    // Peaks and saddles along the crest, sharp ridges and crags on the flanks.
    const crest = 0.55 + 0.45 * ridged(rseed, x * 0.0035, z * 0.0035);
    const crags = ridged(rseed ^ 0x43524147, x * 0.013, z * 0.013) * 0.18 + Noise.value(rseed ^ 0x524f434b, x * 0.05, z * 0.05) * 0.04;
    return .{ .height = r.peak * mass * (crest + crags), .influence = smooth(mass * 1.5) };
}

pub fn height(seed: u64, x: f32, z: f32) f32 {
    return sample(seed, x, z).height;
}

/// Spacing and reach of the far panorama.
pub const panorama_spacing: f32 = 32;
pub const panorama_sink: f32 = 4;

/// The ranges as a coarse far mesh, so they stand on the horizon beyond the streamed terrain.
/// Every vertex sits a few metres under the lowest real ground around it, so wherever the
/// streamed terrain is drawn it covers this mesh. Only cells with mountain under them are kept.
pub fn panorama(allocator: std.mem.Allocator, seed: u64) !@import("../render/Mesh.zig") {
    const Mesh = @import("../render/Mesh.zig");
    const Biome = @import("Biome.zig");
    const n: usize = @intFromFloat(@ceil(outer_reach * 2 / panorama_spacing) + 1);
    const origin = -outer_reach;
    const heights = try allocator.alloc(f32, n * n);
    defer allocator.free(heights);
    const inside = try allocator.alloc(bool, n * n);
    defer allocator.free(inside);
    for (0..n) |k| for (0..n) |i| {
        const x = origin + @as(f32, @floatFromInt(i)) * panorama_spacing;
        const z = origin + @as(f32, @floatFromInt(k)) * panorama_spacing;
        var low = Noise.height(seed, x, z);
        const h = panorama_spacing / 2;
        for ([_][2]f32{ .{ h, 0 }, .{ -h, 0 }, .{ 0, h }, .{ 0, -h }, .{ h, h }, .{ -h, -h }, .{ h, -h }, .{ -h, h } }) |o| low = @min(low, Noise.height(seed, x + o[0], z + o[1]));
        heights[k * n + i] = low - panorama_sink;
        inside[k * n + i] = height(seed, x, z) > 0.5;
    };
    // Grow the kept area by two cells, so the panorama's edge lies on the foothills' base
    // ground rather than ending in mid-air on a slope.
    for (0..2) |_| {
        const was = try allocator.dupe(bool, inside);
        defer allocator.free(was);
        for (0..n) |k| for (0..n) |i| {
            if (was[k * n + i]) continue;
            if ((i > 0 and was[k * n + i - 1]) or (i + 1 < n and was[k * n + i + 1]) or (k > 0 and was[(k - 1) * n + i]) or (k + 1 < n and was[(k + 1) * n + i])) inside[k * n + i] = true;
        };
    }
    var vertices: std.ArrayList(Mesh.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    errdefer indices.deinit(allocator);
    const index_of = try allocator.alloc(u32, n * n);
    defer allocator.free(index_of);
    @memset(index_of, std.math.maxInt(u32));
    for (0..n - 1) |k| for (0..n - 1) |i| {
        if (!(inside[k * n + i] or inside[k * n + i + 1] or inside[(k + 1) * n + i] or inside[(k + 1) * n + i + 1])) continue;
        var corner: [4]u32 = undefined;
        for ([_][2]usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 0, 1 }, .{ 1, 1 } }, 0..) |o, c| {
            const gi = i + o[0];
            const gk = k + o[1];
            const at = gk * n + gi;
            if (index_of[at] == std.math.maxInt(u32)) {
                const x = origin + @as(f32, @floatFromInt(gi)) * panorama_spacing;
                const z = origin + @as(f32, @floatFromInt(gk)) * panorama_spacing;
                const hx = heights[gk * n + @min(gi + 1, n - 1)] - heights[gk * n + gi -| 1];
                const hz = heights[@min(gk + 1, n - 1) * n + gi] - heights[(gk -| 1) * n + gi];
                const nx = -hx / (2 * panorama_spacing);
                const nz = -hz / (2 * panorama_spacing);
                const inv = 1 / @sqrt(nx * nx + 1 + nz * nz);
                const y = heights[at];
                index_of[at] = @intCast(vertices.items.len);
                try vertices.append(allocator, .{ .position = .{ x, y, z }, .normal = .{ nx * inv, inv, nz * inv }, .uv = .{ x / 4, z / 4 }, .color = Biome.terrainColor(seed, x, z, y + panorama_sink, @sqrt(nx * nx + nz * nz)) });
            }
            corner[c] = index_of[at];
        }
        // Same split as the streamed terrain, facing up.
        try indices.appendSlice(allocator, &.{ corner[0], corner[2], corner[1], corner[1], corner[2], corner[3] });
    };
    const owned = try vertices.toOwnedSlice(allocator);
    errdefer allocator.free(owned);
    return .{ .vertices = owned, .indices = try indices.toOwnedSlice(allocator) };
}

test "the far panorama covers the ranges and stays under the real ground" {
    const seed: u64 = 0x4845415659;
    const m = try panorama(std.testing.allocator, seed);
    defer m.deinit(std.testing.allocator);
    try std.testing.expect(m.vertices.len > 1000);
    var i: usize = 0;
    while (i < m.vertices.len) : (i += 97) {
        const p = m.vertices[i].position;
        try std.testing.expect(p[1] <= Noise.height(seed, p[0], p[2]) - panorama_sink + 0.01);
    }
    // Every triangle faces up.
    var t: usize = 0;
    while (t < m.indices.len) : (t += 3 * 31) {
        const a = m.vertices[m.indices[t]].position;
        const b = m.vertices[m.indices[t + 1]].position;
        const c = m.vertices[m.indices[t + 2]].position;
        const ab: [3]f32 = .{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
        const ac: [3]f32 = .{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
        try std.testing.expect(ab[2] * ac[0] - ab[0] * ac[2] > 0);
    }
}

test "ranges stay clear of the hub, rise to real peaks, and open passes for rivers" {
    const seed: u64 = 0x4845415659;
    const rs = ranges(seed);
    var tallest: f32 = 0;
    for (rs) |r| {
        for (r.spine) |p| try std.testing.expect(@sqrt(p[0] * p[0] + p[1] * p[1]) >= inner_clearance + r.half_width - 0.5);
        // Sample the crest for its highest point.
        for (0..200) |k| {
            const t = @as(f32, @floatFromInt(k)) / 199 * (spine_points - 1);
            const i = @min(spine_points - 2, @as(usize, @intFromFloat(t)));
            const f = t - @as(f32, @floatFromInt(i));
            const x = r.spine[i][0] + (r.spine[i + 1][0] - r.spine[i][0]) * f;
            const z = r.spine[i][1] + (r.spine[i + 1][1] - r.spine[i][1]) * f;
            tallest = @max(tallest, height(seed, x, z));
        }
    }
    try std.testing.expect(tallest > 120);
    // The hub and the nest ring are untouched.
    for (0..64) |k| {
        const a = @as(f32, @floatFromInt(k)) / 64 * 2 * std.math.pi;
        try std.testing.expectEqual(@as(f32, 0), height(seed, @sin(a) * 900, @cos(a) * 900));
    }
    // On a river's centre line, nothing is added.
    const Hydrology = @import("Hydrology.zig");
    for (0..40) |k| {
        const x = -2500 + @as(f32, @floatFromInt(k)) * 125;
        try std.testing.expectEqual(@as(f32, 0), height(seed, x, Hydrology.centerZ(seed, 1, x)));
    }
}
