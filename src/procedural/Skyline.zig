//! The sky city's skyline: stone and steel skyscrapers rising from the forest floor around and
//! through the district, plus roof gardens and suspension skyways above the canopy. Placement is
//! seeded and validated. Towers keep clear of every road,
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
pub const skyline_min_height: f32 = 762; // about 2,500 ft
pub const skyline_max_height: f32 = 1067; // about 3,500 ft
pub const skyway_deck_height: f32 = 950;
/// `eco` is the newer rounded Arbor style: round shafts ringed with planted terraces, living
/// green columns and a garden crown. It replaces about half of the modern boxes.
pub const Architecture = enum { modern, gothic, industrial, eco };
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
    .{ .body = .{ 0.82, 0.82, 0.77 }, .band = .{ 0.66, 0.68, 0.64 }, .fin = .{ 0.90, 0.87, 0.77 }, .glass = .{ 0.27, 0.61, 0.65 } },
    .{ .body = .{ 0.69, 0.49, 0.31 }, .band = .{ 0.51, 0.34, 0.22 }, .fin = .{ 0.87, 0.67, 0.42 }, .glass = .{ 0.29, 0.53, 0.53 } },
    .{ .body = .{ 0.39, 0.42, 0.40 }, .band = .{ 0.27, 0.32, 0.28 }, .fin = .{ 0.50, 0.55, 0.45 }, .glass = .{ 0.25, 0.52, 0.57 } },
    // Eco towers: pale shell or warm sandstone shell, planted bands, sea-green glass.
    .{ .body = .{ 0.86, 0.88, 0.84 }, .band = .{ 0.30, 0.55, 0.32 }, .fin = .{ 0.72, 0.80, 0.70 }, .glass = .{ 0.26, 0.66, 0.66 } },
    .{ .body = .{ 0.78, 0.70, 0.56 }, .band = .{ 0.34, 0.56, 0.30 }, .fin = .{ 0.86, 0.80, 0.62 }, .glass = .{ 0.30, 0.62, 0.58 } },
};

fn paletteFor(style: Architecture, seed_palette: usize) u8 {
    return switch (style) {
        .modern => @intCast(seed_palette % palettes.len),
        .gothic => if (seed_palette % 2 == 0) 4 else 8,
        .industrial => 5,
        .eco => if (seed_palette % 2 == 0) 9 else 10,
    };
}

