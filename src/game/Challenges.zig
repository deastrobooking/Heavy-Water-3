//! Approach challenges for Detroit's discoveries. Each ground-level pickup sits in a cage of gates;
//! a short course of platformer blocks beside it ends on a pressure plate that opens the cage for
//! a few seconds. The course follows the discovery's method: stepping-stone pillars, a stair of
//! crumbling steps, a spring up to a ledge, or a mover ferry between two towers. The two pickups
//! already high on landmarks (the bell tower and the sky lobby) are their own climbs.
//!
//! The blocks are part of the city, not the players': they carry `Blocks.authored`, are rebuilt
//! from the seed at start and after every load, are never saved, and the tools will not remove,
//! restyle or refund them.
const std = @import("std");
const Sandbox = @import("Sandbox.zig");
const CityContent = @import("CityContent.zig");
const Blocks = @import("../build/Blocks.zig");
const Materials = @import("../build/Materials.zig");
const Course = @import("../build/Course.zig");
const Mesher = @import("../build/Mesher.zig");
const R = @import("../physics/Rotation.zig");

pub const Archetype = enum { stones, crumble_stair, spring_ledge, ferry };

pub fn archetypeOf(method: CityContent.Method) ?Archetype {
    return switch (method) {
        .grapple_climb, .tower_climb => null,
        .service_stairs, .gallery_trail => .crumble_stair,
        .wiring_puzzle, .glide_across => .spring_ledge,
        .follow_trail, .grapple_rings, .swim_dive => .stones,
        .metro_ride => .ferry,
    };
}

/// Where a challenge was laid: its first block, the plate that opens the cage, and the cage centre.
pub const Built = struct { archetype: Archetype, start: [3]i32, plate: [3]i32, cage: [3]i32 };

const stone: Blocks.Cell = .{ .shape = .cube, .material = Materials.ofRole(.castle, .main), .flags = Blocks.authored };

fn mech(role: Materials.Role, rot: u2) Blocks.Cell {
    return .{ .shape = .cube, .rot = rot, .material = Materials.ofRole(.platformer, role), .flags = Blocks.authored };
}

/// One cell of a layout, in the challenge's own frame: `along` steps away from the cage in the
/// chosen direction, `up` from the ground layer.
const Piece = struct { along: i32, side: i32 = 0, up: i32, cell: Blocks.Cell };

const max_pieces = 128;
/// How far a course may be pushed out from the cage; its plate still reaches every gate.
const max_shift = 5;
const Layout = struct {
    pieces: [max_pieces]Piece = undefined,
    len: usize = 0,
    start: [2]i32 = .{ 0, 0 },
    plate: [2]i32 = .{ 0, 0 },

    /// Push the whole course this many cells farther from the cage (to clear a canopy).
    fn shifted(self: Layout, by: i32) Layout {
        var out = self;
        for (out.pieces[0..out.len]) |*p| p.along += by;
        out.start[0] += by;
        out.plate[0] += by;
        return out;
    }

    fn add(self: *Layout, along: i32, up: i32, cell: Blocks.Cell) void {
        self.pieces[self.len] = .{ .along = along, .up = up, .cell = cell };
        self.len += 1;
    }

    fn pillar(self: *Layout, along: i32, height: i32, top: Blocks.Cell) void {
        var h: i32 = 0;
        while (h < height - 1) : (h += 1) self.add(along, h, stone);
        self.add(along, height - 1, top);
    }
};

