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
pub const Architecture = enum { modern, gothic, industrial };
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
    architecture: Architecture = .modern,
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
    .{ .body = .{ 0.39, 0.38, 0.35 }, .band = .{ 0.18, 0.19, 0.21 }, .fin = .{ 0.64, 0.57, 0.43 }, .glass = .{ 0.78, 0.62, 0.36 } },
    .{ .body = .{ 0.22, 0.26, 0.29 }, .band = .{ 0.12, 0.15, 0.17 }, .fin = .{ 0.67, 0.34, 0.18 }, .glass = .{ 0.31, 0.44, 0.47 } },
};

fn paletteFor(style: Architecture, seed_palette: usize) u8 {
    return switch (style) {
        .modern => @intCast(seed_palette % 4),
        .gothic => 4,
        .industrial => 5,
    };
}

fn architectureAt(x: f32, z: f32, roll: f32) Architecture {
    // Detroit's riverfront factories sit beyond the civic core; historic stone towers cluster
    // around the old market wards, while newer Arbor towers fill the remaining skyline.
    if (x > 170 and z > 95) return .industrial;
    if (x < -150 and z > 85 and z < 430) return .gothic;
    if (roll < 0.21) return .gothic;
    if (roll < 0.43) return .industrial;
    return .modern;
}

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
        const nominal_half = 8 + 3 * Rand.unit(&h);
        const architecture: Architecture = switch (i) {
            1 => .gothic,
            3 => .industrial,
            5 => .gothic,
            else => .modern,
        };
        const half = nominal_half * (if (architecture == .industrial) @as(f32, 1.35) else 1);
        const at = R.add(node.position, R.scale(dir, District.plaza_radius + half * std.math.sqrt2 + 4));
        var b: Building = .{
            .base = .{ at[0], Terrain.surface(layout.seed, at[0], at[2]).height, at[2] },
            .half = if (architecture == .industrial) .{ half, half * 0.82 } else .{ half, half },
            .roof = node.position[1] + (if (architecture == .industrial) @as(f32, 44) else 60) + (if (architecture == .industrial) @as(f32, 48) else 90) * Rand.unit(&h),
            .tiers = if (architecture == .industrial) 1 else 2 + @as(u8, @intFromFloat(Rand.unit(&h) * 1.99)),
            .palette = paletteFor(architecture, i),
            .architecture = architecture,
            .plaza = @intCast(i),
        };
        b.spire = b.roof + (if (architecture == .gothic) @as(f32, 35) else if (architecture == .industrial) @as(f32, 8) else 14) + (if (architecture == .gothic) @as(f32, 45) else if (architecture == .industrial) @as(f32, 16) else 26) * Rand.unit(&h);
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
        const architecture = architectureAt(x, z, Rand.unit(&h));
        const radius_scale: f32 = if (architecture == .industrial) 1.35 else 1;
        const height_base: f32 = if (architecture == .industrial) 38 else if (architecture == .gothic) 55 else 50;
        const height_range: f32 = if (architecture == .industrial) 70 else 210;
        var b: Building = .{
            .base = .{ x, ground, z },
            .half = .{ (9 + 9 * Rand.unit(&h)) * radius_scale, (9 + 9 * Rand.unit(&h)) * radius_scale },
            .roof = ground + height_base + height_range * tall * tall,
            .tiers = if (architecture == .industrial) 1 + @as(u8, @intFromFloat(Rand.unit(&h) * 1.99)) else 1 + @as(u8, @intFromFloat(Rand.unit(&h) * 2.99)),
            .palette = paletteFor(architecture, @intFromFloat(Rand.unit(&h) * 4)),
            .architecture = architecture,
        };
        b.spire = b.roof + switch (architecture) {
            .gothic => 32 + 52 * Rand.unit(&h),
            .industrial => 14 + 36 * Rand.unit(&h),
            .modern => if (tall > 0.5) 10 + 35 * Rand.unit(&h) else 3,
        };
        if (!clear(layout, lanes, layout.buildings[0..n], b, null)) continue;
        layout.buildings[n] = b;
        n += 1;
    }
    layout.building_count = n;
}

