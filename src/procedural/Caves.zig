//! Cave dungeons inside the mountain ranges. Each range holds two cave systems. A system opens
//! in a mouth on a lower flank and runs inward as a tree of chambers joined by tunnels,
//! descending under the mountain. The deepest chamber is the heart (a Hive nest guards it), dead
//! ends are caches (loot), and the rest are halls.
//!
//! A system is a signed distance field: ellipsoid chambers and capsule tunnels, each cut by a
//! flat floor, with rough walls from 3D value noise. The rock is what is under the terrain and
//! outside that field. `mesh` meshes the rock's surface with surface nets over a 1 m lattice
//! (watertight, one vertex per cell, quads across sign changes), evaluated only near the
//! chambers and tunnels.
//!
//! Where a cave breaks the surface (the mouth, or a chamber near the top), the streamed terrain
//! drops the heightfield triangles touching cave air (`openVertex`), and the cave mesh carries
//! the terrain's shape there instead, so the opening is one continuous surface.
//!
//! Physics: `hollow` tells the ground that a point is in cave air, so the terrain overhead is
//! ignored and the cave's mesh collider is the floor.
const std = @import("std");
const Seed = @import("Seed.zig");
const Noise = @import("Noise.zig");
const Mountains = @import("Mountains.zig");
const Biome = @import("Biome.zig");
const Mesh = @import("../render/Mesh.zig");

pub const V = [3]f32;
pub const per_range = 2;
pub const max_systems = Mountains.count * per_range;
pub const max_rooms = 7;
/// Lattice spacing of the cave mesh.
pub const cell: f32 = 1;
/// A terrain vertex this close to cave air is dropped from the heightfield.
pub const open_margin: f32 = 1;
/// Rock kept over every chamber but the first.
pub const min_cover: f32 = 7;
/// Tunnel floors sit this fraction of the radius below the centre line.
const floor_drop: f32 = 0.55;
/// How far past a chamber or tunnel the field is evaluated.
const evaluate_pad: f32 = 6;

pub const Role = enum { mouth, hall, cache, heart };
pub const Room = struct { center: V, radii: V, floor: f32, role: Role = .hall, parent: u8 = 0 };
pub const Tunnel = struct { a: V, b: V, radius: f32 };

pub const System = struct {
    range: u8,
    /// The mouth's floor point on the mountainside, and the horizontal direction into it.
    entrance: V,
    inward: V,
    rooms: [max_rooms]Room = undefined,
    room_count: u8 = 0,
    tunnels: [max_rooms]Tunnel = undefined,
    tunnel_count: u8 = 0,
    /// Bounds of all cave air, padded by the evaluation margin.
    lo: V = @splat(0),
    hi: V = @splat(0),
    noise: u64 = 0,

    pub fn contains(self: *const System, p: V) bool {
        for (0..3) |a| if (p[a] < self.lo[a] or p[a] > self.hi[a]) return false;
        return true;
    }

    pub fn heart(self: *const System) *const Room {
        for (self.rooms[0..self.room_count]) |*r| if (r.role == .heart) return r;
        return &self.rooms[self.room_count - 1];
    }
};

pub const Layout = struct {
    seed: u64,
    systems: [max_systems]System = undefined,
    count: u8 = 0,
};

fn add(a: V, b: V) V {
    return .{ a[0] + b[0], a[1] + b[1], a[2] + b[2] };
}
fn sub(a: V, b: V) V {
    return .{ a[0] - b[0], a[1] - b[1], a[2] - b[2] };
}
fn scale(a: V, s: f32) V {
    return .{ a[0] * s, a[1] * s, a[2] * s };
}
fn dot(a: V, b: V) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
fn length(a: V) f32 {
    return @sqrt(dot(a, a));
}

