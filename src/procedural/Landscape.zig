//! Deterministic landscape shaping and playable-site planning over imported heightmaps.
const std = @import("std");
const Heightmap = @import("Heightmap.zig");
const Noise = @import("Noise.zig");
const Seed = @import("Seed.zig");
const Landscape = @This();

pub const max_stamps = 32;
pub const cave_segments = 8;
pub const Biome = enum { wetland, meadow, forest, alpine };
pub const StampKind = enum { plateau, basin, mound, ridge };
pub const Stamp = struct {
    kind: StampKind,
    center: [2]f32,
    radius: f32,
    amount: f32,
    angle: f32 = 0,
};
pub const TempleSite = struct { position: [3]f32, yaw: f32, pad_radius: f32 };
pub const CaveSite = struct { entrance: [3]f32, yaw: f32, length: f32, depth: f32, radius: f32 };
pub const Features = struct { temple: ?TempleSite = null, cave: ?CaveSite = null };
pub const Surface = struct { height: f32, slope: f32, biome: Biome };

/// Applies smooth radial stamps in order; later edits may refine earlier terrain.
pub fn height(map: Heightmap, x: f32, z: f32, stamps: []const Stamp) ?f32 {
    var y = map.sample(x, z) orelse return null;
    for (stamps) |stamp| {
        if (!std.math.isFinite(stamp.radius) or stamp.radius <= 0) continue;
        const dx = x - stamp.center[0];
        const dz = z - stamp.center[1];
        const d = stampDistance(stamp, dx, dz);
        if (d >= stamp.radius) continue;
        const t = std.math.clamp(1 - d / stamp.radius, 0, 1);
        const falloff = t * t * (3 - 2 * t);
        switch (stamp.kind) {
            .plateau => y += (stamp.amount - y) * falloff,
            .basin => y -= @max(0, stamp.amount) * falloff,
            .mound, .ridge => y += stamp.amount * falloff,
        }
    }
    return y;
}

pub fn surface(map: Heightmap, seed: u64, x: f32, z: f32, stamps: []const Stamp, sea_level: f32, snow_line: f32) ?Surface {
    const y = height(map, x, z, stamps) orelse return null;
    const half_cell_x = map.settings.world_width / @as(f32, @floatFromInt(map.width - 1)) * 0.5;
    const half_cell_z = map.settings.world_depth / @as(f32, @floatFromInt(map.height - 1)) * 0.5;
    const left = height(map, x - half_cell_x, z, stamps) orelse y;
    const right = height(map, x + half_cell_x, z, stamps) orelse y;
    const north = height(map, x, z - half_cell_z, stamps) orelse y;
    const south = height(map, x, z + half_cell_z, stamps) orelse y;
    const dx = (right - left) / (2 * half_cell_x);
    const dz = (south - north) / (2 * half_cell_z);
    const slope = @sqrt(dx * dx + dz * dz);
    const moisture = Noise.value(Seed.mix(seed ^ 0x4c414e444d4f4953), x / 360, z / 360);
    const biome: Biome = if (y <= sea_level + 2)
        .wetland
    else if (y >= snow_line or slope > 0.78)
        .alpine
    else if (moisture > 0.59)
        .forest
    else
        .meadow;
    return .{ .height = y, .slope = slope, .biome = biome };
}

/// Finds stable, buildable landmarks; no random retry state or per-call allocation.
pub fn planFeatures(map: Heightmap, seed: u64) Features {
    var result: Features = .{};
    var temple_score: u64 = 0;
    var cave_score: u64 = 0;
    const min_extent = @min(map.settings.world_width, map.settings.world_depth);
    const spacing = min_extent / 18;
    for (0..17) |iz| for (0..17) |ix| {
        const x = (@as(f32, @floatFromInt(ix)) / 16 - 0.5) * map.settings.world_width * 0.84;
        const z = (@as(f32, @floatFromInt(iz)) / 16 - 0.5) * map.settings.world_depth * 0.84;
        const y = map.sample(x, z) orelse continue;
        const slope = localSlope(map, x, z, spacing) orelse continue;
        const gx: i64 = @intCast(ix);
        const gz: i64 = @intCast(iz);
        const score = Seed.at(seed ^ 0x54454d504c45, gx, gz);
        const normalized_height = (y - map.settings.base_height) / map.settings.elevation;
        if (slope < 0.18 and normalized_height > 0.12 and normalized_height < 0.88 and (result.temple == null or score > temple_score)) {
            temple_score = score;
            result.temple = .{ .position = .{ x, y, z }, .yaw = Seed.unit(Seed.mix(score)) * 2 * std.math.pi, .pad_radius = 14 };
        }
    };
    for (0..17) |iz| for (0..17) |ix| {
        const x = (@as(f32, @floatFromInt(ix)) / 16 - 0.5) * map.settings.world_width * 0.84;
        const z = (@as(f32, @floatFromInt(iz)) / 16 - 0.5) * map.settings.world_depth * 0.84;
        const y = map.sample(x, z) orelse continue;
        const slope = localSlope(map, x, z, spacing) orelse continue;
        if (slope > 0.42) continue;
        if (result.temple) |temple| if (distance2(x, z, temple.position[0], temple.position[2]) < min_extent * min_extent * 0.045) continue;
        const gx: i64 = @intCast(ix);
        const gz: i64 = @intCast(iz);
        const score = Seed.at(seed ^ 0x43415645454e54, gx, gz);
        const normalized_height = (y - map.settings.base_height) / map.settings.elevation;
        if (normalized_height > 0.08 and normalized_height < 0.78 and (result.cave == null or score > cave_score)) {
            cave_score = score;
            result.cave = .{
                .entrance = .{ x, y, z },
                .yaw = Seed.unit(Seed.mix(score)) * 2 * std.math.pi,
                .length = min_extent * (0.22 + Seed.unit(score) * 0.12),
                .depth = @min(48, map.settings.elevation * 0.3),
                .radius = 4.5,
            };
        }
    };
    return result;
}

