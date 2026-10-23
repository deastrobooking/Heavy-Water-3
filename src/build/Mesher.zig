//! Turns the block grid of one terrain chunk column into a flat-shaded mesh (for drawing) and the
//! same triangles in world space (for the collider). Faces lying on a cell boundary are dropped
//! when the neighbour's face there is solid, so a wall of cubes is a single shell.
//! Mesh positions are relative to the chunk centre at y = 0 (`origin`).
const std = @import("std");
const Blocks = @import("Blocks.zig");
const Materials = @import("Materials.zig");
const Mesh = @import("../render/Mesh.zig");
const ChunkKey = @import("../world/ChunkKey.zig");

pub const Dir = enum(u3) {
    px,
    nx,
    py,
    ny,
    pz,
    nz,

    pub fn vector(self: Dir) [3]i32 {
        return switch (self) {
            .px => .{ 1, 0, 0 },
            .nx => .{ -1, 0, 0 },
            .py => .{ 0, 1, 0 },
            .ny => .{ 0, -1, 0 },
            .pz => .{ 0, 0, 1 },
            .nz => .{ 0, 0, -1 },
        };
    }
    pub fn opposite(self: Dir) Dir {
        return switch (self) {
            .px => .nx,
            .nx => .px,
            .py => .ny,
            .ny => .py,
            .pz => .nz,
            .nz => .pz,
        };
    }
    /// The direction after `rot` quarter turns, the same turn `rotatePoint` applies.
    pub fn turned(self: Dir, rot: u2) Dir {
        var d = self;
        for (0..rot) |_| d = switch (d) {
            .pz => .px,
            .px => .nz,
            .nz => .nx,
            .nx => .pz,
            else => d,
        };
        return d;
    }
};

const V = [3]f32;
const Polygon = struct {
    points: [4]V,
    len: u3 = 4,
    normal: V,
    /// The cell face this polygon lies on, if it lies on one.
    plane: ?Dir = null,
    /// It covers that whole face, so it hides the neighbour's face there.
    full: bool = false,
};

fn quad(a: V, b: V, c: V, d: V, normal: V, plane: ?Dir, full: bool) Polygon {
    return .{ .points = .{ a, b, c, d }, .normal = normal, .plane = plane, .full = full };
}

fn tri(a: V, b: V, c: V, normal: V, plane: ?Dir) Polygon {
    return .{ .points = .{ a, b, c, c }, .len = 3, .normal = normal, .plane = plane };
}

/// An axis-aligned box's faces; a face on the cell boundary is tagged with its plane.
fn box(comptime lo: V, comptime hi: V) [6]Polygon {
    const full_x = lo[1] == 0 and hi[1] == 1 and lo[2] == 0 and hi[2] == 1;
    const full_y = lo[0] == 0 and hi[0] == 1 and lo[2] == 0 and hi[2] == 1;
    const full_z = lo[0] == 0 and hi[0] == 1 and lo[1] == 0 and hi[1] == 1;
    return .{
        quad(.{ hi[0], lo[1], lo[2] }, .{ hi[0], hi[1], lo[2] }, .{ hi[0], hi[1], hi[2] }, .{ hi[0], lo[1], hi[2] }, .{ 1, 0, 0 }, if (hi[0] == 1) .px else null, full_x and hi[0] == 1),
        quad(.{ lo[0], lo[1], lo[2] }, .{ lo[0], lo[1], hi[2] }, .{ lo[0], hi[1], hi[2] }, .{ lo[0], hi[1], lo[2] }, .{ -1, 0, 0 }, if (lo[0] == 0) .nx else null, full_x and lo[0] == 0),
        quad(.{ lo[0], hi[1], lo[2] }, .{ lo[0], hi[1], hi[2] }, .{ hi[0], hi[1], hi[2] }, .{ hi[0], hi[1], lo[2] }, .{ 0, 1, 0 }, if (hi[1] == 1) .py else null, full_y and hi[1] == 1),
        quad(.{ lo[0], lo[1], lo[2] }, .{ hi[0], lo[1], lo[2] }, .{ hi[0], lo[1], hi[2] }, .{ lo[0], lo[1], hi[2] }, .{ 0, -1, 0 }, if (lo[1] == 0) .ny else null, full_y and lo[1] == 0),
        quad(.{ lo[0], lo[1], hi[2] }, .{ hi[0], lo[1], hi[2] }, .{ hi[0], hi[1], hi[2] }, .{ lo[0], hi[1], hi[2] }, .{ 0, 0, 1 }, if (hi[2] == 1) .pz else null, full_z and hi[2] == 1),
        quad(.{ lo[0], lo[1], lo[2] }, .{ lo[0], hi[1], lo[2] }, .{ hi[0], hi[1], lo[2] }, .{ hi[0], lo[1], lo[2] }, .{ 0, 0, -1 }, if (lo[2] == 0) .nz else null, full_z and lo[2] == 0),
    };
}