/// 3D value noise in [0, 1].
fn noise3(seed: u64, x: f32, y: f32, z: f32) f32 {
    const ix: i64 = @intFromFloat(@floor(x));
    const iy: i64 = @intFromFloat(@floor(y));
    const iz: i64 = @intFromFloat(@floor(z));
    const f: V = .{ x - @floor(x), y - @floor(y), z - @floor(z) };
    const s: V = .{ f[0] * f[0] * (3 - 2 * f[0]), f[1] * f[1] * (3 - 2 * f[1]), f[2] * f[2] * (3 - 2 * f[2]) };
    var corners: [8]f32 = undefined;
    for (0..8) |c| {
        const dx: i64 = @intCast(c & 1);
        const dy: i64 = @intCast(c >> 1 & 1);
        const dz: i64 = @intCast(c >> 2 & 1);
        corners[c] = Seed.unit(Seed.mix(Seed.at(seed ^ @as(u64, @bitCast(iy + dy)) *% 0x2545f4914f6cdd1d, ix + dx, iz + dz)));
    }
    const x00 = corners[0] + (corners[1] - corners[0]) * s[0];
    const x10 = corners[2] + (corners[3] - corners[2]) * s[0];
    const x01 = corners[4] + (corners[5] - corners[4]) * s[0];
    const x11 = corners[6] + (corners[7] - corners[6]) * s[0];
    const y0 = x00 + (x10 - x00) * s[1];
    const y1 = x01 + (x11 - x01) * s[1];
    return y0 + (y1 - y0) * s[2];
}

// ---------------------------------------------------------------- layout

/// Terrain streaming asks for the layout on its worker threads: each keeps the last seed's.
threadlocal var cached_seed: ?u64 = null;
threadlocal var cached_layout: Layout = undefined;

pub fn cached(seed: u64) *const Layout {
    if (cached_seed == null or cached_seed.? != seed) {
        cached_layout = layout(seed);
        cached_seed = seed;
    }
    return &cached_layout;
}

fn terrain(seed: u64, x: f32, z: f32) f32 {
    return Noise.height(seed, x, z);
}

/// The cave systems for a seed: a few thousand terrain samples, well under a millisecond in
/// release builds. Deterministic.
pub fn layout(seed: u64) Layout {
    var result: Layout = .{ .seed = seed };
    const ranges = Mountains.ranges(seed);
    for (ranges, 0..) |range, ri| for (0..per_range) |k| {
        const s = Seed.mix(seed ^ 0x43415645 ^ (@as(u64, ri) << 8) ^ @as(u64, k));
        if (plan(seed, s, @intCast(ri), range, k)) |system| {
            result.systems[result.count] = system;
            result.count += 1;
        }
    };
    return result;
}

