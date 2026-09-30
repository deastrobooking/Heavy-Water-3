const std = @import("std");
const mach = @import("mach");
const Transform = @import("Transform.zig");
const Catalog = @import("../asset/Catalog.zig");
pub const mach_module = .world;
pub const mach_systems = .{ .init, .deinit };
pub const Renderable = struct { transform: Transform, tint: [4]f32 };
pub const max_props = 256;
/// A dynamic catalog-backed object, published to the renderer each simulation tick.
/// `size` scales the mesh per axis (before rotation) on top of the transform's uniform scale;
/// `rotation` is a unit quaternion (x, y, z, w). `lod`, when set, replaces `mesh` beyond
/// `lod_distance` from the camera; this is the only distance-based simplification tall placed
/// content gets today (roadmap phase 6, "streaming and level of detail for tall placed content").
pub const Prop = struct {
    mesh: Catalog.MeshHandle,
    transform: Transform,
    tint: [4]f32,
    size: [3]f32 = .{ 1, 1, 1 },
    rotation: [4]f32 = .{ 0, 0, 0, 1 },
    lod: Catalog.MeshHandle = .none,
    lod_distance: f32 = 0,

    pub fn effectiveMesh(self: Prop, camera_position: [3]f32) Catalog.MeshHandle {
        if (self.lod.eql(.none) or self.lod_distance <= 0) return self.mesh;
        const dx = self.transform.position[0] - camera_position[0];
        const dy = self.transform.position[1] - camera_position[1];
        const dz = self.transform.position[2] - camera_position[2];
        const squared = dx * dx + dy * dy + dz * dz;
        return if (squared > self.lod_distance * self.lod_distance) self.lod else self.mesh;
    }
};

test "prop LOD swaps to the coarse mesh beyond its distance and back within it" {
    const near: Catalog.MeshHandle = .{ .index = 1, .generation = 1 };
    const far: Catalog.MeshHandle = .{ .index = 2, .generation = 1 };
    const prop: Prop = .{ .mesh = near, .transform = .{ .position = .{ 0, 0, 0 } }, .tint = .{ 1, 1, 1, 1 }, .lod = far, .lod_distance = 100 };
    try std.testing.expect(prop.effectiveMesh(.{ 50, 0, 0 }).eql(near));
    try std.testing.expect(prop.effectiveMesh(.{ 150, 0, 0 }).eql(far));
    const no_lod: Prop = .{ .mesh = near, .transform = .{ .position = .{ 0, 0, 0 } }, .tint = .{ 1, 1, 1, 1 } };
    try std.testing.expect(no_lod.effectiveMesh(.{ 9000, 0, 0 }).eql(near));
}
/// Mach owns collection storage and generational IDs; app owns the lifetime of the world.
objects: mach.Objects(.{}, Renderable),
seed: u64 = 0,
/// Loaded before any other module initializes; immutable afterwards and shared across threads.
catalog: Catalog = .{},
allocator: std.mem.Allocator = undefined,

pub fn init(world: *@This(), allocator: std.mem.Allocator) !void {
    // Collection storage is initialized by Mach before module systems run.
    world.seed = 0;
    world.allocator = allocator;
    try world.catalog.loadSeeded(allocator, @import("options").seed);
}

/// Runs after the renderer has released its GPU copies.
pub fn deinit(world: *@This()) void {
    world.catalog.deinit(world.allocator);
}
