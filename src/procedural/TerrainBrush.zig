//! Sculpting brushes over the terrain edit layer. A dab reads the ground as it stands (generated
//! height plus earlier edits), computes every new offset first, then writes them, so a dab never
//! reacts to its own half-finished result and a refusal changes nothing.
const std = @import("std");
const CityHeightmaps = @import("CityHeightmaps.zig");
const TerrainEdit = @import("../world/TerrainEdit.zig");

pub const Kind = enum { raise, lower, level, smooth };
pub const max_radius: f32 = 24;
pub const min_radius: f32 = 2;

pub const Dab = struct {
    kind: Kind,
    x: f32,
    z: f32,
    radius: f32 = 8,
    /// Meters moved at the centre per dab (raise, lower) or the blend fraction (level, smooth).
    strength: f32 = 0.5,
    /// The height `level` pulls toward; the tool fixes it where the stroke starts.
    target: f32 = 0,
};

const side = @as(usize, @intFromFloat(max_radius * 2 / TerrainEdit.spacing)) + 3;

fn weight(distance: f32, radius: f32) f32 {
    const t = std.math.clamp(1 - distance / radius, 0, 1);
    return t * t * (3 - 2 * t);
}

/// Apply one dab. Returns how many lattice points changed.
pub fn apply(edit: *TerrainEdit, seed: u64, dab: Dab) TerrainEdit.Error!usize {
    const radius = std.math.clamp(dab.radius, min_radius, max_radius);
    const s = TerrainEdit.spacing;
    const ix0: i32 = @intFromFloat(@floor((dab.x - radius) / s));
    const iz0: i32 = @intFromFloat(@floor((dab.z - radius) / s));
    const ix1: i32 = @intFromFloat(@ceil((dab.x + radius) / s));
    const iz1: i32 = @intFromFloat(@ceil((dab.z + radius) / s));
    const w: usize = @intCast(ix1 - ix0 + 1);
    const h: usize = @intCast(iz1 - iz0 + 1);
    std.debug.assert(w <= side and h <= side);
    try edit.reserve(ix0, iz0, ix1, iz1);

    // The ground as it stands over the window, so smooth and level react to the same snapshot.
    var total: [side * side]f32 = undefined;
    var wanted: [side * side]i16 = undefined;
    for (0..h) |j| for (0..w) |i| {
        const ix = ix0 + @as(i32, @intCast(i));
        const iz = iz0 + @as(i32, @intCast(j));
        total[j * side + i] = CityHeightmaps.heightAt(seed, @as(f32, @floatFromInt(ix)) * s, @as(f32, @floatFromInt(iz)) * s);
    };
    for (0..h) |j| for (0..w) |i| {
        const ix = ix0 + @as(i32, @intCast(i));
        const iz = iz0 + @as(i32, @intCast(j));
        const px = @as(f32, @floatFromInt(ix)) * s;
        const pz = @as(f32, @floatFromInt(iz)) * s;
        const k = weight(std.math.hypot(px - dab.x, pz - dab.z), radius);
        const current = edit.get(ix, iz);
        wanted[j * side + i] = current;
        if (k <= 0) continue;
        const here = total[j * side + i];
        const blend = std.math.clamp(dab.strength, 0, 1);
        const move: f32 = switch (dab.kind) {
            .raise => dab.strength * k,
            .lower => -dab.strength * k,
            .level => (dab.target - here) * blend * k,
            .smooth => blk: {
                var sum: f32 = 0;
                for ([_][2]i32{ .{ -1, 0 }, .{ 1, 0 }, .{ 0, -1 }, .{ 0, 1 } }) |o| {
                    const ni = @as(i32, @intCast(i)) + o[0];
                    const nj = @as(i32, @intCast(j)) + o[1];
                    sum += if (ni >= 0 and nj >= 0 and ni < w and nj < h)
                        total[@as(usize, @intCast(nj)) * side + @as(usize, @intCast(ni))]
                    else
                        CityHeightmaps.heightAt(seed, @as(f32, @floatFromInt(ix + o[0])) * s, @as(f32, @floatFromInt(iz + o[1])) * s);
                }
                break :blk (sum / 4 - here) * blend * k;
            },
        };
        const step: i32 = @intFromFloat(@round(move / TerrainEdit.unit));
        wanted[j * side + i] = @intCast(std.math.clamp(@as(i32, current) + step, -TerrainEdit.max_units, TerrainEdit.max_units));
    };
    var changed: usize = 0;
    for (0..h) |j| for (0..w) |i| {
        if (edit.put(ix0 + @as(i32, @intCast(i)), iz0 + @as(i32, @intCast(j)), wanted[j * side + i])) changed += 1;
    };
    return changed;
}

