const World = @import("../world/World.zig");

/// The test game selects the seed. Static content comes from streamed chunk recipes;
/// World.objects remains available for future interactive actors.
pub fn configure(world: *World, seed: u64) void {
    world.seed = seed;
}
