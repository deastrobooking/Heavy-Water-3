//! Smooth, generated energy-weapon silhouettes shared by the held saber and its projectiles.
const std = @import("std");
const Mesh = @import("../render/Mesh.zig");

/// A continuous, swept greatblade with a curved edge and beveled-looking rounded cross section.
/// `core` makes a narrower inner ribbon for the white-hot plasma spine.
pub fn blade(allocator: std.mem.Allocator, core: bool) !Mesh {
    const segments = 24;
    const rings = segments + 1;
    const sides = 8;
    const vertices = try allocator.alloc(Mesh.Vertex, rings * sides);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, segments * sides * 6);
    errdefer allocator.free(indices);
    const factor: f32 = if (core) 0.34 else 1;
    for (0..rings) |i| {
        const t = @as(f32, @floatFromInt(i)) / segments;
        const width = factor * (0.075 + 0.17 * @sin(t * std.math.pi)) * (1 - 0.28 * t);
        const depth: f32 = if (core) 0.035 else 0.075;
        const curve = 0.24 * t * t;
        for (0..sides) |j| {
            const a = @as(f32, @floatFromInt(j)) / sides * 2 * std.math.pi;
            const x = @cos(a) * width;
            const y = @sin(a) * depth;
            const normal = [3]f32{ @cos(a) * 0.55, @sin(a), -0.12 };
            vertices[i * sides + j] = .{
                .position = .{ curve + x, y, t * 3.7 },
                .normal = normal,
                .uv = .{ @as(f32, @floatFromInt(j)) / sides, t },
            };
        }
    }
    var k: usize = 0;
    for (0..segments) |i| for (0..sides) |j| {
        const next = (j + 1) % sides;
        const a: u32 = @intCast(i * sides + j);
        const b: u32 = @intCast(i * sides + next);
        const c: u32 = @intCast((i + 1) * sides + j);
        const d: u32 = @intCast((i + 1) * sides + next);
        for ([_]u32{ a, b, c, b, d, c }) |index| {
            indices[k] = index;
            k += 1;
        }
    };
    return .{ .vertices = vertices, .indices = indices };
}

/// A smooth crescent ribbon in the local XY plane, aimed along +Z. The core width narrows
/// the ribbon and leaves its curved outer rim visible as a coloured corona.
pub fn wave(allocator: std.mem.Allocator, core: bool) !Mesh {
    const segments = 64;
    const vertices = try allocator.alloc(Mesh.Vertex, (segments + 1) * 4);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, segments * 12);
    errdefer allocator.free(indices);
    const scale: f32 = if (core) 0.58 else 1;
    for (0..segments + 1) |i| {
        const u = @as(f32, @floatFromInt(i)) / segments * 2 - 1;
        const edge = 0.38 * scale * @sqrt(@max(0, 1 - u * u));
        const x = u * 2.15 * scale;
        const y = (1 - u * u) * 1.45 * scale;
        const start = i * 4;
        vertices[start] = .{ .position = .{ x, y - edge / 2, -0.035 }, .normal = .{ 0, 0, 1 }, .uv = .{ u * 0.5 + 0.5, 0 } };
        vertices[start + 1] = .{ .position = .{ x, y + edge / 2, -0.035 }, .normal = .{ 0, 0, 1 }, .uv = .{ u * 0.5 + 0.5, 1 } };
        vertices[start + 2] = .{ .position = .{ x, y - edge / 2, 0.035 }, .normal = .{ 0, 0, -1 }, .uv = .{ u * 0.5 + 0.5, 0 } };
        vertices[start + 3] = .{ .position = .{ x, y + edge / 2, 0.035 }, .normal = .{ 0, 0, -1 }, .uv = .{ u * 0.5 + 0.5, 1 } };
    }
    var k: usize = 0;
    for (0..segments) |i| {
        const a: u32 = @intCast(i * 4);
        const b = a + 4;
        for ([_]u32{ a, b, a + 1, a + 1, b, b + 1, a + 2, a + 3, b + 2, a + 3, b + 3, b + 2 }) |index| {
            indices[k] = index;
            k += 1;
        }
    }
    return .{ .vertices = vertices, .indices = indices };
}