fn plan(seed: u64, s: u64, ri: u8, range: Mountains.Range, k: usize) ?System {
    // A spine point a third of the way from either end, and a flank on alternating sides.
    const along = if (k == 0) @as(f32, 0.3) else 0.68;
    const t = along * (Mountains.spine_points - 1);
    const i = @min(Mountains.spine_points - 2, @as(usize, @intFromFloat(t)));
    const f = t - @as(f32, @floatFromInt(i));
    const a = range.spine[i];
    const b = range.spine[i + 1];
    const spine: [2]f32 = .{ a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f };
    const dl = @sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1]));
    const sign: f32 = if ((k + ri) % 2 == 0) 1 else -1;
    const out: [2]f32 = .{ (b[1] - a[1]) / dl * sign, -(b[0] - a[0]) / dl * sign };
    // Walk in from the flank's foot to the first point a quarter of the way up the massif.
    var d = range.half_width * 0.95;
    var mouth: ?[2]f32 = null;
    while (d > range.half_width * 0.25) : (d -= 6) {
        const x = spine[0] + out[0] * d;
        const z = spine[1] + out[1] * d;
        if (Mountains.height(seed, x, z) > range.peak * 0.22) {
            mouth = .{ x, z };
            break;
        }
    }
    const m = mouth orelse return null;
    const inward: V = .{ -out[0], 0, -out[1] };
    var sys: System = .{ .range = ri, .entrance = .{ m[0], terrain(seed, m[0], m[1]), m[1] }, .inward = inward, .noise = Seed.mix(s ^ 0x524f434b) };
    var random_state = std.Random.DefaultPrng.init(s);
    const random = random_state.random();

    // The mouth chamber, a short way in.
    const first_at = add(sys.entrance, scale(inward, 22));
    const first_floor = sys.entrance[1] - 1.5;
    const first_radii: V = .{ 9, 5.5, 9 };
    sys.rooms[0] = .{ .center = .{ first_at[0], first_floor + first_radii[1] * 0.45, first_at[2] }, .radii = first_radii, .floor = first_floor, .role = .mouth };
    sys.room_count = 1;
    // The mouth tunnel starts outside, in the open air, at the mouth's floor level.
    const mouth_radius: f32 = 3;
    sys.tunnels[0] = .{ .a = add(.{ sys.entrance[0], sys.entrance[1] + mouth_radius * floor_drop, sys.entrance[2] }, scale(inward, -6)), .b = .{ first_at[0], first_floor + mouth_radius * floor_drop, first_at[2] }, .radius = mouth_radius };
    sys.tunnel_count = 1;

    // Grow the tree: each new chamber branches from an earlier one, onward and downward.
    var attempts: usize = 0;
    const target: u8 = 5 + @as(u8, @intCast(random.uintLessThan(u8, 3)));
    while (sys.room_count < target and attempts < 80) : (attempts += 1) {
        const parent_index: u8 = if (random.float(f32) < 0.6) sys.room_count - 1 else random.uintLessThan(u8, sys.room_count);
        const parent = sys.rooms[parent_index];
        const turn = (random.float(f32) * 2 - 1) * 1.3;
        const dir: V = .{ inward[0] * @cos(turn) - inward[2] * @sin(turn), 0, inward[0] * @sin(turn) + inward[2] * @cos(turn) };
        const distance = 26 + random.float(f32) * 10;
        const drop = @min(distance * 0.28, 2 + random.float(f32) * 7);
        const radii: V = .{ 7 + random.float(f32) * 6, 4.5 + random.float(f32) * 3, 7 + random.float(f32) * 6 };
        const at = add(parent.center, scale(dir, distance));
        const floor = parent.floor - drop;
        const room: Room = .{ .center = .{ at[0], floor + radii[1] * 0.45, at[2] }, .radii = radii, .floor = floor, .parent = parent_index };
        if (!fits(seed, &sys, room)) continue;
        const r: f32 = 2.6 + random.float(f32) * 0.8;
        sys.rooms[sys.room_count] = room;
        sys.tunnels[sys.tunnel_count] = .{ .a = .{ parent.center[0], parent.floor + r * floor_drop, parent.center[2] }, .b = .{ room.center[0], room.floor + r * floor_drop, room.center[2] }, .radius = r };
        sys.room_count += 1;
        sys.tunnel_count += 1;
    }
    if (sys.room_count < 4) return null;
    // Roles: the deepest chamber is the heart, other dead ends are caches.
    var deepest: u8 = 1;
    for (sys.rooms[1..sys.room_count], 1..) |r, j| if (r.floor < sys.rooms[deepest].floor) {
        deepest = @intCast(j);
    };
    for (sys.rooms[1..sys.room_count], 1..) |*r, j| {
        var leaf = true;
        for (sys.rooms[1..sys.room_count]) |other| if (other.parent == j) {
            leaf = false;
        };
        r.role = if (j == deepest) .heart else if (leaf) .cache else .hall;
    }
    bounds(&sys);
    return sys;
}

/// A chamber fits when it keeps rock overhead and stays apart from the others.
fn fits(seed: u64, sys: *const System, room: Room) bool {
    const reach = @max(room.radii[0], room.radii[2]);
    for (sys.rooms[0..sys.room_count]) |other| {
        const dx = other.center[0] - room.center[0];
        const dz = other.center[2] - room.center[2];
        if (@sqrt(dx * dx + dz * dz) < reach + @max(other.radii[0], other.radii[2]) + 4) return false;
    }
    const top = room.center[1] + room.radii[1] + min_cover;
    for ([_][2]f32{ .{ 0, 0 }, .{ 1, 0 }, .{ -1, 0 }, .{ 0, 1 }, .{ 0, -1 } }) |o| {
        if (terrain(seed, room.center[0] + o[0] * room.radii[0], room.center[2] + o[1] * room.radii[2]) < top) return false;
    }
    return true;
}

fn bounds(sys: *System) void {
    var lo: V = @splat(std.math.inf(f32));
    var hi: V = @splat(-std.math.inf(f32));
    for (sys.rooms[0..sys.room_count]) |r| for (0..3) |a| {
        lo[a] = @min(lo[a], r.center[a] - r.radii[a] - 2);
        hi[a] = @max(hi[a], r.center[a] + r.radii[a] + 2);
    };
    for (sys.tunnels[0..sys.tunnel_count]) |t| for (0..3) |a| {
        lo[a] = @min(lo[a], @min(t.a[a], t.b[a]) - t.radius - 2);
        hi[a] = @max(hi[a], @max(t.a[a], t.b[a]) + t.radius + 2);
    };
    sys.lo = sub(lo, @splat(evaluate_pad + 1));
    sys.hi = add(hi, @splat(evaluate_pad + 1));
}

// ---------------------------------------------------------------- field

