//! The sky city's skyline: steel-and-glass skyscrapers rising from the forest floor around and
//! through the district, plus one tower beside each tower plaza, joined to it by a walkable sky
//! lobby at deck level. Placement is seeded and validated. Towers keep clear of every road,
//! trunk spur, and plaza-to-plaza route a player could still bridge, as well as plazas, trunks,
//! the spawn area, and each other, so they shape the city without blocking any route through it.
const std = @import("std");
const R = @import("../physics/Rotation.zig");
const Seed = @import("Seed.zig");
const Terrain = @import("Terrain.zig");
const District = @import("District.zig");
const Bridges = @import("Bridges.zig");
const V = R.Vec3;

pub const max_buildings = 24;
pub const target_skyline = 18;
/// No tower within this distance of the new-game spawn.
pub const spawn_clearance: f32 = 110;
const spawn_xz: [2]f32 = .{ 0, -58 };

pub const Building = struct {
    /// Footprint centre at ground level.
    base: V = @splat(0),
    half: [2]f32 = .{ 0, 0 },
    /// Roof height (world y) of the main tier, and of the spire tip.
    roof: f32 = 0,
    spire: f32 = 0,
    tiers: u8 = 1,
    palette: u8 = 0,
    /// Tower plaza this one stands beside (sky lobby), if any.
    plaza: ?u8 = null,

    pub fn radius(self: Building) f32 {
        return @sqrt(self.half[0] * self.half[0] + self.half[1] * self.half[1]);
    }
    pub fn beacon(self: Building) V {
        return .{ self.base[0], self.spire, self.base[2] };
    }
};

const palettes = [_]struct { body: V, band: V, fin: V, glass: V }{
    .{ .body = .{ 0.20, 0.33, 0.38 }, .band = .{ 0.78, 0.82, 0.80 }, .fin = .{ 0.55, 0.62, 0.66 }, .glass = .{ 0.22, 0.59, 0.66 } },
    .{ .body = .{ 0.46, 0.30, 0.22 }, .band = .{ 0.20, 0.17, 0.15 }, .fin = .{ 0.72, 0.52, 0.32 }, .glass = .{ 0.30, 0.58, 0.62 } },
    .{ .body = .{ 0.82, 0.84, 0.82 }, .band = .{ 0.30, 0.60, 0.64 }, .fin = .{ 0.40, 0.74, 0.78 }, .glass = .{ 0.23, 0.64, 0.72 } },
    .{ .body = .{ 0.26, 0.28, 0.34 }, .band = .{ 0.60, 0.64, 0.70 }, .fin = .{ 0.85, 0.55, 0.30 }, .glass = .{ 0.24, 0.51, 0.62 } },
};

fn planar(a: V, b: V) f32 {
    return @sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[2] - b[2]) * (a[2] - b[2]));
}

fn segmentDistance(p: V, a: V, b: V) f32 {
    const d: V = .{ b[0] - a[0], 0, b[2] - a[2] };
    const q: V = .{ p[0] - a[0], 0, p[2] - a[2] };
    const t = std.math.clamp(R.dot(q, d) / @max(R.dot(d, d), 0.001), 0, 1);
    return R.length(R.sub(q, R.scale(d, t)));
}

/// Plaza-centre segments a tower must not stand on: roads, spurs, and every bridge a player
/// could still add between plazas.
pub fn corridors(layout: *const District.Layout, out: *[64][2]V) [][2]V {
    var n: usize = 0;
    for (layout.edges) |e| {
        out[n] = .{ layout.nodes[e.a].position, layout.nodes[e.b].position };
        n += 1;
    }
    for (layout.nodes, 0..) |node, i| if (node.tree) |t| if (t > 0) {
        const s = District.trunkSpur(layout, i);
        out[n] = .{ s.a, s.b };
        n += 1;
    };
    for (0..District.node_count) |a| for (a + 1..District.node_count) |b| {
        const edge: District.Edge = .{ .a = @intCast(a), .b = @intCast(b) };
        District.validateEdge(layout, edge, &layout.edges) catch continue;
        out[n] = .{ layout.nodes[a].position, layout.nodes[b].position };
        n += 1;
    };
    return out[0..n];
}

