const mach = @import("mach");
const Transform = @import("Transform.zig");
pub const mach_module = .world;
pub const mach_systems = .{.init};
pub const Renderable = struct { transform: Transform, tint: [4]f32 };
/// Mach owns collection storage and generational IDs; app owns the lifetime of the world.
objects: mach.Objects(.{}, Renderable),
seed: u64 = 0,

pub fn init(world: *@This()) void {
    // Collection storage is initialized by Mach before module systems run.
    world.seed = 0;
}