fn roomDistance(sys: *const System, r: Room, p: V) f32 {
    const q: V = .{ (p[0] - r.center[0]) / r.radii[0], (p[1] - r.center[1]) / r.radii[1], (p[2] - r.center[2]) / r.radii[2] };
    const k = length(q);
    const least = @min(r.radii[0], @min(r.radii[1], r.radii[2]));
    const rough = (noise3(sys.noise, p[0] * 0.21, p[1] * 0.21, p[2] * 0.21) - 0.5) * 2.2;
    const shell = (k - 1) * least + rough;
    return @max(shell, r.floor - p[1]);
}

fn tunnelDistance(sys: *const System, t: Tunnel, p: V) f32 {
    const ab = sub(t.b, t.a);
    const along = std.math.clamp(dot(sub(p, t.a), ab) / dot(ab, ab), 0, 1);
    const center = add(t.a, scale(ab, along));
    const rough = (noise3(sys.noise ^ 0x54554e, p[0] * 0.3, p[1] * 0.3, p[2] * 0.3) - 0.5) * 1.2;
    const tube = length(sub(p, center)) - t.radius + rough;
    return @max(tube, center[1] - t.radius * floor_drop - p[1]);
}

/// Signed distance to the cave's air (negative inside the cave).
pub fn caveDistance(sys: *const System, p: V) f32 {
    var d = std.math.inf(f32);
    for (sys.rooms[0..sys.room_count]) |r| d = @min(d, roomDistance(sys, r, p));
    for (sys.tunnels[0..sys.tunnel_count]) |t| d = @min(d, tunnelDistance(sys, t, p));
    return d;
}

/// Inside any cave's air.
pub fn hollow(caves: *const Layout, p: V) bool {
    for (caves.systems[0..caves.count]) |*sys| {
        if (sys.contains(p) and caveDistance(sys, p) < 0) return true;
    }
    return false;
}

/// The cave system whose air holds `p`, if any.
pub fn systemAt(caves: *const Layout, p: V) ?u8 {
    for (caves.systems[0..caves.count], 0..) |*sys, i| {
        if (sys.contains(p) and caveDistance(sys, p) < 0) return @intCast(i);
    }
    return null;
}

/// Whether the terrain vertex at (x, height, z) touches cave air: the heightfield drops every
/// triangle with such a vertex, and the cave mesh fills the opening.
pub fn openVertex(caves: *const Layout, x: f32, y: f32, z: f32) bool {
    for (caves.systems[0..caves.count]) |*sys| {
        if (sys.contains(.{ x, y, z }) and caveDistance(sys, .{ x, y, z }) < open_margin) return true;
    }
    return false;
}

/// Whether the heightfield triangle under (x, z) was dropped (same split as `Terrain.surface`).
fn opened(caves: *const Layout, x: f32, z: f32) bool {
    const spacing = @import("Terrain.zig").spacing;
    const gx = @floor(x / spacing);
    const gz = @floor(z / spacing);
    const u = x / spacing - gx;
    const v = z / spacing - gz;
    const x0 = gx * spacing;
    const z0 = gz * spacing;
    const corners: [3][2]f32 = if (u + v <= 1)
        .{ .{ x0, z0 }, .{ x0 + spacing, z0 }, .{ x0, z0 + spacing } }
    else
        .{ .{ x0 + spacing, z0 }, .{ x0, z0 + spacing }, .{ x0 + spacing, z0 + spacing } };
    for (corners) |c| if (openVertex(caves, c[0], terrain(caves.seed, c[0], c[1]), c[1])) return true;
    return false;
}

/// Whether any heightfield vertex within 2 m of (x, z) is open: a cheap filter before `opened`.
fn openedNear(caves: *const Layout, x: f32, z: f32) bool {
    const spacing = @import("Terrain.zig").spacing;
    const gx = @floor(x / spacing) * spacing;
    const gz = @floor(z / spacing) * spacing;
    var dz: f32 = -spacing;
    while (dz <= spacing * 2) : (dz += spacing) {
        var dx: f32 = -spacing;
        while (dx <= spacing * 2) : (dx += spacing) {
            if (openVertex(caves, gx + dx, terrain(caves.seed, gx + dx, gz + dz), gz + dz)) return true;
        }
    }
    return false;
}

