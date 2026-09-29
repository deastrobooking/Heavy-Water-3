const std = @import("std");
const Mesh = @This();
pub const Vertex = extern struct { position: [3]f32, normal: [3]f32, uv: [2]f32 };
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
