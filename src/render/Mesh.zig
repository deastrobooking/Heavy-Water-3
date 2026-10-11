const std = @import("std");
const Mesh = @This();
pub const Vertex = extern struct { position: [3]f32, normal: [3]f32, uv: [2]f32, color: [3]f32 = .{ 1, 1, 1 } };
vertices: []Vertex,
indices: []u32,

pub fn deinit(self: Mesh, allocator: std.mem.Allocator) void {
    allocator.free(self.indices);
    allocator.free(self.vertices);
}

pub fn cube(allocator: std.mem.Allocator) !Mesh {
    const vertices = try allocator.alloc(Vertex, 24);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, 36);
    const normals = [6][3]f32{ .{ 0, 0, -1 }, .{ 0, 0, 1 }, .{ -1, 0, 0 }, .{ 1, 0, 0 }, .{ 0, 1, 0 }, .{ 0, -1, 0 } };
    const corners = [6][4][3]f32{
        .{ .{ -0.5, 0, -0.5 }, .{ -0.5, 2, -0.5 }, .{ 0.5, 2, -0.5 }, .{ 0.5, 0, -0.5 } },
        .{ .{ 0.5, 0, 0.5 }, .{ 0.5, 2, 0.5 }, .{ -0.5, 2, 0.5 }, .{ -0.5, 0, 0.5 } },
        .{ .{ -0.5, 0, 0.5 }, .{ -0.5, 2, 0.5 }, .{ -0.5, 2, -0.5 }, .{ -0.5, 0, -0.5 } },
        .{ .{ 0.5, 0, -0.5 }, .{ 0.5, 2, -0.5 }, .{ 0.5, 2, 0.5 }, .{ 0.5, 0, 0.5 } },
        .{ .{ -0.5, 2, -0.5 }, .{ -0.5, 2, 0.5 }, .{ 0.5, 2, 0.5 }, .{ 0.5, 2, -0.5 } },
        .{ .{ -0.5, 0, 0.5 }, .{ -0.5, 0, -0.5 }, .{ 0.5, 0, -0.5 }, .{ 0.5, 0, 0.5 } },
    };
    const uv = [4][2]f32{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 1 }, .{ 1, 0 } };
    for (0..6) |face| {
        for (0..4) |v| vertices[face * 4 + v] = .{ .position = corners[face][v], .normal = normals[face], .uv = uv[v] };
        for ([_]u32{ 0, 1, 2, 0, 2, 3 }, 0..) |offset, i| indices[face * 6 + i] = @as(u32, @intCast(face * 4)) + offset;
    }
    return .{ .vertices = vertices, .indices = indices };
}

/// Centered unit cube (-0.5..0.5 on each axis) for instances scaled per axis.
pub fn block(allocator: std.mem.Allocator) !Mesh {
    const mesh = try cube(allocator);
    for (mesh.vertices) |*v| v.position[1] = v.position[1] / 2 - 0.5;
    return mesh;
}

/// Unit-diameter, unit-width cylinder along X (a wheel). UVs stripe around the rim so spin
/// is visible under the checker texture.
pub fn wheel(allocator: std.mem.Allocator) !Mesh {
    const segments = 16;
    const vertices = try allocator.alloc(Vertex, segments * 4 + 4);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, segments * 12);
    for (0..segments + 1) |i| {
        const a = @as(f32, @floatFromInt(i)) / segments * 2 * std.math.pi;
        const y = @cos(a) * 0.5;
        const z = @sin(a) * 0.5;
        const v = @as(f32, @floatFromInt(i)) / segments * 8;
        vertices[i * 2] = .{ .position = .{ -0.5, y, z }, .normal = .{ 0, y * 2, z * 2 }, .uv = .{ 0, v } };
        vertices[i * 2 + 1] = .{ .position = .{ 0.5, y, z }, .normal = .{ 0, y * 2, z * 2 }, .uv = .{ 0.5, v } };
    }
    // Caps: one center vertex per side plus a ring.
    const cap = (segments + 1) * 2;
    for ([_]f32{ -0.5, 0.5 }, 0..) |x, side| {
        vertices[cap + side] = .{ .position = .{ x, 0, 0 }, .normal = .{ x * 2, 0, 0 }, .uv = .{ 0.25, 0.25 } };
    }
    const ring = cap + 2;
    for (0..segments) |i| {
        const a = @as(f32, @floatFromInt(i)) / segments * 2 * std.math.pi;
        for ([_]f32{ -0.5, 0.5 }, 0..) |x, side| {
            vertices[ring + i * 2 + side] = .{ .position = .{ x, @cos(a) * 0.5, @sin(a) * 0.5 }, .normal = .{ x * 2, 0, 0 }, .uv = .{ 0.25 + @cos(a) * 0.2, 0.25 + @sin(a) * 0.2 } };
        }
    }
    var n: usize = 0;
    for (0..segments) |i| {
        const a: u32 = @intCast(i * 2);
        for ([_]u32{ a, a + 2, a + 1, a + 1, a + 2, a + 3 }) |index| {
            indices[n] = index;
            n += 1;
        }
        const r0: u32 = @intCast(ring + i * 2);
        const r1: u32 = @intCast(ring + ((i + 1) % segments) * 2);
        for ([_]u32{ @intCast(cap), r1, r0, @intCast(cap + 1), r0 + 1, r1 + 1 }) |index| {
            indices[n] = index;
            n += 1;
        }
    }
    return .{ .vertices = vertices, .indices = indices };
}