/// Whether a chunk's bounds (x, z) could hold an opened terrain vertex: lets terrain streaming
/// skip the per-vertex test almost everywhere.
pub fn nearChunk(caves: *const Layout, lo_x: f32, lo_z: f32, hi_x: f32, hi_z: f32) bool {
    for (caves.systems[0..caves.count]) |sys| {
        if (sys.hi[0] >= lo_x and sys.lo[0] <= hi_x and sys.hi[2] >= lo_z and sys.lo[2] <= hi_z) return true;
    }
    return false;
}

// ---------------------------------------------------------------- mesh

/// The rock field: negative in air (the cave's, or the open sky's above the terrain).
fn field(sys: *const System, p: V, ground: f32) f32 {
    return @min(caveDistance(sys, p), ground - p[1]);
}

const unset = std.math.nan(f32);

const Grid = struct {
    origin: V,
    n: [3]usize,
    values: []f32,
    ground: []f32,

    fn index(self: *const Grid, i: usize, j: usize, k: usize) usize {
        return (k * self.n[1] + j) * self.n[0] + i;
    }
    fn point(self: *const Grid, i: usize, j: usize, k: usize) V {
        return .{ self.origin[0] + @as(f32, @floatFromInt(i)) * cell, self.origin[1] + @as(f32, @floatFromInt(j)) * cell, self.origin[2] + @as(f32, @floatFromInt(k)) * cell };
    }
};

/// Rock colour: dark, banded with depth, lighter on floors.
fn rockColor(sys: *const System, p: V, up: f32) [3]f32 {
    const n = noise3(sys.noise ^ 0x434f4c, p[0] * 0.08, p[1] * 0.25, p[2] * 0.08);
    const base: [3]f32 = .{ 0.24 + n * 0.08, 0.22 + n * 0.06, 0.21 + n * 0.05 };
    const floor = std.math.clamp((up - 0.5) * 2, 0, 1);
    return .{ base[0] + floor * 0.1, base[1] + floor * 0.07, base[2] + floor * 0.04 };
}