test "raise lifts the ground under the brush and the physics-facing height follows" {
    const Terrain = @import("Terrain.zig");
    const edit = try TerrainEdit.create(std.testing.allocator);
    defer edit.destroy();
    TerrainEdit.active.store(edit, .release);
    defer TerrainEdit.active.store(null, .release);
    const before = Terrain.surface(42, 100, 100).height;
    const outside = Terrain.surface(42, 130, 100).height;
    edit.beginStroke();
    for (0..8) |_| _ = try apply(edit, 42, .{ .kind = .raise, .x = 100, .z = 100, .radius = 8, .strength = 1 });
    try std.testing.expect(Terrain.surface(42, 100, 100).height - before > 4);
    try std.testing.expectApproxEqAbs(outside, Terrain.surface(42, 130, 100).height, 1e-4);
    try std.testing.expect(edit.undo());
    try std.testing.expectApproxEqAbs(before, Terrain.surface(42, 100, 100).height, 1e-4);
}

test "level pulls the ground toward the target and smooth never adds relief" {
    const edit = try TerrainEdit.create(std.testing.allocator);
    defer edit.destroy();
    TerrainEdit.active.store(edit, .release);
    defer TerrainEdit.active.store(null, .release);
    const target = CityHeightmaps.heightAt(42, 300, 300) + 3;
    for (0..30) |_| _ = try apply(edit, 42, .{ .kind = .level, .x = 300, .z = 300, .radius = 10, .strength = 0.5, .target = target });
    try std.testing.expectApproxEqAbs(target, CityHeightmaps.heightAt(42, 300, 300), 0.1);
    var before: f32 = 0;
    var after: f32 = 0;
    for ([_]f32{ 296, 298, 302, 304 }) |x| before += @abs(CityHeightmaps.heightAt(42, x, 300) - target);
    _ = try apply(edit, 42, .{ .kind = .smooth, .x = 300, .z = 300, .radius = 10, .strength = 1 });
    for ([_]f32{ 296, 298, 302, 304 }) |x| after += @abs(CityHeightmaps.heightAt(42, x, 300) - target);
    try std.testing.expect(after <= before + 0.01);
}

test "a refused dab leaves the terrain exactly as it was" {
    const edit = try TerrainEdit.create(std.testing.allocator);
    defer edit.destroy();
    var tx: i32 = 0;
    while (tx < TerrainEdit.tile_capacity) : (tx += 1) try edit.reserve(tx * 64 + 5000, 0, tx * 64 + 5000, 0);
    const revision = edit.revision;
    try std.testing.expectError(error.TerrainEditFull, apply(edit, 42, .{ .kind = .raise, .x = 0, .z = 0, .radius = 8 }));
    try std.testing.expectEqual(revision, edit.revision);
}

test "sculpted chunks stay seamless and Terrain.surface still matches the mesh" {
    const Chunk = @import("Chunk.zig");
    const Terrain = @import("Terrain.zig");
    const edit = try TerrainEdit.create(std.testing.allocator);
    defer edit.destroy();
    TerrainEdit.active.store(edit, .release);
    defer TerrainEdit.active.store(null, .release);
    // A mound on the corner shared by chunks (0,0), (1,0), (0,1) and (1,1).
    for (0..6) |_| _ = try apply(edit, 42, .{ .kind = .raise, .x = 64, .z = 64, .radius = 12, .strength = 1 });
    const a = try Chunk.generate(std.testing.allocator, 42, 0, 0);
    defer a.deinit(std.testing.allocator);
    const b = try Chunk.generate(std.testing.allocator, 42, 1, 0);
    defer b.deinit(std.testing.allocator);
    for (0..65) |k| try std.testing.expectEqual(a.vertices[k * 65 + 64].position[1], b.vertices[k * 65].position[1]);
    for (a.vertices[0..Chunk.terrain_vertex_count]) |v| try std.testing.expectApproxEqAbs(v.position[1], Terrain.surface(42, v.position[0], v.position[2]).height, 1e-4);
}