const cube_polygons = box(.{ 0, 0, 0 }, .{ 1, 1, 1 });
const slab_polygons = box(.{ 0, 0, 0 }, .{ 1, 0.5, 1 });
/// A narrow, full-height glazing panel; quarter-turn rotation changes its facing direction.
const pane_polygons = box(.{ 0, 0, 0.46 }, .{ 1, 1, 0.54 });
const s2 = 0.70710678;
/// Rises from the front (z = 0) to the back (z = 1).
const ramp_polygons = [_]Polygon{
    quad(.{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 0, 1 }, .{ 0, 0, 1 }, .{ 0, -1, 0 }, .ny, true),
    quad(.{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 1, 1 }, .{ 0, 1, 1 }, .{ 0, 0, 1 }, .pz, true),
    quad(.{ 0, 0, 0 }, .{ 0, 1, 1 }, .{ 1, 1, 1 }, .{ 1, 0, 0 }, .{ 0, s2, -s2 }, null, false),
    tri(.{ 0, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 1, 1 }, .{ -1, 0, 0 }, .nx),
    tri(.{ 1, 0, 0 }, .{ 1, 1, 1 }, .{ 1, 0, 1 }, .{ 1, 0, 0 }, .px),
};
/// Two steps climbing toward the back.
const stair_polygons = [_]Polygon{
    quad(.{ 0, 0, 0 }, .{ 1, 0, 0 }, .{ 1, 0, 1 }, .{ 0, 0, 1 }, .{ 0, -1, 0 }, .ny, true),
    quad(.{ 0, 0, 1 }, .{ 1, 0, 1 }, .{ 1, 1, 1 }, .{ 0, 1, 1 }, .{ 0, 0, 1 }, .pz, true),
    quad(.{ 0, 0, 0 }, .{ 0, 0.5, 0 }, .{ 1, 0.5, 0 }, .{ 1, 0, 0 }, .{ 0, 0, -1 }, .nz, false),
    quad(.{ 0, 0.5, 0 }, .{ 0, 0.5, 0.5 }, .{ 1, 0.5, 0.5 }, .{ 1, 0.5, 0 }, .{ 0, 1, 0 }, null, false),
    quad(.{ 0, 0.5, 0.5 }, .{ 0, 1, 0.5 }, .{ 1, 1, 0.5 }, .{ 1, 0.5, 0.5 }, .{ 0, 0, -1 }, null, false),
    quad(.{ 0, 1, 0.5 }, .{ 0, 1, 1 }, .{ 1, 1, 1 }, .{ 1, 1, 0.5 }, .{ 0, 1, 0 }, .py, false),
    quad(.{ 0, 0, 0 }, .{ 0, 0, 1 }, .{ 0, 0.5, 1 }, .{ 0, 0.5, 0 }, .{ -1, 0, 0 }, .nx, false),
    quad(.{ 0, 0.5, 0.5 }, .{ 0, 0.5, 1 }, .{ 0, 1, 1 }, .{ 0, 1, 0.5 }, .{ -1, 0, 0 }, .nx, false),
    quad(.{ 1, 0, 0 }, .{ 1, 0.5, 0 }, .{ 1, 0.5, 1 }, .{ 1, 0, 1 }, .{ 1, 0, 0 }, .px, false),
    quad(.{ 1, 0.5, 0.5 }, .{ 1, 1, 0.5 }, .{ 1, 1, 1 }, .{ 1, 0.5, 1 }, .{ 1, 0, 0 }, .px, false),
};

fn polygons(shape: Blocks.Shape) []const Polygon {
    return switch (shape) {
        .cube => &cube_polygons,
        .slab => &slab_polygons,
        .ramp => &ramp_polygons,
        .stair => &stair_polygons,
        .pane => &pane_polygons,
        else => &.{},
    };
}

/// What the character collides with. Stairs collide as a ramp: each step is half a metre, above
/// the character's 0.4 m step, and the 45 degree slope is walkable.
fn collisionPolygons(shape: Blocks.Shape) []const Polygon {
    return if (shape == .stair) &ramp_polygons else polygons(shape);
}

pub const Purpose = enum { draw, collide };