/// A course running away from the cage along +along, compact enough for a 20 m plaza. Rot faces
/// movers back toward the cage.
fn layout(archetype: Archetype, mover_rot: u2) Layout {
    var l: Layout = .{};
    switch (archetype) {
        .stones => {
            // Pillars rising toward the cage; the plate tops the last, too high to jump from the floor.
            l.pillar(9, 2, stone);
            l.pillar(7, 3, stone);
            l.pillar(5, 4, stone);
            l.pillar(3, 6, mech(.nature, 0));
            l.start = .{ 9, 1 };
            l.plate = .{ 3, 5 };
        },
        .crumble_stair => {
            // The same climb, but every step crumbles under you: keep moving.
            l.add(11, 0, stone);
            l.pillar(9, 2, mech(.accent, 0));
            l.pillar(7, 3, mech(.accent, 0));
            l.pillar(5, 4, mech(.accent, 0));
            l.pillar(3, 6, mech(.nature, 0));
            l.start = .{ 11, 0 };
            l.plate = .{ 3, 5 };
        },
        .spring_ledge => {
            // A spring on the floor launches you onto a high ledge that holds the plate.
            l.add(10, 0, stone);
            l.add(8, 0, mech(.main, 0));
            l.pillar(4, 9, mech(.nature, 0));
            l.add(3, 8, stone);
            l.add(5, 8, stone);
            l.start = .{ 10, 0 };
            l.plate = .{ 4, 8 };
        },
        .ferry => {
            // Steps up a far tower, a mover across the gap, and the plate tower by the cage.
            l.pillar(11, 2, stone);
            l.pillar(10, 4, stone);
            l.pillar(9, 6, stone);
            l.add(8, 5, mech(.color, mover_rot));
            l.pillar(3, 6, mech(.nature, 0));
            l.start = .{ 11, 1 };
            l.plate = .{ 3, 5 };
        },
    }
    return l;
}

const directions = [_][2]i32{ .{ 0, 1 }, .{ 1, 0 }, .{ 0, -1 }, .{ -1, 0 } };
/// The quarter turn that faces a mover along each direction's opposite (back toward the cage).
const toward_cage = [_]u2{ 2, 3, 0, 1 };

fn world(cage: [3]i32, d: [2]i32, along: i32, up: i32) [3]i32 {
    return .{ cage[0] + d[0] * along, cage[1] + up, cage[2] + d[1] * along };
}

const Plan = struct { cage: [3]i32, roof: i32, d: [2]i32, l: Layout };

/// A cage centred on (x, z) over the floor near `floor_hint`, with room for the course somewhere.
fn planAt(sb: *const Sandbox, archetype: Archetype, x: f32, z: f32, floor_hint: f32) ?Plan {
    const ground = floorAt(sb, x, floor_hint + 2.5, z) orelse return null;
    if (@abs(ground - floor_hint) > 2.5) return null;
    const cage: [3]i32 = .{ @intFromFloat(@floor(x)), @intFromFloat(@floor(ground)), @intFromFloat(@floor(z)) };
    // A low canopy over the keepsake gets a cage one layer shorter.
    const roof: i32 = if (cageClear(sb, cage, 5)) 4 else if (cageClear(sb, cage, 4)) 3 else return null;
    // The first direction and distance whose cells are all open floor (no building, canopy,
    // bridge or route in the way).
    for (0..max_shift + 1) |shift| for (directions, 0..) |d, k| {
        const candidate = layout(archetype, toward_cage[k]).shifted(@intCast(shift));
        if (clear(sb, cage, d, candidate)) return .{ .cage = cage, .roof = roof, .d = d, .l = candidate };
    };
    return null;
}

/// How far a keepsake may move to find room for its challenge, off the routes.
pub const max_move: f32 = 30;

