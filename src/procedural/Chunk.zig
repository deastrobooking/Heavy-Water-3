const std = @import("std");
const Noise = @import("Noise.zig");
const Biome = @import("Biome.zig");
const Hydrology = @import("Hydrology.zig");
const Mesh = @import("../render/Mesh.zig");
pub const cells = 64;
pub const extent = @import("../world/ChunkKey.zig").extent;
pub const terrain_vertex_count = (cells + 1) * (cells + 1);
pub const terrain_index_count = cells * cells * 6;
pub const max_river_lanes = 3;
pub const river_vertices_per_lane = (cells + 1) * 2 + 4;
pub const river_indices_per_lane = cells * 6 + 6;
pub const vertex_count = terrain_vertex_count + max_river_lanes * river_vertices_per_lane;
pub const index_count = terrain_index_count + max_river_lanes * river_indices_per_lane;
pub const Cancel = struct { token: *const std.atomic.Value(u64), expected: u64 };

/// Coordinates are integer chunk addresses; shared edges sample identical world positions.
pub fn generate(allocator: std.mem.Allocator, seed: u64, cx: i32, cz: i32) !Mesh {
    const vertices = try allocator.alloc(Mesh.Vertex, vertex_count);
    errdefer allocator.free(vertices);
    const indices = try allocator.alloc(u32, index_count);
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
            const height = Noise.height(seed, wx, wz);
            const nx = Noise.height(seed, wx - 0.5, wz) - Noise.height(seed, wx + 0.5, wz);
            const nz = Noise.height(seed, wx, wz - 0.5) - Noise.height(seed, wx, wz + 0.5);
            const inv = 1 / @sqrt(nx * nx + 1 + nz * nz);
            const slope = @sqrt(nx * nx + nz * nz);
            vertices[z * (cells + 1) + x] = .{ .position = .{ wx, height, wz }, .normal = .{ nx * inv, inv, nz * inv }, .uv = .{ wx / 4, wz / 4 }, .color = Biome.terrainColor(seed, wx, wz, height, slope) };
        }
    }
    for (0..cells) |z| {
        for (0..cells) |x| {
            const a: u32 = @intCast(z * (cells + 1) + x);
            const base = (z * cells + x) * 6;
            @memcpy(indices[base..][0..6], &[_]u32{ a, a + cells + 1, a + 1, a + 1, a + cells + 1, a + cells + 2 });
        }
    }
    if (!fillRivers(seed, ox, oz, vertices, indices)) return false;
    return true;
}