/// The rock surface of system `index`, in world coordinates. The caller owns the mesh.
pub fn mesh(allocator: std.mem.Allocator, caves: *const Layout, index: u8) !Mesh {
    const sys = &caves.systems[index];
    const seed = caves.seed;
    var grid: Grid = .{ .origin = .{ @floor(sys.lo[0]), @floor(sys.lo[1]), @floor(sys.lo[2]) }, .n = undefined, .values = undefined, .ground = undefined };
    for (0..3) |a| grid.n[a] = @as(usize, @intFromFloat(@ceil((sys.hi[a] - grid.origin[a]) / cell))) + 1;
    grid.values = try allocator.alloc(f32, grid.n[0] * grid.n[1] * grid.n[2]);
    defer allocator.free(grid.values);
    @memset(grid.values, unset);
    grid.ground = try allocator.alloc(f32, grid.n[0] * grid.n[2]);
    defer allocator.free(grid.ground);
    @memset(grid.ground, unset);

    // Evaluate only near each chamber and tunnel.
    const Box = struct { lo: V, hi: V };
    var boxes: [max_rooms * 2]Box = undefined;
    var box_count: usize = 0;
    for (sys.rooms[0..sys.room_count]) |r| {
        boxes[box_count] = .{ .lo = sub(r.center, add(r.radii, @splat(evaluate_pad))), .hi = add(r.center, add(r.radii, @splat(evaluate_pad))) };
        box_count += 1;
    }
    for (sys.tunnels[0..sys.tunnel_count]) |t| {
        var lo: V = undefined;
        var hi: V = undefined;
        for (0..3) |a| {
            lo[a] = @min(t.a[a], t.b[a]) - t.radius - evaluate_pad;
            hi[a] = @max(t.a[a], t.b[a]) + t.radius + evaluate_pad;
        }
        boxes[box_count] = .{ .lo = lo, .hi = hi };
        box_count += 1;
    }
    for (boxes[0..box_count]) |box| {
        var lo: [3]usize = undefined;
        var hi: [3]usize = undefined;
        for (0..3) |a| {
            lo[a] = @intFromFloat(std.math.clamp(@floor((box.lo[a] - grid.origin[a]) / cell), 0, @as(f32, @floatFromInt(grid.n[a] - 1))));
            hi[a] = @intFromFloat(std.math.clamp(@ceil((box.hi[a] - grid.origin[a]) / cell), 0, @as(f32, @floatFromInt(grid.n[a] - 1))));
        }
        for (lo[2]..hi[2] + 1) |k| for (lo[0]..hi[0] + 1) |i| {
            const column = k * grid.n[0] + i;
            if (std.math.isNan(grid.ground[column])) {
                const p = grid.point(i, 0, k);
                grid.ground[column] = terrain(seed, p[0], p[2]);
            }
            for (lo[1]..hi[1] + 1) |j| {
                const at = grid.index(i, j, k);
                if (!std.math.isNan(grid.values[at])) continue;
                grid.values[at] = field(sys, grid.point(i, j, k), grid.ground[column]);
            }
        };
    }

    // One vertex per cell that the surface crosses (all eight corners evaluated).
    const cells: [3]usize = .{ grid.n[0] - 1, grid.n[1] - 1, grid.n[2] - 1 };
    const vertex_of = try allocator.alloc(u32, cells[0] * cells[1] * cells[2]);
    defer allocator.free(vertex_of);
    @memset(vertex_of, std.math.maxInt(u32));
    var vertices: std.ArrayList(Mesh.Vertex) = .empty;
    errdefer vertices.deinit(allocator);
    var indices: std.ArrayList(u32) = .empty;
    errdefer indices.deinit(allocator);
    const edges = [12][2]u3{ .{ 0, 1 }, .{ 2, 3 }, .{ 4, 5 }, .{ 6, 7 }, .{ 0, 2 }, .{ 1, 3 }, .{ 4, 6 }, .{ 5, 7 }, .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 } };
    for (0..cells[2]) |k| for (0..cells[1]) |j| for (0..cells[0]) |i| {
        var corner: [8]f32 = undefined;
        var inside: u8 = 0;
        var known = true;
        for (0..8) |c| {
            corner[c] = grid.values[grid.index(i + (c & 1), j + (c >> 1 & 1), k + (c >> 2 & 1))];
            if (std.math.isNan(corner[c])) known = false;
            if (corner[c] < 0) inside += 1;
        }
        if (!known or inside == 0 or inside == 8) continue;
        var sum: V = @splat(0);
        var crossings: f32 = 0;
        for (edges) |e| {
            const fa = corner[e[0]];
            const fb = corner[e[1]];
            if ((fa < 0) == (fb < 0)) continue;
            const t = fa / (fa - fb);
            const pa: V = .{ @floatFromInt(e[0] & 1), @floatFromInt(e[0] >> 1 & 1), @floatFromInt(e[0] >> 2 & 1) };
            const pb: V = .{ @floatFromInt(e[1] & 1), @floatFromInt(e[1] >> 1 & 1), @floatFromInt(e[1] >> 2 & 1) };
            sum = add(sum, add(pa, scale(sub(pb, pa), t)));
            crossings += 1;
        }
        const p = add(grid.point(i, j, k), scale(sum, cell / crossings));
        // Normals point into the air: down the field's gradient.
        const ground = terrain(seed, p[0], p[2]);
        const e: f32 = 0.35;
        const gx = field(sys, add(p, .{ e, 0, 0 }), terrain(seed, p[0] + e, p[2])) - field(sys, sub(p, .{ e, 0, 0 }), terrain(seed, p[0] - e, p[2]));
        const gy = field(sys, add(p, .{ 0, e, 0 }), ground) - field(sys, sub(p, .{ 0, e, 0 }), ground);
        const gz = field(sys, add(p, .{ 0, 0, e }), terrain(seed, p[0], p[2] + e)) - field(sys, sub(p, .{ 0, 0, e }), terrain(seed, p[0], p[2] - e));
        const gl = @max(1e-6, @sqrt(gx * gx + gy * gy + gz * gz));
        const normal: V = .{ -gx / gl, -gy / gl, -gz / gl };
        // The cave's own walls in rock colours; where the mesh stands in for open terrain, the
        // terrain's colours.
        const color = if (caveDistance(sys, p) < ground - p[1]) rockColor(sys, p, normal[1]) else Biome.terrainColor(seed, p[0], p[2], ground, @sqrt(normal[0] * normal[0] + normal[2] * normal[2]) / @max(0.05, normal[1]));
        vertex_of[(k * cells[1] + j) * cells[0] + i] = @intCast(vertices.items.len);
        try vertices.append(allocator, .{ .position = p, .normal = normal, .uv = .{ p[0] / 4, p[2] / 4 + p[1] / 4 }, .color = color });
    };

    // A quad across every lattice edge the surface crosses, around the four cells sharing it.
    // Skipped: open-sky terrain the heightfield still draws.
    for (0..grid.n[2]) |k| for (0..grid.n[1]) |j| for (0..grid.n[0]) |i| {
        const here: [3]usize = .{ i, j, k };
        const fa = grid.values[grid.index(i, j, k)];
        if (std.math.isNan(fa)) continue;
        for (0..3) |axis| {
            const u = (axis + 1) % 3;
            const v = (axis + 2) % 3;
            // The four cells around this edge must all exist.
            if (here[axis] >= cells[axis] or here[u] == 0 or here[v] == 0 or here[u] >= cells[u] or here[v] >= cells[v]) continue;
            var next = here;
            next[axis] += 1;
            const fb = grid.values[grid.index(next[0], next[1], next[2])];
            if (std.math.isNan(fb) or (fa < 0) == (fb < 0)) continue;
            const t = fa / (fa - fb);
            const crossing = add(grid.point(i, j, k), scale(sub(grid.point(next[0], next[1], next[2]), grid.point(i, j, k)), t));
            const ground = terrain(seed, crossing[0], crossing[2]);
            const cave_side = caveDistance(sys, crossing) < ground - crossing[1];
            // Open-sky ground is meshed only over the heightfield's hole (tested below).
            if (!cave_side and !openedNear(caves, crossing[0], crossing[2])) continue;
            var quad: [4]u32 = undefined;
            var complete = true;
            const offsets = [4][2]usize{ .{ 1, 1 }, .{ 0, 1 }, .{ 0, 0 }, .{ 1, 0 } };
            for (offsets, 0..) |o, q| {
                var c = here;
                c[u] -= o[0];
                c[v] -= o[1];
                const vi = vertex_of[(c[2] * cells[1] + c[1]) * cells[0] + c[0]];
                if (vi == std.math.maxInt(u32)) {
                    complete = false;
                    break;
                }
                quad[q] = vi;
            }
            if (!complete) continue;
            // A ground quad touching the hole anywhere is kept, so the rim has no gaps (it
            // overlaps the remaining heightfield slightly instead).
            if (!cave_side) {
                var touches = opened(caves, crossing[0], crossing[2]);
                for (quad) |q| touches = touches or opened(caves, vertices.items[q].position[0], vertices.items[q].position[2]);
                if (!touches) continue;
            }
            // (u-1,v-1) → (u,v-1) → (u,v) → (u-1,v) winds about +axis; face the air.
            const air_ahead = fb < 0;
            const order: [4]u32 = if (air_ahead) quad else .{ quad[3], quad[2], quad[1], quad[0] };
            try indices.appendSlice(allocator, &.{ order[0], order[1], order[2], order[0], order[2], order[3] });
        }
    };
    if (indices.items.len == 0) return error.EmptyCave;
    const owned_vertices = try vertices.toOwnedSlice(allocator);
    errdefer allocator.free(owned_vertices);
    return .{ .vertices = owned_vertices, .indices = try indices.toOwnedSlice(allocator) };
}