/// Lay every discovery's challenge. A keepsake whose spot is on a route, under a low roof or
/// without room for its course moves to the nearest spot on the same floor that has room (its
/// claims are by index, so nothing saved refers to the position). Cells already holding a
/// player's block are overwritten (only possible with a save from before the challenges
/// existed). Returns how many were laid.
pub fn place(sb: *Sandbox) usize {
    var laid: usize = 0;
    // Always from the city's own anchors, so a reload lays the same challenges.
    @import("CityDiscoveries.zig").positions(&sb.catalog.district, sb.seed, &sb.city_discovery_positions);
    for (CityContent.detroit.discoveries, 0..) |discovery, index| {
        sb.challenges[index] = null;
        const archetype = archetypeOf(discovery.method) orelse continue;
        const point = sb.city_discovery_positions[index];
        const floor_hint = floorAt(sb, point[0], point[1] + 0.5, point[2]) orelse point[1] - 1.25;
        // Rings of candidate spots, nearest first.
        const plan: Plan, const spot: [2]f32 = search: {
            var r: f32 = 0;
            while (r <= max_move) : (r += 2) {
                const steps: usize = if (r == 0) 1 else @intFromFloat(@ceil(r * 2));
                for (0..steps) |k| {
                    const angle = std.math.tau * @as(f32, @floatFromInt(k)) / @as(f32, @floatFromInt(steps));
                    const x = point[0] + @cos(angle) * r;
                    const z = point[2] + @sin(angle) * r;
                    if (planAt(sb, archetype, x, z, floor_hint)) |p| break :search .{ p, .{ x, z } };
                }
            }
            continue;
        };
        const cage = plan.cage;
        const d = plan.d;
        const l = plan.l;
        const blocks = sb.block_world.blocks;
        // The cage: gate walls around the keepsake and a gate roof.
        var ok = true;
        var dy: i32 = 1;
        while (dy <= plan.roof) : (dy += 1) {
            var dz: i32 = -2;
            while (dz <= 2) : (dz += 1) {
                var dx: i32 = -2;
                while (dx <= 2) : (dx += 1) {
                    if (dy < plan.roof and @abs(dx) < 2 and @abs(dz) < 2) continue;
                    blocks.set(cage[0] + dx, cage[1] + dy, cage[2] + dz, mech(.metal, 0)) catch {
                        ok = false;
                    };
                }
            }
        }
        for (l.pieces[0..l.len]) |p| {
            const c = world(cage, d, p.along, p.up);
            blocks.set(c[0], c[1], c[2], p.cell) catch {
                ok = false;
            };
        }
        if (!ok) continue;
        // The keepsake sits in the middle of its cage.
        const ground = floorAt(sb, spot[0], floor_hint + 2.5, spot[1]) orelse floor_hint;
        sb.city_discovery_positions[index] = .{ @as(f32, @floatFromInt(cage[0])) + 0.5, ground + 1.25, @as(f32, @floatFromInt(cage[2])) + 0.5 };
        sb.challenges[index] = .{ .archetype = archetype, .start = world(cage, d, l.start[0], l.start[1]), .plate = world(cage, d, l.plate[0], l.plate[1]), .cage = cage };
        laid += 1;
    }
    return laid;
}

/// Every column of the cage and the course has open air for its height and a floor near the
/// cage's floor, and lies in a chunk that may hold blocks.
fn cageClear(sb: *const Sandbox, cage: [3]i32, height: f32) bool {
    const base: f32 = @floatFromInt(cage[1]);
    var dz: i32 = -2;
    while (dz <= 2) : (dz += 1) {
        var dx: i32 = -2;
        while (dx <= 2) : (dx += 1) if (!columnClear(sb, .{ cage[0] + dx, cage[1], cage[2] + dz }, base, height)) return false;
    }
    return true;
}

fn clear(sb: *const Sandbox, cage: [3]i32, d: [2]i32, l: Layout) bool {
    const base: f32 = @floatFromInt(cage[1]);
    // The whole strip the course runs over, including a mover's path, to its tallest piece.
    var tallest: i32 = 0;
    var farthest: i32 = 0;
    for (l.pieces[0..l.len]) |p| {
        tallest = @max(tallest, p.up);
        farthest = @max(farthest, p.along);
    }
    var nearest: i32 = farthest;
    for (l.pieces[0..l.len]) |p| nearest = @min(nearest, p.along);
    var along: i32 = nearest;
    while (along <= farthest) : (along += 1) if (!columnClear(sb, world(cage, d, along, 0), base, @floatFromInt(tallest + 4))) return false;
    return true;
}

/// The first walkable surface below (x, y, z), or null over a drop.
fn floorAt(sb: *const Sandbox, x: f32, y: f32, z: f32) ?f32 {
    const hit = sb.physics.castRay(.{ x, y, z }, .{ 0, -1, 0 }, 12, .none) orelse return null;
    return if (hit.normal[1] > 0.7) hit.point[1] else null;
}

/// Half the width kept clear along every way through a plaza and every bridge deck.
pub const route_half_width: f32 = 5;
/// Kept clear around each plaza centre, where routes meet.
pub const hub_radius: f32 = 7;

