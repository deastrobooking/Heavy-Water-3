const std = @import("std");
const mach = @import("mach");
const Transform = @import("Transform.zig");
const Catalog = @import("../asset/Catalog.zig");
pub const mach_module = .world;
pub const mach_systems = .{ .init, .deinit };
pub const Renderable = struct { transform: Transform, tint: [4]f32 };
pub const max_props = 16;
/// A dynamic catalog-backed object, published to the renderer each simulation tick.
pub const Prop = struct { mesh: Catalog.MeshHandle, transform: Transform, tint: [4]f32 };
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
    try world.catalog.load(allocator);
}

/// Runs after the renderer has released its GPU copies.
pub fn deinit(world: *@This()) void {
    world.catalog.deinit(world.allocator);
}