/// A physics mesh collider for system `index` (the same surface as `mesh`).
pub fn collider(allocator: std.mem.Allocator, physics: *@import("../physics/Physics.zig"), caves: *const Layout, index: u8, user: u32) !@import("../physics/Physics.zig").MeshCollider {
    const m = try mesh(allocator, caves, index);
    defer m.deinit(allocator);
    const positions = try allocator.alloc(V, m.vertices.len);
    defer allocator.free(positions);
    for (positions, m.vertices) |*p, v| p.* = v.position;
    return physics.createMesh(allocator, positions, m.indices, user);
}

// ---------------------------------------------------------------- content

/// Floor spots for loot and crystals: points on chamber floors, `count` per chamber, ringed
/// around its centre at `ring` of the way to its wall.
pub fn floorSpot(sys: *const System, room: u8, k: usize, count: usize, ring: f32) V {
    const r = sys.rooms[room];
    const a = (@as(f32, @floatFromInt(k)) + 0.37 * @as(f32, @floatFromInt(room))) / @as(f32, @floatFromInt(count)) * 2 * std.math.pi;
    return .{ r.center[0] + @sin(a) * r.radii[0] * ring, r.floor, r.center[2] + @cos(a) * r.radii[2] * ring };
}

/// A name for a cave system, for toasts and flags.
pub fn name(index: u8) []const u8 {
    const names = [_][]const u8{ "Hollowdeep", "Glimmerwell", "Stonethroat", "Ashen Vault", "Echo Halls", "Lumen Grotto", "Rimefang", "Sunken Choir" };
    return names[index % names.len];
}