/// Cave centerline points descend beneath the entrance while gently meandering.
pub fn cavePoint(site: CaveSite, index: u8, seed: u64) [3]f32 {
    const t = @as(f32, @floatFromInt(@min(index, cave_segments))) / cave_segments;
    const lateral = (Seed.unit(Seed.at(seed, index, 7)) - 0.5) * site.radius * 2;
    const forward: [2]f32 = .{ @sin(site.yaw), @cos(site.yaw) };
    const side: [2]f32 = .{ forward[1], -forward[0] };
    const sway = @sin(t * std.math.pi) * lateral;
    return .{
        site.entrance[0] + forward[0] * site.length * t + side[0] * sway,
        site.entrance[1] - 2 - site.depth * t + @sin(t * std.math.pi) * site.depth * 0.12,
        site.entrance[2] + forward[1] * site.length * t + side[1] * sway,
    };
}

fn stampDistance(stamp: Stamp, dx: f32, dz: f32) f32 {
    if (stamp.kind != .ridge) return @sqrt(dx * dx + dz * dz);
    const c = @cos(stamp.angle);
    const s = @sin(stamp.angle);
    const along = c * dx + s * dz;
    const across = -s * dx + c * dz;
    return @max(@abs(across), @abs(along) * 0.2);
}

fn localSlope(map: Heightmap, x: f32, z: f32, step: f32) ?f32 {
    const left = map.sample(x - step, z) orelse return null;
    const right = map.sample(x + step, z) orelse return null;
    const north = map.sample(x, z - step) orelse return null;
    const south = map.sample(x, z + step) orelse return null;
    const dx = (right - left) / (2 * step);
    const dz = (south - north) / (2 * step);
    return @sqrt(dx * dx + dz * dz);
}

fn distance2(x0: f32, z0: f32, x1: f32, z1: f32) f32 {
    const dx = x1 - x0;
    const dz = z1 - z0;
    return dx * dx + dz * dz;
}

fn flatMap(allocator: std.mem.Allocator) !Heightmap {
    const samples = try allocator.alloc(u16, 33 * 33);
    @memset(samples, 32768);
    return .{ .width = 33, .height = 33, .settings = .{ .world_width = 512, .world_depth = 512, .base_height = 0, .elevation = 100 }, .samples = samples };
}

test "terrain stamps form smooth temple pads, basins, and elongated ridges" {
    const map = try flatMap(std.testing.allocator);
    defer map.deinit(std.testing.allocator);
    const stamps = [_]Stamp{
        .{ .kind = .plateau, .center = .{ 0, 0 }, .radius = 40, .amount = 90 },
        .{ .kind = .basin, .center = .{ 100, 0 }, .radius = 30, .amount = 20 },
        .{ .kind = .ridge, .center = .{ -100, 0 }, .radius = 20, .amount = 15, .angle = 0 },
    };
    const base = map.sample(0, 0).?;
    try std.testing.expectApproxEqAbs(@as(f32, 90), height(map, 0, 0, &stamps).?, 0.01);
    try std.testing.expect(height(map, 100, 0, &stamps).? < base);
    try std.testing.expect(height(map, -100, 0, &stamps).? > base);
    try std.testing.expectApproxEqAbs(base, height(map, 0, 40, &stamps).?, 0.01);
}

test "biome classification and temple/cave plans are deterministic and terrain aware" {
    const map = try flatMap(std.testing.allocator);
    defer map.deinit(std.testing.allocator);
    const features = planFeatures(map, 8172);
    const again = planFeatures(map, 8172);
    try std.testing.expect(features.temple != null and features.cave != null);
    try std.testing.expectEqualDeep(features, again);
    const temple = features.temple.?;
    const site = surface(map, 8172, temple.position[0], temple.position[2], &.{}, 60, 90).?;
    try std.testing.expectEqual(Biome.wetland, site.biome);
    try std.testing.expect(site.slope < 0.18);
    const cave = features.cave.?;
    const start = cavePoint(cave, 0, 8172);
    const end = cavePoint(cave, cave_segments, 8172);
    try std.testing.expectApproxEqAbs(cave.entrance[1] - 2, start[1], 0.001);
    try std.testing.expect(end[1] < start[1] - 20);
    try std.testing.expectApproxEqAbs(cave.length, @sqrt(distance2(start[0], start[2], end[0], end[2])), cave.length * 0.1);
}