/// Cells left out of the static mesh: movers (drawn and collided as moving bodies), gates near a
/// pressed plate, and the given cells (crumbled blocks). Hidden cells count as empty to neighbours.
pub const Hide = struct {
    cells: []const [3]i32 = &.{},
    /// Centres of plates holding their gates open.
    plates: []const [3]f32 = &.{},

    /// How far a plate's reach extends: gates within this many metres open with it.
    /// Gates within this distance of a pressed plate open. Wide enough for a discovery course
    /// whose plate stands 23 m above its cage (`Challenges.plate_height`).
    pub const gate_reach: f32 = 28;

    pub fn hides(self: Hide, cell: Blocks.Cell, x: i32, y: i32, z: i32) bool {
        if (cell.isEmpty()) return false;
        if (cell.material == Materials.ofRole(.platformer, .color)) return true;
        if (cell.material == Materials.ofRole(.platformer, .metal)) {
            const c: [3]f32 = .{ @as(f32, @floatFromInt(x)) + 0.5, @as(f32, @floatFromInt(y)) + 0.5, @as(f32, @floatFromInt(z)) + 0.5 };
            for (self.plates) |p| {
                const d: [3]f32 = .{ c[0] - p[0], c[1] - p[1], c[2] - p[2] };
                if (d[0] * d[0] + d[1] * d[1] + d[2] * d[2] <= gate_reach * gate_reach) return true;
            }
        }
        for (self.cells) |c| if (c[0] == x and c[1] == y and c[2] == z) return true;
        return false;
    }

    fn get(self: Hide, blocks: *const Blocks, x: i32, y: i32, z: i32) Blocks.Cell {
        const cell = blocks.get(x, y, z);
        return if (self.hides(cell, x, y, z)) .empty else cell;
    }
};

/// Whether the cell's face in world direction `dir` is solid over the whole face.
pub fn fullFace(cell: Blocks.Cell, dir: Dir) bool {
    if (cell.isEmpty()) return false;
    for (polygons(cell.shape)) |p| if (p.full and p.plane.?.turned(cell.rot) == dir) return true;
    return false;
}

fn rotatePoint(p: V, rot: u2) V {
    var q = p;
    for (0..rot) |_| {
        const prev = q; // a result-location init would read its own half-written fields
        q = .{ prev[2], prev[1], 1 - prev[0] };
    }
    return q;
}

fn rotateVector(v: V, rot: u2) V {
    var q = v;
    for (0..rot) |_| {
        const prev = q;
        q = .{ prev[2], prev[1], -prev[0] };
    }
    return q;
}

pub fn origin(key: ChunkKey) V {
    return .{ @as(f32, @floatFromInt(key.x)) * ChunkKey.extent, 0, @as(f32, @floatFromInt(key.z)) * ChunkKey.extent };
}

pub const Output = struct {
    vertices: std.ArrayList(Mesh.Vertex) = .empty,
    indices: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *Output, allocator: std.mem.Allocator) void {
        self.vertices.deinit(allocator);
        self.indices.deinit(allocator);
    }
};

/// Mesh every block in the chunk column `key` into `out` (cleared first).
pub fn meshChunk(allocator: std.mem.Allocator, blocks: *const Blocks, key: ChunkKey, purpose: Purpose, hide: Hide, out: *Output) !void {
    out.vertices.clearRetainingCapacity();
    out.indices.clearRetainingCapacity();
    const o = origin(key);
    var buffer: [Blocks.section_capacity]usize = undefined;
    for (blocks.sectionsIn(key, &buffer)) |i| {
        const section = blocks.sectionAt(i);
        for (section.cells, 0..) |cell, n| {
            if (cell.isEmpty()) continue;
            const lx: i32 = @intCast(n % Blocks.side);
            const lz: i32 = @intCast(n / Blocks.side % Blocks.side);
            const ly: i32 = @intCast(n / (Blocks.side * Blocks.side));
            const x = section.key.x * Blocks.side + lx;
            const y = section.key.y * Blocks.side + ly;
            const z = section.key.z * Blocks.side + lz;
            if (hide.hides(cell, x, y, z)) continue;
            try emitCell(allocator, blocks, cell, x, y, z, o, purpose, hide, out);
        }
    }
}