fn clear(layout: *const District.Layout, lanes: []const [2]V, placed: []const Building, b: Building, own_plaza: ?usize) bool {
    const r = b.radius();
    for (lanes) |c| {
        const margin: f32 = if (own_plaza != null) 4 else 10;
        if (segmentDistance(b.base, c[0], c[1]) < r + District.width / 2 + margin) return false;
    }
    for (layout.nodes, 0..) |node, i| {
        if (own_plaza == i) continue;
        if (planar(b.base, node.position) < District.plaza_radius + r + 12) return false;
    }
    for (layout.trees, 0..) |tree, i| if (planar(b.base, tree.position) < tree.radius + r + (if (i == 0) @as(f32, 60) else 30)) return false;
    if (planar(b.base, .{ spawn_xz[0], 0, spawn_xz[1] }) < spawn_clearance + r) return false;
    for (placed) |o| if (planar(b.base, o.base) < r + o.radius() + 14) return false;
    return true;
}

/// Seeded, validated towers: first one beside each tower plaza, then the skyline.
pub fn generate(layout: *District.Layout) void {
    var lane_buffer: [64][2]V = undefined;
    const lanes = corridors(layout, &lane_buffer);
    var h = Seed.mix(layout.seed ^ 0x534b594c);
    const Rand = struct {
        fn unit(state: *u64) f32 {
            state.* = Seed.mix(state.* +% 0x9E3779B97F4A7C15);
            return Seed.unit(state.*);
        }
    };
    var n: usize = 0;
    for (layout.nodes, 0..) |node, i| {
        if (node.kind != .tower) continue;
        // The bearing farthest from every other plaza and from the market bay.
        const market = R.normalize(R.sub(District.marketPosition(layout, i), node.position));
        var best: f32 = -2;
        var dir: V = .{ 1, 0, 0 };
        for (0..32) |k| {
            const a = @as(f32, @floatFromInt(k)) * 2 * std.math.pi / 32;
            const d: V = .{ @sin(a), 0, @cos(a) };
            var score: f32 = 1 - R.dot(d, market);
            for (layout.nodes, 0..) |other, j| if (j != i) {
                score = @min(score, 1 - R.dot(d, R.normalize(.{ other.position[0] - node.position[0], 0, other.position[2] - node.position[2] })));
            };
            if (score > best) {
                best = score;
                dir = d;
            }
        }
        const half = 8 + 3 * Rand.unit(&h);
        const at = R.add(node.position, R.scale(dir, District.plaza_radius + half * std.math.sqrt2 + 4));
        var b: Building = .{
            .base = .{ at[0], Terrain.surface(layout.seed, at[0], at[2]).height, at[2] },
            .half = .{ half, half },
            .roof = node.position[1] + 60 + 90 * Rand.unit(&h),
            .tiers = 2 + @as(u8, @intFromFloat(Rand.unit(&h) * 1.99)),
            .palette = @intCast(i % palettes.len),
            .plaza = @intCast(i),
        };
        b.spire = b.roof + 14 + 26 * Rand.unit(&h);
        if (clear(layout, lanes, layout.buildings[0..n], b, i)) {
            layout.buildings[n] = b;
            n += 1;
        }
    }
    var attempts: usize = 0;
    while (n < target_skyline + 3 and n < max_buildings and attempts < 600) : (attempts += 1) {
        const x = -480 + 960 * Rand.unit(&h);
        const z = -260 + 800 * Rand.unit(&h);
        const ground = Terrain.surface(layout.seed, x, z).height;
        const tall = Rand.unit(&h);
        var b: Building = .{
            .base = .{ x, ground, z },
            .half = .{ 9 + 9 * Rand.unit(&h), 9 + 9 * Rand.unit(&h) },
            .roof = ground + 50 + 210 * tall * tall,
            .tiers = 1 + @as(u8, @intFromFloat(Rand.unit(&h) * 2.99)),
            .palette = @intFromFloat(Rand.unit(&h) * (@as(f32, palettes.len) - 0.01)),
        };
        b.spire = b.roof + (if (tall > 0.5) 10 + 35 * Rand.unit(&h) else 3);
        if (!clear(layout, lanes, layout.buildings[0..n], b, null)) continue;
        layout.buildings[n] = b;
        n += 1;
    }
    layout.building_count = n;
}