/// Smooth sphere of unit diameter, centred on the origin. UVs are all zero so the surface checker
/// never patterns it (pets and other puppets tint it per part).
pub fn orb(allocator: std.mem.Allocator) !Mesh {
    const rows = 10;
    const cols = 16;
    const vertices = try allocator.alloc(Vertex, (rows + 1) * (cols + 1));
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, rows * cols * 6);
    for (0..rows + 1) |r| for (0..cols + 1) |c| {
        const lat = std.math.pi * @as(f32, @floatFromInt(r)) / rows;
        const lon = 2 * std.math.pi * @as(f32, @floatFromInt(c)) / cols;
        const n = [3]f32{ @sin(lat) * @cos(lon), @cos(lat), @sin(lat) * @sin(lon) };
        vertices[r * (cols + 1) + c] = .{ .position = .{ n[0] * 0.5, n[1] * 0.5, n[2] * 0.5 }, .normal = n, .uv = .{ 0, 0 } };
    };
    var k: usize = 0;
    for (0..rows) |r| for (0..cols) |c| {
        const a: u32 = @intCast(r * (cols + 1) + c);
        const b: u32 = a + cols + 1;
        for ([_]u32{ a, b, a + 1, a + 1, b, b + 1 }) |i| {
            indices[k] = i;
            k += 1;
        }
    };
    return .{ .vertices = vertices, .indices = indices };
}

/// A smooth cone of unit base diameter: base at the origin, tip at +y (ears, beaks, horns).
pub fn spike(allocator: std.mem.Allocator) !Mesh {
    const sides = 12;
    const vertices = try allocator.alloc(Vertex, sides * 2 + 1);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, sides * 6);
    const slope = 0.5;
    for (0..sides) |i| {
        const a = @as(f32, @floatFromInt(i)) / sides * 2 * std.math.pi;
        const n = [3]f32{ @cos(a), slope, @sin(a) };
        const l = @sqrt(1 + slope * slope);
        vertices[i] = .{ .position = .{ @cos(a) * 0.5, 0, @sin(a) * 0.5 }, .normal = .{ n[0] / l, n[1] / l, n[2] / l }, .uv = .{ 0, 0 } };
        vertices[sides + i] = .{ .position = .{ 0, 1, 0 }, .normal = .{ n[0] / l, n[1] / l, n[2] / l }, .uv = .{ 0, 0 } };
    }
    vertices[sides * 2] = .{ .position = .{ 0, 0, 0 }, .normal = .{ 0, -1, 0 }, .uv = .{ 0, 0 } };
    for (0..sides) |i| {
        const next: u32 = @intCast((i + 1) % sides);
        const at: u32 = @intCast(i);
        for ([_]u32{ at, sides + at, next, next, sides * 2, at }, 0..) |v, j| indices[i * 6 + j] = v;
    }
    return .{ .vertices = vertices, .indices = indices };
}

/// A faceted, six-sided alien shrub. Shared by all vegetation instances.
pub fn vegetation(allocator: std.mem.Allocator) !Mesh {
    const vertices = try allocator.alloc(Vertex, 18);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, 18);
    for (0..6) |i| {
        const a = @as(f32, @floatFromInt(i)) * std.math.pi / 3;
        const b = @as(f32, @floatFromInt(i + 1)) * std.math.pi / 3;
        const p = [3]f32{ @cos(a) * 0.8, 0, @sin(a) * 0.8 };
        const q = [3]f32{ @cos(b) * 0.8, 0, @sin(b) * 0.8 };
        const mid = (a + b) / 2;
        const normal = [3]f32{ @cos(mid) * 0.94, 0.341, @sin(mid) * 0.94 };
        vertices[i * 3] = .{ .position = p, .normal = normal, .uv = .{ 0, 0 } };
        vertices[i * 3 + 1] = .{ .position = .{ 0, 2, 0 }, .normal = normal, .uv = .{ 0.5, 1 } };
        vertices[i * 3 + 2] = .{ .position = q, .normal = normal, .uv = .{ 1, 0 } };
    }
    for (indices, 0..) |*v, i| v.* = @intCast(i);
    return .{ .vertices = vertices, .indices = indices };
}