/// Whether a modern tower at (x, z) is built in the rounded eco style instead. A hash of the
/// position, not the placement random stream, so choosing it moves no tower.
fn ecoAt(seed: u64, x: f32, z: f32) bool {
    const key: u64 = @bitCast(@as(i64, @intFromFloat(@floor(x))) *% 73856093 ^ @as(i64, @intFromFloat(@floor(z))) *% 83492791);
    return Seed.unit(Seed.mix(seed ^ 0x45434f5f544f5752 ^ key)) < 0.55;
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
        var scores: [32]f32 = undefined;
        for (&scores, 0..) |*score, k| {
            const a = @as(f32, @floatFromInt(k)) * 2 * std.math.pi / 32;
            const d: V = .{ @sin(a), 0, @cos(a) };
            score.* = 1 - R.dot(d, market);
            for (layout.nodes, 0..) |other, j| if (j != i) {
                score.* = @min(score.*, 1 - R.dot(d, R.normalize(.{ other.position[0] - node.position[0], 0, other.position[2] - node.position[2] })));
            };
        }
        const nominal_half = 8 + 3 * Rand.unit(&h);
        const architecture: Architecture = switch (i) {
            1 => .gothic,
            3 => .industrial,
            5 => .gothic,
            else => .modern,
        };
        const half = nominal_half * (if (architecture == .industrial) @as(f32, 1.35) else 1);
        const tiers: u8 = if (architecture == .industrial) 1 else 2 + @as(u8, @intFromFloat(Rand.unit(&h) * 1.99));
        const spire_roll = Rand.unit(&h);
        // The best bearing first; if a road, route or tree blocks it, the next best, so every
        // tower plaza keeps its sky lobby (a blocked first choice once left plaza 1 without one).
        var tried: [32]bool = @splat(false);
        for (0..32) |_| {
            var pick: usize = 0;
            var best: f32 = -3;
            for (scores, 0..) |score, k| if (!tried[k] and score > best) {
                best = score;
                pick = k;
            };
            tried[pick] = true;
            const a = @as(f32, @floatFromInt(pick)) * 2 * std.math.pi / 32;
            const dir: V = .{ @sin(a), 0, @cos(a) };
            const at = R.add(node.position, R.scale(dir, District.plaza_radius + half * std.math.sqrt2 + 4));
            var b: Building = .{
                .base = .{ at[0], Terrain.surface(layout.seed, at[0], at[2]).height, at[2] },
                .half = if (architecture == .industrial) .{ half, half * 0.82 } else .{ half, half },
                .roof = skyway_deck_height + @as(f32, @floatFromInt(i - 1)) * 8,
                .tiers = tiers,
                .palette = paletteFor(architecture, i),
                .architecture = architecture,
                .plaza = @intCast(i),
            };
            b.spire = b.roof + (if (architecture == .gothic) @as(f32, 35) else if (architecture == .industrial) @as(f32, 8) else 14) + (if (architecture == .gothic) @as(f32, 45) else if (architecture == .industrial) @as(f32, 16) else 26) * spire_roll;
            if (clear(layout, lanes, layout.buildings[0..n], b, i)) {
                layout.buildings[n] = b;
                n += 1;
                break;
            }
        }
    }
    var attempts: usize = 0;
    while (n < target_skyline + 3 and n < max_buildings and attempts < 600) : (attempts += 1) {
        const x = -480 + 960 * Rand.unit(&h);
        const z = -260 + 800 * Rand.unit(&h);
        const ground = Terrain.surface(layout.seed, x, z).height;
        const tall = Rand.unit(&h);
        const drawn = architectureAt(x, z, Rand.unit(&h));
        const architecture: Architecture = if (drawn == .modern and ecoAt(layout.seed, x, z)) .eco else drawn;
        const radius_scale: f32 = if (architecture == .industrial) 1.35 else 1;
        const height_base: f32 = if (architecture == .industrial) 90 else skyline_min_height;
        const height_range: f32 = if (architecture == .industrial) 240 else skyline_max_height - skyline_min_height;
        var b: Building = .{
            .base = .{ x, ground, z },
            .half = .{ (9 + 9 * Rand.unit(&h)) * radius_scale, (9 + 9 * Rand.unit(&h)) * radius_scale },
            .roof = ground + height_base + height_range * tall * tall,
            .tiers = if (architecture == .industrial) 1 + @as(u8, @intFromFloat(Rand.unit(&h) * 1.99)) else 1 + @as(u8, @intFromFloat(Rand.unit(&h) * 2.99)),
            .palette = paletteFor(architecture, @intFromFloat(Rand.unit(&h) * @as(f32, @floatFromInt(palettes.len)))),
            .architecture = architecture,
        };
        b.spire = b.roof + switch (architecture) {
            .gothic => 32 + 52 * Rand.unit(&h),
            .industrial => 14 + 36 * Rand.unit(&h),
            .modern, .eco => if (tall > 0.5) 10 + 35 * Rand.unit(&h) else 3,
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
    if (b.architecture == .eco) {
        try ecoTower(b, out);
        try skyLobby(layout, b, out);
        return;
    }
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
            .modern, .eco => @min(1.5, half[0] * 0.22),
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
        .eco => unreachable, // built by `ecoTower`
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
    // Stone towers carry hanging gardens down their facades. The narrow green runs leave the
    // windows legible and read as vines from the ground instead of a solid green wall.
    if (b.palette >= 6 and b.architecture != .industrial) {
        const ivy: V = .{ 0.22, 0.43, 0.25 };
        for ([_]f32{ -0.76, -0.28, 0.20, 0.66, 0.88 }) |u| {
            const top_y = b.roof - 8;
            const drop = 70 + @abs(u) * 45;
            const x = b.base[0] + u * b.half[0];
            const sign: f32 = if (u < 0) -1 else 1;
            const side: V = if (@abs(u) > 0.6)
                .{ x + sign * (b.half[0] + 0.18), top_y, b.base[2] + b.half[1] * 0.32 }
            else
                .{ x, top_y, b.base[2] + b.half[1] + 0.24 };
            const end = R.add(side, .{ 0.4 * @sin(u * 6), -@min(drop, top_y - b.base[1] - 8), 0 });
            try Bridges.beam(out, side, end, 1.8, ivy, false);
            const ledge = R.add(side, .{ 0, -2, 0 });
            try out.add(.{ .center = ledge, .size = .{ 5.5, 1.2, 2.8 }, .color = .{ 0.25, 0.48, 0.27 }, .solid = false });
        }
    }
    if (b.architecture != .industrial) try roofGarden(b, out);
    try skyLobby(layout, b, out);
}

/// Sky lobby: a walkable deck from a tower plaza's edge to its tower at plaza level.
fn skyLobby(layout: *const District.Layout, b: Building, out: anytype) !void {
    const p = palettes[b.palette];
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

/// The rounded eco tower: each tier a twelve-sided shaft (shell panels alternating with
/// full-height glass), its core filling the inside so the roof is walkable; planted terrace
/// rings every 130 m; three living green columns; and a crown of a garden ring, a glass dome
/// and leaf-like sails. About 150 parts, a third of them solid.
fn ecoTower(b: Building, out: anytype) !void {
    const p = palettes[b.palette];
    const sides = 12;
    const step = 2 * std.math.pi / @as(f32, sides);
    const leaf: V = .{ 0.24, 0.50, 0.30 };
    var bottom = b.base[1] - 2;
    var radius = @min(b.half[0], b.half[1]) * 1.12;
    for (0..b.tiers) |k| {
        const top = if (k + 1 == b.tiers) b.roof else bottom + (b.roof - bottom) * (0.55 + 0.1 * @as(f32, @floatFromInt(k)));
        const height = top - bottom;
        const mid = bottom + height / 2;
        // The core fills the shaft; the panels round its corners off.
        try out.add(.{ .center = .{ b.base[0], mid, b.base[2] }, .size = .{ radius * 1.42, height, radius * 1.42 }, .color = p.body });
        const panel = 2 * radius * @tan(step / 2) + 0.15;
        for (0..sides) |j| {
            const a = @as(f32, @floatFromInt(j)) * step;
            const at: V = .{ b.base[0] + @sin(a) * (radius - 0.8), mid, b.base[2] + @cos(a) * (radius - 0.8) };
            try out.add(.{ .center = at, .size = .{ panel, height, 1.6 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, a), .color = if (j % 2 == 0) p.body else p.glass });
        }
        // Planted terraces: a green ledge ring every 130 m up the shaft.
        var y = bottom + 60;
        while (y < top - 20) : (y += 130) {
            for (0..sides) |j| {
                const a = (@as(f32, @floatFromInt(j)) + 0.5) * step;
                const ring = radius + 2.2;
                try out.add(.{ .center = .{ b.base[0] + @sin(a) * ring, y, b.base[2] + @cos(a) * ring }, .size = .{ 2 * ring * @tan(step / 2) + 0.2, 1.6, 4.4 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, a), .color = p.band, .solid = false });
            }
        }
        // A pale rim where each tier steps in.
        try out.add(.{ .center = .{ b.base[0], top + 0.5, b.base[2] }, .size = .{ radius * 2.05, 1, radius * 2.05 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, step / 2), .color = p.fin });
        bottom = top;
        radius *= 0.8;
    }
    // Living columns: three green runs down the facade from the crown.
    for (0..3) |j| {
        const a = @as(f32, @floatFromInt(j)) * 2 * std.math.pi / 3 + 0.4;
        const r = @min(b.half[0], b.half[1]) * 1.12 + 0.6;
        const top: V = .{ b.base[0] + @sin(a) * r * 0.8, b.roof - 6, b.base[2] + @cos(a) * r * 0.8 };
        const foot: V = .{ b.base[0] + @sin(a) * r, b.base[1] + 30, b.base[2] + @cos(a) * r };
        try Bridges.beam(out, foot, top, 1.6, leaf, false);
    }
    // The crown: a planted garden ring on the roof, a glass dome, and six leaf sails.
    const crown_r = radius / 0.8 + 3;
    try out.add(.{ .center = .{ b.base[0], b.roof + 0.7, b.base[2] }, .size = .{ crown_r * 2, 1.4, crown_r * 2 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, step / 2), .color = .{ 0.30, 0.40, 0.32 } });
    for (0..sides) |j| {
        const a = (@as(f32, @floatFromInt(j)) + 0.5) * step;
        try out.add(.{ .center = .{ b.base[0] + @sin(a) * crown_r, b.roof + 1.9, b.base[2] + @cos(a) * crown_r }, .size = .{ 2 * crown_r * @tan(step / 2), 1.2, 2.4 }, .rotation = R.axisAngle(.{ 0, 1, 0 }, a), .color = leaf, .solid = false });
    }
    const dome_r = crown_r * 0.42;
    for (0..8) |i| {
        const a0 = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 8;
        const a1 = @as(f32, @floatFromInt(i + 1)) * 2 * std.math.pi / 8;
        const p0: V = .{ b.base[0] + @cos(a0) * dome_r, b.roof + 1.4, b.base[2] + @sin(a0) * dome_r };
        const p1: V = .{ b.base[0] + @cos(a1) * dome_r, b.roof + 1.4, b.base[2] + @sin(a1) * dome_r };
        try Bridges.beam(out, p0, p1, 0.5, p.glass, false);
        try Bridges.beam(out, p0, .{ b.base[0], b.roof + 1.4 + dome_r * 0.8, b.base[2] }, 0.4, p.glass, false);
    }
    for (0..6) |i| {
        const a = @as(f32, @floatFromInt(i)) * 2 * std.math.pi / 6;
        const root: V = .{ b.base[0] + @sin(a) * crown_r * 0.9, b.roof + 1.4, b.base[2] + @cos(a) * crown_r * 0.9 };
        const bow: V = .{ b.base[0] + @sin(a) * crown_r * 1.15, b.roof + 9, b.base[2] + @cos(a) * crown_r * 1.15 };
        const tip: V = .{ b.base[0] + @sin(a) * crown_r * 0.55, b.roof + 16, b.base[2] + @cos(a) * crown_r * 0.55 };
        try Bridges.beam(out, root, bow, 0.7, p.fin, false);
        try Bridges.beam(out, bow, tip, 0.55, p.fin, false);
    }
    if (b.spire > b.roof + 4) try Bridges.beam(out, .{ b.base[0], b.roof + 1.4, b.base[2] }, b.beacon(), 0.7, p.band, true);
}

fn roofGarden(b: Building, out: anytype) !void {
    const deck: V = .{ b.base[0], b.roof + 0.7, b.base[2] };
    try out.add(.{ .center = deck, .size = .{ b.half[0] * 2 + 16, 1.4, b.half[1] * 2 + 16 }, .color = .{ 0.24, 0.35, 0.29 } });
    for ([_]f32{ -1, 1 }) |sx| for ([_]f32{ -1, 1 }) |sz| {
        const x = b.base[0] + sx * (b.half[0] + 5.5);
        const z = b.base[2] + sz * (b.half[1] + 5.5);
        try out.add(.{ .center = .{ x, b.roof + 2, z }, .size = .{ 9, 1.2, 9 }, .color = .{ 0.22, 0.48, 0.28 } });
        try out.add(.{ .center = .{ x, b.roof + 2.68, z }, .size = .{ 7.8, 0.16, 7.8 }, .color = .{ 0.25, 0.31, 0.22 }, .solid = false });
    };
    // A sheltered kiosk gives each roof terrace a reason to be a place, not just a landing.
    try out.add(.{ .center = .{ b.base[0], b.roof + 3.8, b.base[2] }, .size = .{ 9, 6.2, 7 }, .color = palettes[b.palette].body });
    try out.add(.{ .center = .{ b.base[0], b.roof + 4, b.base[2] + 3.6 }, .size = .{ 6.5, 3.4, 0.2 }, .color = palettes[b.palette].glass, .solid = false });

    // The kiosk sits inside a light pergola, with open benches around the planted edge so the
    // roof reads as a small public square instead of a decorated rooftop landing.
    for ([_]f32{ -5, 5 }) |x| for ([_]f32{ -4, 4 }) |z| {
        try out.add(.{ .center = .{ b.base[0] + x, b.roof + 7.9, b.base[2] + z }, .size = .{ 0.55, 2, 0.55 }, .color = palettes[b.palette].fin, .solid = false });
    };
    try out.add(.{ .center = .{ b.base[0], b.roof + 9.15, b.base[2] }, .size = .{ 12, 0.5, 10 }, .color = palettes[b.palette].band, .solid = false });
    for ([_]f32{ -3, -1, 1, 3 }) |z| {
        try out.add(.{ .center = .{ b.base[0], b.roof + 9.52, b.base[2] + z }, .size = .{ 12, 0.18, 0.32 }, .color = palettes[b.palette].fin, .solid = false });
    }
    for ([_]f32{ -1, 1 }) |side| {
        const x = b.base[0] + side * (b.half[0] + 2.5);
        try out.add(.{ .center = .{ x, b.roof + 1.65, b.base[2] }, .size = .{ 5.5, 0.5, 1.6 }, .color = palettes[b.palette].band, .solid = false });
        try out.add(.{ .center = .{ x, b.roof + 2.35, b.base[2] - side * 0.55 }, .size = .{ 5.5, 0.9, 0.25 }, .color = palettes[b.palette].fin, .solid = false });
    }
}

/// One planned skyway: two towers and the level deck between them (world y of the deck's top
/// surface). The lower tower's roof terrace is the landing at one end; the taller tower gets a
/// sky collar at the deck height at the other.
pub const SkySpan = struct { a: u8, b: u8, deck: f32 };
pub const max_skyways = 40;
/// Longest skyway worth building; farther towers connect through nearer ones.
pub const max_skyway_length: f32 = 380;

fn bridged(b: Building) bool {
    return b.architecture != .industrial or b.plaza != null;
}

/// Where a span's deck may run: clear of every other tower that stands above the deck.
fn spanClear(layout: *const District.Layout, ai: usize, bi: usize, deck: f32) bool {
    const a = layout.buildings[ai];
    const b = layout.buildings[bi];
    for (layout.buildings[0..layout.building_count], 0..) |c, ci| {
        if (ci == ai or ci == bi or c.spire < deck - 4) continue;
        if (segmentDistance(c.base, a.base, b.base) < c.radius() + 10) return false;
    }
    return true;
}

fn deckBetween(a: Building, b: Building) f32 {
    return @min(a.roof, b.roof) + 1.4;
}

/// The skyway network: a nearest-first tree from a tower plaza's tower (plaza 1's if it has one)
/// over every tower that is bridged, using only spans that are clear and not too long, then
/// the short loop between the three market towers. Pure, so tests can check it.
pub fn plannedSkyways(layout: *const District.Layout, out: *[max_skyways]SkySpan) []SkySpan {
    var n: usize = 0;
    var connected: [max_buildings]bool = @splat(false);
    const towers = layout.buildings[0..layout.building_count];
    var root: ?usize = null;
    for (towers, 0..) |t, i| if (t.plaza == 1) {
        root = i;
    };
    if (root == null) for (towers, 0..) |t, i| if (t.plaza != null and bridged(t)) {
        root = i;
        break;
    };
    if (root == null) for (towers, 0..) |t, i| if (bridged(t)) {
        root = i;
        break;
    };
    connected[root orelse return out[0..0]] = true;
    while (n < max_skyways) {
        var best: f32 = std.math.inf(f32);
        var from: usize = 0;
        var to: usize = 0;
        for (towers, 0..) |a, ai| {
            if (!connected[ai] or !bridged(a)) continue;
            for (towers, 0..) |b, bi| {
                if (connected[bi] or ai == bi or !bridged(b)) continue;
                const distance = planar(a.base, b.base);
                if (distance >= best or distance > max_skyway_length) continue;
                if (!spanClear(layout, ai, bi, deckBetween(a, b))) continue;
                best = distance;
                from = ai;
                to = bi;
            }
        }
        if (!std.math.isFinite(best)) break;
        connected[to] = true;
        out[n] = .{ .a = @intCast(from), .b = @intCast(to), .deck = deckBetween(towers[from], towers[to]) };
        n += 1;
    }
    // A short return link between the three market towers closes the parkour loop.
    const links = [_][2]usize{ .{ 1, 3 }, .{ 3, 5 }, .{ 5, 1 } };
    for (links) |link| {
        if (n == max_skyways) break;
        var ia: ?usize = null;
        var ib: ?usize = null;
        for (towers, 0..) |t, i| {
            if (t.plaza == @as(?u8, @intCast(link[0]))) ia = i;
            if (t.plaza == @as(?u8, @intCast(link[1]))) ib = i;
        }
        const x = ia orelse continue;
        const y = ib orelse continue;
        var duplicate = false;
        for (out[0..n]) |sp| duplicate = duplicate or (sp.a == x and sp.b == y) or (sp.a == y and sp.b == x);
        if (duplicate or !spanClear(layout, x, y, deckBetween(towers[x], towers[y]))) continue;
        out[n] = .{ .a = @intCast(x), .b = @intCast(y), .deck = deckBetween(towers[x], towers[y]) };
        n += 1;
    }
    return out[0..n];
}

/// Where a span lands at tower `t` heading toward `other`: on the roof terrace if the deck is at
/// its roof, else on its sky collar just outside the facade.
fn landing(t: Building, other: Building, deck: f32) V {
    const dir = R.normalize(.{ other.base[0] - t.base[0], 0, other.base[2] - t.base[2] });
    const at_roof = deck <= t.roof + 1.5;
    const reach = if (at_roof) @min(t.half[0], t.half[1]) * 0.5 else t.radius() + 3;
    return .{ t.base[0] + dir[0] * reach, deck, t.base[2] + dir[2] * reach };
}

/// Every skyway, with the sky collars where a deck meets a taller tower's facade.
pub fn skyways(layout: *const District.Layout, out: anytype) !void {
    var plan: [max_skyways]SkySpan = undefined;
    const towers = layout.buildings[0..layout.building_count];
    for (plannedSkyways(layout, &plan)) |sp| {
        const a = towers[sp.a];
        const b = towers[sp.b];
        const from = landing(a, b, sp.deck);
        const to = landing(b, a, sp.deck);
        for ([_]Building{ a, b }) |t| if (sp.deck > t.roof + 1.5) {
            // A sky collar: a walkable deck all around the taller tower at the skyway's height.
            const p = palettes[t.palette];
            try out.add(.{ .center = .{ t.base[0], sp.deck - 0.7, t.base[2] }, .size = .{ t.half[0] * 2 + 14, 1.4, t.half[1] * 2 + 14 }, .color = .{ 0.34, 0.40, 0.37 } });
            try out.add(.{ .center = .{ t.base[0], sp.deck + 1.2, t.base[2] }, .size = .{ t.half[0] * 2 + 14.4, 0.35, t.half[1] * 2 + 14.4 }, .color = p.fin, .solid = false });
        };
        try skywaySpan(from, to, out);
    }
}

fn skywaySpan(start: V, end: V, out: anytype) !void {
        // The deck's top sits at the endpoints' height, level with the landings.
        const span: District.Span = .{ .a = R.add(start, .{ 0, -0.7, 0 }), .b = R.add(end, .{ 0, -0.7, 0 }) };
        const q = span.rotation();
        const length = span.length();
        if (length < 20) return;
        try out.add(.{ .center = span.point(0.5), .size = .{ 32, 1.4, length }, .rotation = q, .color = .{ 0.30, 0.38, 0.36 } });
        // Gate pylons mark each landing and carry the visible suspension loads outside the path.
        for ([_]f32{ 0, 1 }) |t| for ([_]f32{ -17, 17 }) |side| {
            const base = R.add(span.point(t), R.rotate(q, .{ side, 1.4, 0 }));
            const top = R.add(base, .{ 0, 42, 0 });
            try out.add(.{ .center = R.add(base, .{ 0, 21, 0 }), .size = .{ 2.8, 42, 2.8 }, .rotation = q, .color = .{ 0.66, 0.69, 0.65 } });
            try Bridges.beam(out, base, top, 1.4, .{ 0.74, 0.80, 0.78 }, false);
        };
        for ([_]f32{ -15.5, 15.5 }) |side| {
            const offset = R.rotate(q, .{ side, 2.4, 0 });
            try out.add(.{ .center = R.add(span.point(0.5), offset), .size = .{ 0.6, 4.8, length }, .rotation = q, .color = .{ 0.38, 0.48, 0.46 } });
            const rail = R.rotate(q, .{ side, 5.1, 0 });
            try out.add(.{ .center = R.add(span.point(0.5), rail), .size = .{ 0.35, 0.35, length }, .rotation = q, .color = .{ 0.22, 0.75, 0.78 }, .solid = false });
        }
        // Broad sky terraces break long spans into garden, market, and parkour rooms.
        const rooms: []const f32 = if (length > 180) &.{ 0.25, 0.5, 0.75 } else &.{0.5};
        for (rooms) |t| {
            const center = span.point(t);
            const market = t == 0.5;
            try out.add(.{ .center = center, .size = .{ 48, 1.8, @min(42, length * 0.3) }, .rotation = q, .color = if (market) .{ 0.34, 0.34, 0.30 } else .{ 0.20, 0.38, 0.26 } });
            for ([_]f32{ -15, 15 }) |side| {
                const planter = R.add(center, R.rotate(q, .{ side, 1.7, 0 }));
                try out.add(.{ .center = planter, .size = .{ 8, 1.8, @min(24, length * 0.2) }, .rotation = q, .color = .{ 0.24, 0.52, 0.30 } });
            }
            if (!market) for ([_]f32{ -8, 8 }) |side| {
                const seat = R.add(center, R.rotate(q, .{ side, 1.45, 0 }));
                const back = R.add(center, R.rotate(q, .{ side + (if (side < 0) @as(f32, 0.7) else -0.7), 2.05, 0 }));
                try out.add(.{ .center = seat, .size = .{ 5.5, 0.5, 1.4 }, .rotation = q, .color = .{ 0.64, 0.59, 0.46 }, .solid = false });
                try out.add(.{ .center = back, .size = .{ 5.5, 0.9, 0.25 }, .rotation = q, .color = .{ 0.42, 0.46, 0.39 }, .solid = false });
            };
            if (market) {
                const kiosk = R.add(center, R.rotate(q, .{ 0, 4.5, 0 }));
                try out.add(.{ .center = kiosk, .size = .{ 12, 7.2, 10 }, .rotation = q, .color = palettes[2].body });
                const glass = R.add(kiosk, R.rotate(q, .{ 0, 0, 5.1 }));
                try out.add(.{ .center = glass, .size = .{ 8.5, 4.5, 0.2 }, .rotation = q, .color = palettes[2].glass, .solid = false });
            }
        }
        // Cable arcs and hangers give the skywalks a suspension-bridge silhouette.
        const height: f32 = @min(44, length * 0.08);
        for ([_]f32{ -13, 13 }) |side| {
            var previous = R.add(span.point(0), R.rotate(q, .{ side, 0.8, 0 }));
            for (1..9) |step| {
                const t = @as(f32, @floatFromInt(step)) / 8;
                const rise = 0.8 + height * (1 - 4 * (t - 0.5) * (t - 0.5));
                const next = R.add(span.point(t), R.rotate(q, .{ side, rise, 0 }));
                try Bridges.beam(out, previous, next, 0.32, .{ 0.74, 0.80, 0.78 }, false);
                previous = next;
            }
            for (1..8) |step| {
                const t = @as(f32, @floatFromInt(step)) / 8;
                const rise = 0.8 + height * (1 - 4 * (t - 0.5) * (t - 0.5));
                const top = R.add(span.point(t), R.rotate(q, .{ side, rise, 0 }));
                const foot = R.add(span.point(t), R.rotate(q, .{ side, 0.8, 0 }));
                try Bridges.beam(out, foot, top, 0.12, .{ 0.78, 0.82, 0.80 }, false);
            }
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

test "every tower plaza keeps its tower, and level skyways connect the skyline without crossing a tower" {
    var eco_seen: usize = 0;
    for ([_]u64{ 0x4845415659, 0, 42, 310399555161, 987654321 }) |seed| {
        const layout = try District.generate(seed);
        const towers = layout.buildings[0..layout.building_count];
        // The default world once lost plaza 1's tower to a blocked bearing, and every skyway with it.
        for (layout.nodes, 0..) |node, i| if (node.kind == .tower) {
            var found = false;
            for (towers) |t| found = found or t.plaza == @as(?u8, @intCast(i));
            try std.testing.expect(found);
        };
        var plan: [max_skyways]SkySpan = undefined;
        const spans = plannedSkyways(&layout, &plan);
        var bridged_count: usize = 0;
        for (towers) |t| bridged_count += @intFromBool(bridged(t));
        try std.testing.expect(spans.len + 1 >= bridged_count * 7 / 10);
        var linked: [max_buildings]bool = @splat(false);
        for (spans) |sp| {
            const a = towers[sp.a];
            const b = towers[sp.b];
            linked[sp.a] = true;
            linked[sp.b] = true;
            // Level: the deck is at the lower roof's terrace, below both crowns.
            try std.testing.expectEqual(@min(a.roof, b.roof) + 1.4, sp.deck);
            try std.testing.expect(sp.deck <= a.roof + 1.5 or sp.deck <= b.roof + 1.5);
            try std.testing.expect(spanClear(&layout, sp.a, sp.b, sp.deck));
            try std.testing.expect(planar(a.base, b.base) <= max_skyway_length * 1.6);
        }
        var reached: usize = 0;
        for (towers, 0..) |t, i| reached += @intFromBool(bridged(t) and linked[i]);
        try std.testing.expect(reached * 10 >= bridged_count * 7);
        for (towers) |t| eco_seen += @intFromBool(t.architecture == .eco);
        // The whole city, skyways and rounded towers included, fits the shared part budget.
        const parts = try District.geometry(&layout);
        try std.testing.expect(parts.count < 8192);
    }
    try std.testing.expect(eco_seen >= 5);
}

test "an eco tower is round, walkable on top, ringed with terraces and crowned with a garden" {
    var parts: District.CityParts = .{};
    const b: Building = .{ .base = .{ 0, 100, 0 }, .half = .{ 14, 14 }, .roof = 950, .spire = 980, .tiers = 3, .palette = 9, .architecture = .eco };
    try ecoTower(b, &parts);
    try std.testing.expect(parts.count > 60 and parts.count < 170);
    var solid_top: f32 = 0;
    var panels: usize = 0;
    var terraces: usize = 0;
    for (parts.slice()) |p| {
        // The highest wide solid slab is the walkable roof (the spire beam is solid but narrow).
        if (p.solid and p.size[0] > 10 and p.size[2] > 10) solid_top = @max(solid_top, p.center[1] + p.size[1] / 2);
        if (p.solid and p.size[2] == 1.6) panels += 1;
        if (!p.solid and std.meta.eql(p.color, palettes[9].band)) terraces += 1;
    }
    // A solid roof surface at the roof terrace (the garden deck tops out at roof + 1.4).
    try std.testing.expect(solid_top >= b.roof + 1.3 and solid_top <= b.roof + 1.5);
    try std.testing.expectEqual(@as(usize, 12 * 3), panels);
    try std.testing.expect(terraces >= 12 * 4);
}