/// Setback tiers, inset glass bays, floor bands, crown ribs, a light-catching dome, and a spire.
pub fn geometry(layout: *const District.Layout, b: Building, out: anytype) !void {
    const p = palettes[b.palette];
    var bottom = b.base[1] - 2;
    var half = b.half;
    for (0..b.tiers) |k| {
        const top = if (k + 1 == b.tiers) b.roof else bottom + (b.roof - bottom) * (0.55 + 0.1 * @as(f32, @floatFromInt(k)));
        const height = top - bottom;
        try out.add(.{ .center = .{ b.base[0], bottom + height / 2, b.base[2] }, .size = .{ half[0] * 2, height, half[1] * 2 }, .color = p.body });
        // Narrow, inset glass bays break up the old blank box facades. Repeating three calm
        // vertical ribbons on each face keeps the tower legible from the ground and distant hills.
        const bay_w = @min(1.5, half[0] * 0.22);
        const bay_h = @max(2, height - 4);
        for ([_]f32{ -0.58, 0, 0.58 }) |u| {
            try out.add(.{ .center = .{ b.base[0] + u * half[0], bottom + height / 2, b.base[2] + half[1] + 0.12 }, .size = .{ bay_w, bay_h, 0.18 }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] + u * half[0], bottom + height / 2, b.base[2] - half[1] - 0.12 }, .size = .{ bay_w, bay_h, 0.18 }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] + half[0] + 0.12, bottom + height / 2, b.base[2] + u * half[1] }, .size = .{ 0.18, bay_h, bay_w }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] - half[0] - 0.12, bottom + height / 2, b.base[2] + u * half[1] }, .size = .{ 0.18, bay_h, bay_w }, .color = p.glass, .solid = false });
        }
        // Floor bands, at most 14 per tier.
        const spacing = @max(7, height / 14);
        var y = bottom + spacing;
        while (y < top - 1) : (y += spacing) try out.add(.{ .center = .{ b.base[0], y, b.base[2] }, .size = .{ half[0] * 2 + 0.6, 0.45, half[1] * 2 + 0.6 }, .color = p.band, .solid = false });
        for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
            try out.add(.{ .center = .{ b.base[0] + sx * (half[0] + 0.2), bottom + height / 2, b.base[2] + sz * (half[1] + 0.2) }, .size = .{ 0.7, height, 0.7 }, .color = p.fin, .solid = false });
        };
        try out.add(.{ .center = .{ b.base[0], top + 0.6, b.base[2] }, .size = .{ half[0] * 2 + 1.2, 1.2, half[1] * 2 + 1.2 }, .color = p.band });
        bottom = top;
        half = .{ half[0] * 0.72, half[1] * 0.72 };
    }
    // Layer a shallow, faceted dome above the crown. Its open ribs preserve the sky through the
    // structure and read as an observatory crown instead of another solid cube.
    try out.add(.{ .center = .{ b.base[0], b.roof + 2.5, b.base[2] }, .size = .{ half[0] * 1.2, 4, half[1] * 1.2 }, .color = p.fin });
    const dome_r = @min(half[0], half[1]) * 0.44;
    var lower: [3]f32 = .{ b.base[0], b.roof + 4.6, b.base[2] };
    var upper: [3]f32 = .{ b.base[0], b.roof + 13, b.base[2] };
    for (0..12) |i| {
        const a0 = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 12;
        const a1 = @as(f32, @floatFromInt(i + 1)) * 2 * std.math.pi / 12;
        lower[0] = b.base[0] + @cos(a0) * dome_r;
        lower[1] = b.roof + 4.6;
        lower[2] = b.base[2] + @sin(a0) * dome_r;
        upper[0] = b.base[0] + @cos(a1) * dome_r;
        upper[1] = b.roof + 4.6;
        upper[2] = b.base[2] + @sin(a1) * dome_r;
        try Bridges.beam(out, lower, upper, 0.62, p.glass, false);
        const apex: V = .{ b.base[0], b.roof + 12.5, b.base[2] };
        try Bridges.beam(out, lower, apex, 0.48, p.fin, false);
    }
    try Bridges.beam(out, .{ b.base[0], b.roof + 4, b.base[2] }, b.beacon(), 0.8, p.band, true);
    if (b.plaza) |i| {
        // Sky lobby: a walkable deck from the plaza edge to the tower at plaza level.
        const node = layout.nodes[i].position;
        const dir = R.normalize(.{ b.base[0] - node[0], 0, b.base[2] - node[2] });
        const from = R.add(node, R.scale(dir, District.plaza_radius - 1));
        const to = R.add(.{ b.base[0], node[1], b.base[2] }, R.scale(dir, -@min(b.half[0], b.half[1]) + 0.5));
        const s: District.Span = .{ .a = from, .b = to };
        try out.add(.{ .center = R.add(s.point(0.5), .{ 0, -0.5, 0 }), .size = .{ 8, 1, s.length() }, .rotation = s.rotation(), .color = .{ 0.44, 0.48, 0.41 } });
        try out.add(.{ .center = R.add(to, .{ 0, 4.5, 0 }), .size = .{ 8, 0.4, 3 }, .rotation = s.rotation(), .color = p.fin });
    }
}

