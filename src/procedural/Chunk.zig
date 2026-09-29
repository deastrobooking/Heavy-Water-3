const std = @import("std");
const Noise = @import("Noise.zig");
const Biome = @import("Biome.zig");
const Mesh = @import("../render/Mesh.zig");
pub const cells = 64;
pub const extent = @import("../world/ChunkKey.zig").extent;
pub const vertex_count = (cells + 1) * (cells + 1);
pub const index_count = cells * cells * 6;
pub const Cancel = struct { token: *const std.atomic.Value(u64), expected: u64 };

/// Coordinates are integer chunk addresses; shared edges sample identical world positions.
pub fn generate(allocator: std.mem.Allocator, seed: u64, cx: i32, cz: i32) !Mesh {
    const vertices = try allocator.alloc(Mesh.Vertex, (cells + 1) * (cells + 1));
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, cells * cells * 6);
    _ = fill(seed, cx, cz, vertices, indices, null);
    return .{ .vertices = vertices, .indices = indices };
}

/// Caller owns fixed storage. Cooperative cancellation is checked once per terrain row.
pub fn fill(seed: u64, cx: i32, cz: i32, vertices: []Mesh.Vertex, indices: []u32, cancel: ?Cancel) bool {
    std.debug.assert(vertices.len == vertex_count and indices.len == index_count);
    const ox = @as(f32, @floatFromInt(cx)) * extent - extent / 2;
    const oz = @as(f32, @floatFromInt(cz)) * extent - extent / 2;
    for (0..cells + 1) |z| {
        if (cancel) |c| if (c.token.load(.acquire) != c.expected) return false;
        for (0..cells + 1) |x| {
            const wx = ox + @as(f32, @floatFromInt(x)) * 2;
            const wz = oz + @as(f32, @floatFromInt(z)) * 2;
            const nx = Noise.height(seed, wx - 0.5, wz) - Noise.height(seed, wx + 0.5, wz);
            const nz = Noise.height(seed, wx, wz - 0.5) - Noise.height(seed, wx, wz + 0.5);
            const inv = 1 / @sqrt(nx * nx + 1 + nz * nz);
            vertices[z * (cells + 1) + x] = .{ .position = .{ wx, Noise.height(seed, wx, wz), wz }, .normal = .{ nx * inv, inv, nz * inv }, .uv = .{ wx / 4, wz / 4 }, .color = Biome.sample(seed, wx, wz).color() };
        }
    }
    for (0..cells) |z| {
        for (0..cells) |x| {
            const a: u32 = @intCast(z * (cells + 1) + x);
            const base = (z * cells + x) * 6;
            @memcpy(indices[base..][0..6], &[_]u32{ a, a + cells + 1, a + 1, a + 1, a + cells + 1, a + cells + 2 });
        }
    }
    return true;
}

test "adjacent chunks share positions and normals, including negative coordinates" {
    const a = try generate(std.testing.allocator, 42, -1, 0);
    defer a.deinit(std.testing.allocator);
    const b = try generate(std.testing.allocator, 42, 0, 0);
    defer b.deinit(std.testing.allocator);
    for (0..cells + 1) |z| {
        try std.testing.expectEqualDeep(a.vertices[z * (cells + 1) + cells], b.vertices[z * (cells + 1)]);
    }
    for (a.indices) |index| try std.testing.expect(index < a.vertices.len);
}

test "generation repeats for the same seed and changes with a different seed" {
    const a = try generate(std.testing.allocator, 42, 0, 0);
    defer a.deinit(std.testing.allocator);
    const b = try generate(std.testing.allocator, 42, 0, 0);
    defer b.deinit(std.testing.allocator);
    const c = try generate(std.testing.allocator, 43, 0, 0);
    defer c.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(Mesh.Vertex, a.vertices, b.vertices);
    try std.testing.expectEqualSlices(u32, a.indices, b.indices);
    try std.testing.expect(a.vertices[0].position[1] != c.vertices[0].position[1]);
}

fn allocationProbe(allocator: std.mem.Allocator) !void {
    const mesh = try generate(allocator, 42, 0, 0);
    defer mesh.deinit(allocator);
}

test "partial mesh allocation failure frees previous allocations" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationProbe, .{});
}