fn emitCell(allocator: std.mem.Allocator, blocks: *const Blocks, cell: Blocks.Cell, x: i32, y: i32, z: i32, o: V, purpose: Purpose, hide: Hide, out: *Output) !void {
    const color = Materials.shade(cell.material, x, y, z);
    const base: V = .{ @as(f32, @floatFromInt(x)) - o[0], @floatFromInt(y), @as(f32, @floatFromInt(z)) - o[2] };
    for (if (purpose == .collide) collisionPolygons(cell.shape) else polygons(cell.shape)) |p| {
        if (p.plane) |plane| {
            const dir = plane.turned(cell.rot);
            const d = dir.vector();
            if (fullFace(hide.get(blocks, x + d[0], y + d[1], z + d[2]), dir.opposite())) continue;
        }
        const normal = rotateVector(p.normal, cell.rot);
        const first: u32 = @intCast(out.vertices.items.len);
        for (p.points[0..p.len]) |point| {
            const r = rotatePoint(point, cell.rot);
            try out.vertices.append(allocator, .{
                .position = .{ base[0] + r[0], base[1] + r[1], base[2] + r[2] },
                .normal = normal,
                .uv = .{ r[0] + r[2], r[1] },
                .color = color,
            });
        }
        // Wind each triangle counter-clockwise around the outward normal.
        const tris: []const [3]u32 = if (p.len == 4) &.{ .{ 0, 1, 2 }, .{ 0, 2, 3 } } else &.{.{ 0, 1, 2 }};
        for (tris) |t| {
            const a = out.vertices.items[first + t[0]].position;
            const b = out.vertices.items[first + t[1]].position;
            const c = out.vertices.items[first + t[2]].position;
            const e1: V = .{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
            const e2: V = .{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
            const cross: V = .{ e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
            const outward = cross[0] * normal[0] + cross[1] * normal[1] + cross[2] * normal[2] >= 0;
            if (outward) {
                try out.indices.appendSlice(allocator, &.{ first + t[0], first + t[1], first + t[2] });
            } else try out.indices.appendSlice(allocator, &.{ first + t[0], first + t[2], first + t[1] });
        }
    }
}

test "a lone cube has six faces and two touching cubes hide the shared pair" {
    const a = std.testing.allocator;
    const b = try Blocks.create(a);
    defer b.destroy();
    var out: Output = .{};
    defer out.deinit(a);
    try b.set(0, 0, 0, .{ .shape = .cube });
    try meshChunk(a, b, .{ .x = 0, .z = 0 }, .draw, .{}, &out);
    try std.testing.expectEqual(@as(usize, 12), out.indices.items.len / 3);
    try b.set(1, 0, 0, .{ .shape = .cube });
    try meshChunk(a, b, .{ .x = 0, .z = 0 }, .draw, .{}, &out);
    try std.testing.expectEqual(@as(usize, 20), out.indices.items.len / 3);
}

test "a slab does not hide the cube face above it, and turned ramps show their back to a neighbour" {
    const a = std.testing.allocator;
    const b = try Blocks.create(a);
    defer b.destroy();
    var out: Output = .{};
    defer out.deinit(a);
    try b.set(0, 1, 0, .{ .shape = .cube });
    try b.set(0, 0, 0, .{ .shape = .slab });
    try meshChunk(a, b, .{ .x = 0, .z = 0 }, .draw, .{}, &out);
    // Cube keeps all 6 faces (the slab's top is not full); slab keeps its 6 too.
    try std.testing.expectEqual(@as(usize, 24), out.indices.items.len / 3);
    // A ramp turned once faces its full back toward +x.
    try std.testing.expect(fullFace(.{ .shape = .ramp, .rot = 1 }, .px));
    try std.testing.expect(!fullFace(.{ .shape = .ramp, .rot = 1 }, .pz));
    try std.testing.expect(fullFace(.{ .shape = .ramp, .rot = 0 }, .pz));
}

test "every emitted triangle faces outward from its cell" {
    const a = std.testing.allocator;
    const b = try Blocks.create(a);
    defer b.destroy();
    var out: Output = .{};
    defer out.deinit(a);
    const shapes = Blocks.placeable_shapes;
    for (shapes, 0..) |shape, i| for (0..4) |r| try b.set(@intCast(i * 3), 0, @intCast(r * 3), .{ .shape = shape, .rot = @intCast(r) });
    try meshChunk(a, b, .{ .x = 0, .z = 0 }, .draw, .{}, &out);
    var i: usize = 0;
    while (i < out.indices.items.len) : (i += 3) {
        const p0 = out.vertices.items[out.indices.items[i]];
        const p1 = out.vertices.items[out.indices.items[i + 1]].position;
        const p2 = out.vertices.items[out.indices.items[i + 2]].position;
        const e1: V = .{ p1[0] - p0.position[0], p1[1] - p0.position[1], p1[2] - p0.position[2] };
        const e2: V = .{ p2[0] - p0.position[0], p2[1] - p0.position[1], p2[2] - p0.position[2] };
        const cross: V = .{ e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0] };
        try std.testing.expect(cross[0] * p0.normal[0] + cross[1] * p0.normal[1] + cross[2] * p0.normal[2] > 0);
        // The normal points away from the centre of the cell the triangle belongs to.
        const face: V = .{ (p0.position[0] + p1[0] + p2[0]) / 3, (p0.position[1] + p1[1] + p2[1]) / 3, (p0.position[2] + p1[2] + p2[2]) / 3 };
        const cx = @floor(face[0] - 0.01 * p0.normal[0]) + 0.5;
        const cz = @floor(face[2] - 0.01 * p0.normal[2]) + 0.5;
        try std.testing.expect((face[0] - cx) * p0.normal[0] + (face[1] - 0.5) * p0.normal[1] + (face[2] - cz) * p0.normal[2] > -0.01);
    }
}
