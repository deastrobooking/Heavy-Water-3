const mach = @import("mach");
const Transform = @import("Transform.zig");
pub const max_objects = 1000;
pub const mach_module = .world;
pub const mach_systems = .{.init};
pub const Renderable = struct { transform: Transform, tint: [4]f32 };
/// Mach owns collection storage and generational IDs; app owns the lifetime of the world.
objects: mach.Objects(.{}, Renderable),

pub fn init(world: *@This()) void {
    // Collection storage is initialized by Mach before module systems run.
    _ = world;
}