/// Detroit's mixed skyline: modern Arbor towers, pointed stone Gothic landmarks, and industrial
/// works with flues, service gantries, and visible pipe runs.
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
        const bay_w = switch (b.architecture) {
            .gothic => @min(1.05, half[0] * 0.16),
            .industrial => @min(1.2, half[0] * 0.17),
            .modern => @min(1.5, half[0] * 0.22),
        };
        const bay_h = @max(2, height - if (b.architecture == .gothic) @as(f32, 8) else 4);
        for ([_]f32{ -0.58, 0, 0.58 }) |u| {
            try out.add(.{ .center = .{ b.base[0] + u * half[0], bottom + height / 2, b.base[2] + half[1] + 0.12 }, .size = .{ bay_w, bay_h, 0.18 }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] + u * half[0], bottom + height / 2, b.base[2] - half[1] - 0.12 }, .size = .{ bay_w, bay_h, 0.18 }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] + half[0] + 0.12, bottom + height / 2, b.base[2] + u * half[1] }, .size = .{ 0.18, bay_h, bay_w }, .color = p.glass, .solid = false });
            try out.add(.{ .center = .{ b.base[0] - half[0] - 0.12, bottom + height / 2, b.base[2] + u * half[1] }, .size = .{ 0.18, bay_h, bay_w }, .color = p.glass, .solid = false });
            if (b.architecture == .gothic) {
                const x = b.base[0] + u * half[0];
                const left: V = .{ x - bay_w * 0.6, bottom + 2.5, b.base[2] + half[1] + 0.22 };
                const peak: V = .{ x, bottom + height - 2.5, b.base[2] + half[1] + 0.22 };
                const right: V = .{ x + bay_w * 0.6, bottom + 2.5, b.base[2] + half[1] + 0.22 };
                try Bridges.beam(out, left, peak, 0.32, p.fin, false);
                try Bridges.beam(out, peak, right, 0.32, p.fin, false);
                const back_left: V = .{ left[0], left[1], b.base[2] - half[1] - 0.22 };
                const back_peak: V = .{ peak[0], peak[1], b.base[2] - half[1] - 0.22 };
                const back_right: V = .{ right[0], right[1], b.base[2] - half[1] - 0.22 };
                try Bridges.beam(out, back_left, back_peak, 0.32, p.fin, false);
                try Bridges.beam(out, back_peak, back_right, 0.32, p.fin, false);
            }
        }
        // Floor bands, at most 14 per tier.
        const spacing = @max(7, height / 14);
        var y = bottom + spacing;
        while (y < top - 1) : (y += spacing) try out.add(.{ .center = .{ b.base[0], y, b.base[2] }, .size = .{ half[0] * 2 + 0.6, 0.45, half[1] * 2 + 0.6 }, .color = p.band, .solid = false });
        for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
            const width: f32 = if (b.architecture == .gothic) 1.6 else if (b.architecture == .industrial) 0.9 else 0.7;
            try out.add(.{ .center = .{ b.base[0] + sx * (half[0] + 0.2), bottom + height / 2, b.base[2] + sz * (half[1] + 0.2) }, .size = .{ width, height, width }, .color = p.fin, .solid = false });
        };
        try out.add(.{ .center = .{ b.base[0], top + 0.6, b.base[2] }, .size = .{ half[0] * 2 + 1.2, 1.2, half[1] * 2 + 1.2 }, .color = p.band });
        bottom = top;
        half = .{ half[0] * 0.72, half[1] * 0.72 };
    }
    switch (b.architecture) {
        .modern => {
            // A light-catching observatory dome crowns the newer Arbor towers.
            try out.add(.{ .center = .{ b.base[0], b.roof + 2.5, b.base[2] }, .size = .{ half[0] * 1.2, 4, half[1] * 1.2 }, .color = p.fin });
            const dome_r = @min(half[0], half[1]) * 0.44;
            var lower: [3]f32 = undefined;
            var upper: [3]f32 = undefined;
            for (0..12) |i| {
                const a0 = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 12;
                const a1 = @as(f32, @floatFromInt(i + 1)) * 2 * std.math.pi / 12;
                lower = .{ b.base[0] + @cos(a0) * dome_r, b.roof + 4.6, b.base[2] + @sin(a0) * dome_r };
                upper = .{ b.base[0] + @cos(a1) * dome_r, b.roof + 4.6, b.base[2] + @sin(a1) * dome_r };
                try Bridges.beam(out, lower, upper, 0.62, p.glass, false);
                const apex: V = .{ b.base[0], b.roof + 12.5, b.base[2] };
                try Bridges.beam(out, lower, apex, 0.48, p.fin, false);
            }
            try Bridges.beam(out, .{ b.base[0], b.roof + 4, b.base[2] }, b.beacon(), 0.8, p.band, true);
        },
        .gothic => {
            // Pitched pinnacles and flying buttress lines break the broad roof into an older
            // civic silhouette; the gold lumen glass makes the lancet arches readable at dusk.
            const roof_y = b.roof + 1;
            const tip_y = b.spire;
            try Bridges.beam(out, .{ b.base[0], roof_y, b.base[2] }, b.beacon(), 1.5, p.band, true);
            for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
                const base: V = .{ b.base[0] + sx * half[0] * 0.78, roof_y, b.base[2] + sz * half[1] * 0.78 };
                const tip: V = .{ base[0], roof_y + (tip_y - roof_y) * 0.58, base[2] };
                try Bridges.beam(out, base, tip, 0.9, p.fin, false);
                const flying: V = .{ b.base[0] + sx * half[0] * 0.28, roof_y + 9, b.base[2] + sz * half[1] * 0.28 };
                try Bridges.beam(out, base, flying, 0.55, p.band, false);
            };
        },
        .industrial => {
            // Detroit's factory quarter: clustered exhaust flues, roof monitors, exposed pipes,
            // and transfer gantries give the Hive useful heavy-industry silhouettes to occupy.
            const delta = b.spire - b.roof;
            for (0..3) |i| {
                const f: f32 = @floatFromInt(i);
                const x = b.base[0] + (f - 1) * @min(half[0] * 0.58, 11);
                const z = b.base[2] + (if (i == 1) half[1] * 0.18 else -half[1] * 0.32);
                const h = delta * (0.64 + f * 0.1);
                try out.add(.{ .center = .{ x, b.roof + h * 0.5, z }, .size = .{ 2.6, h, 2.6 }, .color = p.band, .solid = false });
                try out.add(.{ .center = .{ x, b.roof + h, z }, .size = .{ 3.8, 0.9, 3.8 }, .color = p.fin, .solid = false });
                const warn = [_]f32{ 0.76, 0.18, 0.08 };
                try out.add(.{ .center = .{ x, b.roof + h + 1.1, z }, .size = .{ 0.75, 0.75, 0.75 }, .color = warn, .solid = false });
            }
            for ([_]f32{ -1, 1 }) |side| {
                const a: V = .{ b.base[0] + side * (half[0] + 0.4), b.base[1] + 5, b.base[2] - half[1] * 0.65 };
                const b0: V = .{ b.base[0] + side * (half[0] + 0.4), b.roof - 2, b.base[2] + half[1] * 0.65 };
                try Bridges.beam(out, a, b0, 0.65, p.fin, false);
                const gantry_a: V = .{ b.base[0] - half[0], b.roof + 8, b.base[2] };
                const gantry_b: V = .{ b.base[0] + half[0], b.roof + 8, b.base[2] };
                try Bridges.beam(out, gantry_a, gantry_b, 0.55, p.band, false);
            }
        },
    }
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