test "every range opens cave systems with a mouth, chambers under rock, and a heart" {
    const seed: u64 = 0x4845415659;
    const caves = layout(seed);
    try std.testing.expect(caves.count >= Mountains.count);
    for (caves.systems[0..caves.count]) |*sys| {
        try std.testing.expect(sys.room_count >= 4);
        // The mouth is open: just outside it is air, and the tunnel inside is cave.
        const inside = add(sys.entrance, add(scale(sys.inward, 4), .{ 0, 1.5, 0 }));
        try std.testing.expect(caveDistance(sys, inside) < 0);
        try std.testing.expect(hollow(&caves, inside));
        // Every chamber but the mouth's has rock overhead, and floors descend to the heart.
        for (sys.rooms[1..sys.room_count]) |r| {
            try std.testing.expect(terrain(seed, r.center[0], r.center[2]) >= r.center[1] + r.radii[1] + min_cover - 0.01);
            try std.testing.expect(hollow(&caves, .{ r.center[0], r.floor + 1, r.center[2] }));
            try std.testing.expect(!hollow(&caves, .{ r.center[0], r.floor - 1, r.center[2] }));
        }
        try std.testing.expect(sys.heart().floor <= sys.rooms[0].floor);
    }
    // Same seed, same caves.
    const again = layout(seed);
    try std.testing.expectEqualDeep(caves.systems[0].rooms[0], again.systems[0].rooms[0]);
}

test "a cave mesh is closed around its air, faces into it, and carries floors to walk on" {
    const seed: u64 = 0x4845415659;
    const caves = layout(seed);
    const m = try mesh(std.testing.allocator, &caves, 0);
    defer m.deinit(std.testing.allocator);
    try std.testing.expect(m.vertices.len > 1000 and m.indices.len % 3 == 0);
    for (m.indices) |i| try std.testing.expect(i < m.vertices.len);
    const sys = &caves.systems[0];
    // A ray down from the middle of each chamber meets a floor facing up, about at its floor height.
    const TriangleMesh = @import("../physics/TriangleMesh.zig");
    const positions = try std.testing.allocator.alloc([3]f32, m.vertices.len);
    defer std.testing.allocator.free(positions);
    for (m.vertices, positions) |vtx, *p| p.* = vtx.position;
    var solid = try TriangleMesh.build(std.testing.allocator, positions, m.indices);
    defer solid.deinit();
    for (sys.rooms[0..sys.room_count], 0..) |r, i| {
        const hit = solid.raycast(.{ r.center[0], r.floor + 2, r.center[2] }, .{ 0, -1, 0 }, 6) orelse return error.NoFloor;
        try std.testing.expect(hit.normal[1] > 0.7);
        try std.testing.expectApproxEqAbs(r.floor, hit.point[1], 0.6);
        // And, under cover, a ceiling overhead facing down (the mouth chamber may be open).
        if (i == 0) continue;
        const up = solid.raycast(.{ r.center[0], r.floor + 1, r.center[2] }, .{ 0, 1, 0 }, 30) orelse return error.NoCeiling;
        try std.testing.expect(up.normal[1] < 0);
    }
}

test "where the heightfield opens over a cave, the cave mesh carries the ground" {
    const seed: u64 = 0x4845415659;
    const caves = layout(seed);
    const m = try mesh(std.testing.allocator, &caves, 0);
    defer m.deinit(std.testing.allocator);
    const TriangleMesh = @import("../physics/TriangleMesh.zig");
    const positions = try std.testing.allocator.alloc([3]f32, m.vertices.len);
    defer std.testing.allocator.free(positions);
    for (m.vertices, positions) |vtx, *p| p.* = vtx.position;
    var solid = try TriangleMesh.build(std.testing.allocator, positions, m.indices);
    defer solid.deinit();
    const sys = &caves.systems[0];
    var opened_count: usize = 0;
    var covered: usize = 0;
    var x = sys.entrance[0] - 24;
    while (x < sys.entrance[0] + 24) : (x += 0.7) {
        var z = sys.entrance[2] - 24;
        while (z < sys.entrance[2] + 24) : (z += 0.7) {
            if (!opened(&caves, x, z)) continue;
            opened_count += 1;
            const ground = terrain(seed, x, z);
            if (solid.raycast(.{ x, ground + 30, z }, .{ 0, -1, 0 }, 60)) |_| covered += 1;
        }
    }
    try std.testing.expect(opened_count > 20);
    try std.testing.expectEqual(opened_count, covered);
}
