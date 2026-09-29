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