fn segmentDistance(x: f32, z: f32, a: [3]f32, b: [3]f32) f32 {
    const abx = b[0] - a[0];
    const abz = b[2] - a[2];
    const len2 = abx * abx + abz * abz;
    const t = if (len2 == 0) 0 else std.math.clamp(((x - a[0]) * abx + (z - a[2]) * abz) / len2, 0, 1);
    const px = a[0] + abx * t - x;
    const pz = a[2] + abz * t - z;
    return @sqrt(px * px + pz * pz);
}

/// On a way people, cars and the rover use: a plaza's hub, the line from its centre to each bridge
/// it has, or a bridge deck. A bridge a player adds later through a challenge is a known gap.
pub fn onRoute(sb: *const Sandbox, x: f32, z: f32) bool {
    const District = @import("../procedural/District.zig");
    const city = &sb.catalog.district;
    var edges: [District.base_edge_count + District.max_bridges]District.Edge = undefined;
    var n: usize = 0;
    for (city.edges) |edge| {
        edges[n] = edge;
        n += 1;
    }
    for (sb.bridges) |maybe| if (maybe) |bridge| {
        edges[n] = bridge.edge;
        n += 1;
    };
    for (city.nodes) |node| {
        const dx = x - node.position[0];
        const dz = z - node.position[2];
        if (dx * dx + dz * dz < hub_radius * hub_radius) return true;
    }
    for (city.nodes, 0..) |node, i| if (node.tree != null) {
        // The walkway out to the plaza's Arbor trunk.
        if (segmentDistance(x, z, node.position, District.trunkSpur(city, i).b) < route_half_width) return true;
    };
    for (edges[0..n]) |edge| {
        // From one plaza's centre, over the deck, to the other's.
        const a = city.nodes[edge.a].position;
        const b = city.nodes[edge.b].position;
        if (segmentDistance(x, z, a, b) < route_half_width) return true;
    }
    return false;
}

fn columnClear(sb: *const Sandbox, c: [3]i32, base: f32, height: f32) bool {
    if (!sb.block_world.hasRoom(Blocks.chunkOf(c[0], c[2]))) return false;
    const x = @as(f32, @floatFromInt(c[0])) + 0.5;
    const z = @as(f32, @floatFromInt(c[2])) + 0.5;
    if (onRoute(sb, x, z)) return false;
    // The first surface a ray from the top of the column meets must be the floor near the base.
    const hit = sb.physics.castRay(.{ x, base + height, z }, .{ 0, -1, 0 }, height + 4, .none) orelse return false;
    return hit.normal[1] > 0.7 and @abs(hit.point[1] - base - 0.5) <= 1.5;
}

/// The course can be finished: from its first block to the plate, by `Course.reachable`.
pub fn finishable(sb: *const Sandbox, built: Built) bool {
    return Course.reachable(sb.block_world.blocks, built.start, built.plate) catch false;
}

test "every method maps to a challenge except the two landmark climbs" {
    var cages: usize = 0;
    for (CityContent.detroit.discoveries) |d| cages += @intFromBool(archetypeOf(d.method) != null);
    try std.testing.expectEqual(@as(usize, 8), cages);
}

test "each course fits its piece budget and keeps its plate within reach of the cage gates" {
    for (std.enums.values(Archetype)) |a| {
        const l = layout(a, 0).shifted(max_shift);
        try std.testing.expect(l.len > 0 and l.len <= max_pieces);
        // Every cage gate must lie within the plate's reach, or part of the cage stays shut.
        const plate: [3]f32 = .{ 0.5, @as(f32, @floatFromInt(l.plate[1])) + 0.5, @as(f32, @floatFromInt(l.plate[0])) + 0.5 };
        var dy: f32 = 1;
        while (dy <= 4) : (dy += 1) for ([_]f32{ -2, 2 }) |dx| for ([_]f32{ -2, 2 }) |dz| {
            const g: [3]f32 = .{ dx + 0.5 - plate[0], dy + 0.5 - plate[1], dz + 0.5 - plate[2] };
            try std.testing.expect(g[0] * g[0] + g[1] * g[1] + g[2] * g[2] <= Mesher.Hide.gate_reach * Mesher.Hide.gate_reach);
        };
    }
}