/// Appends blue river ribbons and actual vertical curtains at seeded waterfall drops.
/// Paths and waterfalls are evaluated in world space, so adjacent chunks meet exactly.
fn fillRivers(seed: u64, ox: f32, oz: f32, vertices: []Mesh.Vertex, indices: []u32) bool {
    var vertex_at: usize = terrain_vertex_count;
    var index_at: usize = terrain_index_count;
    const lane_center: i64 = @intFromFloat(@round((oz + extent * 0.5 - Hydrology.lane_offset) / Hydrology.lane_spacing));
    for ([_]i64{ lane_center - 1, lane_center, lane_center + 1 }) |lane| {
        var intersects = false;
        for (0..cells + 1) |step| {
            const x = ox + @as(f32, @floatFromInt(step)) * (extent / cells);
            const center_z = Hydrology.centerZ(seed, lane, x);
            if (center_z + Hydrology.water_width >= oz and center_z - Hydrology.water_width <= oz + extent) intersects = true;
        }
        if (!intersects) continue;
        if (vertex_at + river_vertices_per_lane > vertices.len or index_at + river_indices_per_lane > indices.len) return false;
        const first = vertex_at;
        for (0..cells + 1) |step| {
            const x = ox + @as(f32, @floatFromInt(step)) * (extent / cells);
            const z = Hydrology.centerZ(seed, lane, x);
            const level = Hydrology.level(seed, lane, x);
            const half = Hydrology.water_width * 0.5;
            vertices[vertex_at] = waterVertex(x, level, z - half, step, 0);
            vertices[vertex_at + 1] = waterVertex(x, level, z + half, step, 1);
            vertex_at += 2;
            if (step == 0) continue;
            const a: u32 = @intCast(first + (step - 1) * 2);
            const base = index_at + (step - 1) * 6;
            @memcpy(indices[base..][0..6], &[_]u32{ a, a + 1, a + 2, a + 1, a + 3, a + 2 });
        }
        index_at += cells * 6;

        const lane_seed = @import("Seed.zig").mix(seed ^ @as(u64, @bitCast(lane)) ^ 0x464c4f57);
        const phase = @floor(@import("Seed.zig").unit(lane_seed) * Hydrology.fall_period / 4) * 4;
        const fall_index = @ceil((ox + phase) / Hydrology.fall_period);
        const fall_x = fall_index * Hydrology.fall_period - phase;
        if (fall_x < ox or fall_x >= ox + extent) continue;
        const center_z = Hydrology.centerZ(seed, lane, fall_x);
        const high = Hydrology.level(seed, lane, fall_x - 0.01);
        const low = Hydrology.level(seed, lane, fall_x + 0.01);
        const half = Hydrology.water_width * 0.5;
        vertices[vertex_at] = waterVertex(fall_x, high, center_z - half, cells + 1, 0);
        vertices[vertex_at + 1] = waterVertex(fall_x, high, center_z + half, cells + 1, 1);
        vertices[vertex_at + 2] = waterVertex(fall_x, low, center_z - half, cells + 1, 0);
        vertices[vertex_at + 3] = waterVertex(fall_x, low, center_z + half, cells + 1, 1);
        const a: u32 = @intCast(vertex_at);
        const base = index_at;
        @memcpy(indices[base..][0..6], &[_]u32{ a, a + 2, a + 1, a + 1, a + 2, a + 3 });
        vertex_at += 4;
        index_at += 6;
    }
    // Zero-area reserved indices reference a valid existing vertex and are ignored by rasterization.
    @memset(indices[index_at..], 0);
    return true;
}

fn waterVertex(x: f32, y: f32, z: f32, step: usize, side: u32) Mesh.Vertex {
    return .{ .position = .{ x, y, z }, .normal = .{ 0, 1, 0 }, .uv = .{ @as(f32, @floatFromInt(step)) / 8, @floatFromInt(side) }, .color = Hydrology.color() };
}

test "streamed chunk includes a real waterfall curtain and joined river surface" {
    const Seed = @import("Seed.zig");
    const lane_seed = Seed.mix(42 ^ 0x464c4f57);
    const phase = @floor(Seed.unit(lane_seed) * Hydrology.fall_period / 4) * 4;
    const fall_x = Hydrology.fall_period - phase;
    const fall_z = Hydrology.centerZ(42, 0, fall_x);
    const cx: i32 = @intFromFloat(@floor((fall_x + extent / 2) / extent));
    const cz: i32 = @intFromFloat(@floor((fall_z + extent / 2) / extent));
    const mesh = try generate(std.testing.allocator, 42, cx, cz);
    defer mesh.deinit(std.testing.allocator);
    var lowest: f32 = std.math.inf(f32);
    var highest: f32 = -std.math.inf(f32);
    var colored = false;
    for (mesh.vertices[terrain_vertex_count..]) |vertex| {
        if (vertex.color[2] > 0.6 and vertex.color[1] > 0.5) colored = true;
        if (@abs(vertex.position[0] - fall_x) < 0.01) {
            lowest = @min(lowest, vertex.position[1]);
            highest = @max(highest, vertex.position[1]);
        }
    }
    try std.testing.expect(colored);
    try std.testing.expectApproxEqAbs(Hydrology.fall_drop, highest - lowest, 0.1);
    for (mesh.indices) |index| try std.testing.expect(index < mesh.vertices.len);
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