/// Braced steel legs under a free-standing plaza (the Arbor junctions).
pub fn plazaBraces(layout: *const District.Layout, node: V, out: anytype) !void {
    const steel: V = .{ 0.38, 0.42, 0.48 };
    const top = node[1] - 1;
    var legs: [4]V = undefined;
    for ([_][2]f32{ .{ -11, -11 }, .{ 11, -11 }, .{ 11, 11 }, .{ -11, 11 } }, &legs) |o, *leg| {
        leg.* = .{ node[0] + o[0], Terrain.surface(layout.seed, node[0] + o[0], node[2] + o[1]).height - 1, node[2] + o[1] };
        try out.add(.{ .center = .{ leg.*[0], (leg.*[1] + top) / 2, leg.*[2] }, .size = .{ 2, top - leg.*[1], 2 }, .color = steel });
        try out.add(.{ .center = .{ leg.*[0], leg.*[1] + 0.7, leg.*[2] }, .size = .{ 4, 1.4, 4 }, .color = .{ 0.52, 0.53, 0.50 } });
    }
    for (0..4) |k| {
        const a = legs[k];
        const b = legs[(k + 1) % 4];
        try Bridges.beam(out, .{ a[0], top - 0.8, a[2] }, .{ b[0], top - 0.8, b[2] }, 1.2, steel, true);
        if (top - @max(a[1], b[1]) > 10) {
            try Bridges.beam(out, .{ a[0], a[1] + 2, a[2] }, .{ b[0], top - 2, b[2] }, 0.5, steel, true);
            try Bridges.beam(out, .{ b[0], b[1] + 2, b[2] }, .{ a[0], top - 2, a[2] }, 0.5, steel, true);
        }
    }
}

test "the skyline is seeded, plentiful, and clear of roads, bridge routes, plazas, trunks, and spawn" {
    for ([_]u64{ 0, 42, 310399555161, 987654321 }) |seed| {
        const layout = try District.generate(seed);
        try std.testing.expect(layout.building_count >= 12);
        var lane_buffer: [64][2]V = undefined;
        const lanes = corridors(&layout, &lane_buffer);
        var beside: usize = 0;
        for (layout.buildings[0..layout.building_count], 0..) |b, i| {
            try std.testing.expect(clear(&layout, lanes, layout.buildings[0..i], b, if (b.plaza) |p| p else null));
            try std.testing.expect(b.spire > b.roof and b.roof > b.base[1] + 30);
            beside += @intFromBool(b.plaza != null);
        }
        try std.testing.expect(beside >= 2);
        var facade: District.CityParts = .{};
        try geometry(&layout, layout.buildings[0], &facade);
        var glass_parts: usize = 0;
        for (facade.slice()) |part| glass_parts += @intFromBool(std.meta.eql(part.color, palettes[layout.buildings[0].palette].glass));
        try std.testing.expect(glass_parts >= 12);
        try std.testing.expectEqualDeep(layout, try District.generate(seed));
        // Every documented bridge route stays buildable.
        try District.validate(&layout, &.{.{ .a = 0, .b = 3 }});
    }
}
